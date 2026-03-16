#!/usr/bin/env bash
# Shell completion tests for nested subcommands
# Usage: bash test_nested_completions.sh /path/to/nested [shell]
set -euo pipefail

binary="$1"
only_shell="${2:-}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
expect_helper="$script_dir/complete.expect"

source "$script_dir/shell_test_helpers.sh"

run_tests_for_shell() {
    local shell="$1"
    current_shell="$shell"

    echo "=== $shell (nested) ==="

    # Root level: subcommand names
    local root
    root=$(get_completions "$shell" "nested ")
    assert_contains "root offers server" "$root" "server"
    assert_contains "root offers version" "$root" "version"

    # Server level: sub-subcommand names
    # zsh completes the common prefix "st" on first TAB when both "start" and
    # "stop" match, so we disambiguate by typing enough characters to uniquely
    # match each candidate.
    case "$shell" in
        zsh)
            local server_start
            server_start=$(get_completions "$shell" "nested server star")
            assert_contains "server offers start" "$server_start" "start"
            local server_stop
            server_stop=$(get_completions "$shell" "nested server sto")
            assert_contains "server offers stop" "$server_stop" "stop"
            ;;
        *)
            local server
            server=$(get_completions "$shell" "nested server ")
            assert_contains "server offers start" "$server" "start"
            assert_contains "server offers stop" "$server" "stop"
            ;;
    esac

    # Start sub-subcommand: flags
    local start_flags
    start_flags=$(get_completions "$shell" "nested server start -")
    assert_contains "start offers --port" "$start_flags" "--port"
    assert_contains "start offers --help" "$start_flags" "--help"

    # Stop sub-subcommand: flags
    local stop_flags
    stop_flags=$(get_completions "$shell" "nested server stop -")
    assert_contains "stop offers --force" "$stop_flags" "--force"
    assert_contains "stop offers --help" "$stop_flags" "--help"

    echo ""
}

echo "Running nested subcommand completion tests..."
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
