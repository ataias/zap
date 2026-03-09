#!/usr/bin/env bash
# Unified shell completion tests for ZAP
# Usage: bash test_completions.sh /path/to/shell-completion [shell]
#
# Tests live completion behavior across fish, bash, and zsh using expect.
# Script content/structure is validated by Zig unit tests; this only tests
# that completions work correctly in a real shell.
set -euo pipefail

binary="$1"
only_shell="${2:-}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
expect_helper="$script_dir/complete.expect"

source "$script_dir/shell_test_helpers.sh"

run_tests_for_shell() {
    local shell="$1"
    current_shell="$shell"

    echo "=== $shell ==="

    # Root level: subcommand names
    local root
    root=$(get_completions "$shell" "shell-completion ")
    assert_contains "root offers deploy" "$root" "deploy"
    assert_contains "root offers status" "$root" "status"
    assert_not_contains "root hides debug-info" "$root" "debug-info"

    # Enum option: --format offers variant names
    local format
    format=$(get_completions "$shell" "shell-completion deploy --format ")
    assert_contains "--format offers json" "$format" "json"
    assert_contains "--format offers yaml" "$format" "yaml"
    assert_contains "--format offers text" "$format" "text"

    # Custom values: --target offers hint values
    local target
    target=$(get_completions "$shell" "shell-completion deploy --target ")
    assert_contains "--target offers prod" "$target" "prod"
    assert_contains "--target offers staging" "$target" "staging"
    assert_contains "--target offers dev" "$target" "dev"

    # File extension filtering: --config only shows .json and .yaml
    local config
    config=$(get_completions_in_dir "$shell" "shell-completion deploy --config " "$tmpdir")
    assert_contains "--config offers json file" "$config" "config.json"
    assert_contains "--config offers yaml file" "$config" "schema.yaml"
    assert_not_contains "--config hides txt file" "$config" "notes.txt"
    assert_not_contains "--config hides md file" "$config" "readme.md"
    assert_contains "--config offers directories" "$config" "subdir"

    # File extension filtering with path prefix: --config $tmpdir/
    local config_path
    config_path=$(get_completions "$shell" "shell-completion deploy --config $tmpdir/")
    assert_contains "--config path offers json" "$config_path" "config.json"
    assert_contains "--config path offers yaml" "$config_path" "schema.yaml"
    assert_not_contains "--config path hides txt" "$config_path" "notes.txt"

    # Value completions don't leak file names (tests -f flag)
    local target_in_dir
    target_in_dir=$(get_completions_in_dir "$shell" "shell-completion deploy --target " "$tmpdir")
    assert_contains "--target still offers prod" "$target_in_dir" "prod"
    assert_not_contains "--target doesn't show files" "$target_in_dir" "config.json"

    # Deploy subcommand: all visible flags offered
    local deploy_flags
    deploy_flags=$(get_completions "$shell" "shell-completion deploy -")
    assert_contains "deploy offers --target" "$deploy_flags" "--target"
    assert_contains "deploy offers --format" "$deploy_flags" "--format"
    assert_contains "deploy offers --port" "$deploy_flags" "--port"
    assert_contains "deploy offers --verbose" "$deploy_flags" "--verbose"
    assert_contains "deploy offers --count" "$deploy_flags" "--count"
    assert_contains "deploy offers --service" "$deploy_flags" "--service"
    assert_contains "deploy offers --config" "$deploy_flags" "--config"
    assert_contains "deploy offers --help" "$deploy_flags" "--help"
    assert_not_contains "deploy hides --debug-trace" "$deploy_flags" "--debug-trace"

    # Status subcommand
    local status_flags
    status_flags=$(get_completions "$shell" "shell-completion status -")
    assert_contains "status offers --verbose" "$status_flags" "--verbose"
    assert_contains "status offers --help" "$status_flags" "--help"

    # Root-level --help
    # bash returns options and subcommands together via compgen -W, so --help
    # appears in the same "shell-completion " query as deploy/status.
    # fish and zsh only show subcommands for a bare "shell-completion "; options
    # require a "--" prefix to appear in the candidate list.
    case "$shell" in
        bash)
            assert_contains "root offers --help" "$root" "--help"
            ;;
        fish|zsh)
            local root_opts
            root_opts=$(get_completions "$shell" "shell-completion --")
            assert_contains "root offers --help" "$root_opts" "--help"
            ;;
    esac

    # Custom command completions: --service values from `echo web api worker`
    local service
    service=$(get_completions "$shell" "shell-completion deploy --service ")
    assert_contains "--service offers web" "$service" "web"
    assert_contains "--service offers api" "$service" "api"
    assert_contains "--service offers worker" "$service" "worker"

    # Non-repeating flags
    case "$shell" in
        bash)
            local after_format
            after_format=$(get_completions bash "shell-completion deploy --format json ")
            assert_not_contains "--format not repeated" "$after_format" "--format"
            assert_contains "other opts after --format" "$after_format" "--verbose"

            local after_count
            after_count=$(get_completions bash "shell-completion deploy --count --count ")
            assert_contains "counted --count repeats" "$after_count" "--count"
            ;;
        fish)
            local after_verbose
            after_verbose=$(get_completions fish "shell-completion deploy --verbose -")
            assert_not_contains "--verbose not repeated" "$after_verbose" "--verbose"
            assert_contains "--format still offered" "$after_verbose" "--format"

            local after_count
            after_count=$(get_completions fish "shell-completion deploy --count -")
            assert_contains "counted --count repeats" "$after_count" "--count"
            ;;
        zsh)
            local after_verbose
            after_verbose=$(get_zsh_completion_lines "shell-completion deploy --verbose --")
            assert_not_contains "--verbose not repeated" "$after_verbose" "--verbose"
            assert_contains "--format still offered" "$after_verbose" "--format"

            local after_count
            after_count=$(get_zsh_completion_lines "shell-completion deploy --count --")
            assert_contains "counted --count repeats" "$after_count" "--count"
            ;;
    esac

    echo ""
}

tmpdir=$(mktemp -d)
touch "$tmpdir/config.json" "$tmpdir/schema.yaml" "$tmpdir/notes.txt" "$tmpdir/readme.md"
mkdir -p "$tmpdir/subdir"
trap 'rm -rf "$tmpdir"' EXIT

echo "Running unified shell completion tests..."
echo ""

if [[ -n "$only_shell" ]]; then
    shells=("$only_shell")
else
    shells=(fish bash zsh)
fi

for shell in "${shells[@]}"; do
    if ! command -v "$shell" >/dev/null 2>&1; then
        echo "SKIP: $shell not found"
        continue
    fi
    run_tests_for_shell "$shell"
done

print_results
