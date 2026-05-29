#!/usr/bin/env bash
#
# Run the full CI pipeline locally inside a Linux container using Apple
# Container (https://github.com/apple/container).
#
# The repo is copied INTO the image at build time (no bind mount), which mirrors
# CI's fresh checkout and avoids virtiofs build-cache instability.
#
# Mirrors .github/workflows/ci.yml:
#   lint                   -> zig fmt --check .
#   test                   -> zig build test for each optimize mode
#   test-shell-completions -> zig build test-shell-completions (fish/zsh/bash/expect)
#   test-as-dependency     -> test/consumer/test_as_dependency.sh
#   cross-compile          -> zig build -Dtarget=... for each CI target
#
# Usage:
#   scripts/ci.sh [job]
#
#   job is one of: all (default), lint, test, completions, dependency, cross
#
# Environment overrides:
#   ZIG_VERSION   Zig version to install in the image (default: 0.16.0)
#   IMAGE         Image tag to build/use (default: zap-ci:local)
#   NO_BUILD=1    Skip the image build; reuse the existing image (and its code copy)
#   REBUILD=1     Force a clean image rebuild (--no-cache)
#   CI_CPUS       CPUs allocated to the run container (default: 4)
#   CI_MEMORY     Memory allocated to the run container (default: 6G)
#
set -euo pipefail

JOB="${1:-all}"
ZIG_VERSION="${ZIG_VERSION:-0.16.0}"
IMAGE="${IMAGE:-zap-ci:local}"
CI_CPUS="${CI_CPUS:-4}"
CI_MEMORY="${CI_MEMORY:-6G}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

err() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || err "Apple Container only runs on macOS (this host is $(uname -s))."
command -v container >/dev/null 2>&1 || err "the 'container' CLI was not found. Install Apple Container: https://github.com/apple/container"

case "$JOB" in
  all|lint|test|completions|dependency|cross) ;;
  *) err "unknown job '$JOB' (expected: all, lint, test, completions, dependency, cross)" ;;
esac

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Apple Container needs its system services (and the buildkit builder) running
# before run/build. These are idempotent; ignore "already running" noise.
container system start  >/dev/null 2>&1 || true
container builder start >/dev/null 2>&1 || true

# --- Build the CI image -----------------------------------------------------
# Lay out the build context: the repo as a single tarball (minus build
# artifacts, keeping .git for the test-as-dependency git+file fetch) plus the
# inner pipeline script. Apple Container's build context only transfers
# top-level files -- nested directories are silently dropped -- so the repo is
# shipped as one tarball and unpacked in a RUN step rather than COPYed as a tree.
# Zig is installed from the official download index so the tarball filename
# format is not hardcoded, and the arch is detected from the container itself.
if [ "${NO_BUILD:-0}" != "1" ]; then
  CTX="$WORK_DIR/ctx"
  mkdir -p "$CTX"
  tar -C "$REPO_ROOT" \
      --exclude=./.zig-cache --exclude=./zig-out --exclude=./workspaces \
      -czf "$CTX/app.tar.gz" .

  cat > "$CTX/ci-inner.sh" <<'INNER_EOF'
#!/usr/bin/env bash
set -euo pipefail

export ZIG_LOCAL_CACHE_DIR=/tmp/zig-local-cache
export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache
cd /src
git config --global --add safe.directory /src >/dev/null 2>&1 || true

section() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }

job_lint() {
  section "lint: zig fmt --check ."
  zig fmt --check .
}

job_test() {
  for opt in Debug ReleaseSafe ReleaseFast ReleaseSmall; do
    section "test: zig build test -Doptimize=$opt"
    zig build test -Doptimize="$opt"
  done
}

job_completions() {
  section "test-shell-completions: zig build test-shell-completions"
  zig build test-shell-completions
}

job_dependency() {
  section "test-as-dependency"
  # Local analog of CI's git+https://...#<sha>: fetch the committed HEAD of the
  # copied repo over git+file. Uncommitted working-tree changes are not seen,
  # matching CI, which tests the pushed commit.
  sha="$(git -C /src rev-parse HEAD)"
  bash test/consumer/test_as_dependency.sh "git+file:///src#$sha"
}

job_cross() {
  for t in aarch64-linux x86_64-macos aarch64-macos x86_64-windows x86_64-freebsd aarch64-freebsd; do
    section "cross-compile: zig build -Dtarget=$t"
    zig build -Dtarget="$t"
  done
}

case "${1:-all}" in
  lint)        job_lint ;;
  test)        job_test ;;
  completions) job_completions ;;
  dependency)  job_dependency ;;
  cross)       job_cross ;;
  all)         job_lint; job_test; job_completions; job_dependency; job_cross ;;
esac

printf '\n\033[1;32mCI passed.\033[0m\n'
INNER_EOF

  cat > "$WORK_DIR/Dockerfile" <<DOCKERFILE
FROM docker.io/library/debian:bookworm-slim
ARG ZIG_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \\
      bash ca-certificates curl expect fish git jq xz-utils zsh \\
    && rm -rf /var/lib/apt/lists/*
RUN set -eux; \\
    arch="\$(uname -m)"; \\
    url="\$(curl -fsSL https://ziglang.org/download/index.json \\
            | jq -r --arg v "\$ZIG_VERSION" --arg a "\$arch" '.[\$v][\$a+"-linux"].tarball')"; \\
    [ -n "\$url" ] && [ "\$url" != "null" ] || { echo "no zig \$ZIG_VERSION tarball for \$arch-linux" >&2; exit 1; }; \\
    curl -fsSL "\$url" -o /tmp/zig.tar.xz; \\
    mkdir -p /opt/zig; \\
    tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1; \\
    ln -s /opt/zig/zig /usr/local/bin/zig; \\
    rm /tmp/zig.tar.xz; \\
    zig version
COPY app.tar.gz /tmp/app.tar.gz
COPY ci-inner.sh /usr/local/bin/ci-inner.sh
RUN mkdir -p /src && tar -xzf /tmp/app.tar.gz -C /src && rm /tmp/app.tar.gz
WORKDIR /src
DOCKERFILE

  build_args=(--tag "$IMAGE" --build-arg "ZIG_VERSION=$ZIG_VERSION" --file "$WORK_DIR/Dockerfile")
  [ "${REBUILD:-0}" = "1" ] && build_args+=(--no-cache)
  echo ">> building image $IMAGE (zig $ZIG_VERSION, code copied in)"
  container build "${build_args[@]}" "$CTX"
fi

# --- Run --------------------------------------------------------------------
echo ">> running job '$JOB' in $IMAGE"
container run --rm \
  --cpus "$CI_CPUS" \
  --memory "$CI_MEMORY" \
  "$IMAGE" \
  bash /usr/local/bin/ci-inner.sh "$JOB"
