#!/usr/bin/env bash
set -euo pipefail

# Test that zap works correctly when consumed as a packaged dependency.
# This simulates what happens when an external project fetches zap,
# where only the files listed in build.zig.zon .paths are included.
#
# Usage:
#   test_as_dependency.sh <zig-fetch-url>
#
# Example:
#   test_as_dependency.sh "git+https://github.com/ataias/zap.git#abc123"

ZAP_URL="${1:?Usage: test_as_dependency.sh <zig-fetch-url>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

ZAP_HASH=$(zig fetch "$ZAP_URL")

CONSUMER_DIR="$WORK_DIR/consumer"
mkdir -p "$CONSUMER_DIR/src"
cp "$SCRIPT_DIR/build.zig" "$CONSUMER_DIR/build.zig"
cp "$SCRIPT_DIR/src/main.zig" "$CONSUMER_DIR/src/main.zig"

cat > "$CONSUMER_DIR/build.zig.zon" << EOF
.{
    .name = .zap_consumer_test,
    .version = "0.0.0",
    .fingerprint = 0xa4789a78408a3a86,
    .dependencies = .{
        .zap = .{
            .url = "$ZAP_URL",
            .hash = "$ZAP_HASH",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
EOF

cd "$CONSUMER_DIR"
zig build
./zig-out/bin/consumer --test-flag
