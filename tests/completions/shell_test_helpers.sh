#!/usr/bin/env bash
# Shared helpers for shell completion tests

if [[ "$(uname)" == "Darwin" ]]; then
    if ! command -v gsed >/dev/null 2>&1; then
        echo "ERROR: gsed is required on macOS (brew install gnu-sed)" >&2
        exit 1
    fi
    SED=gsed
else
    SED=sed
fi

failures=0
tests=0
current_shell=""

assert_contains() {
    local description="$1"
    local haystack="$2"
    local needle="$3"
    tests=$((tests + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: [$current_shell] $description"
    else
        echo "  FAIL: [$current_shell] $description"
        echo "    expected to find: $needle"
        echo "    in: $haystack"
        failures=$((failures + 1))
    fi
}

assert_not_contains() {
    local description="$1"
    local haystack="$2"
    local needle="$3"
    tests=$((tests + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  FAIL: [$current_shell] $description"
        echo "    expected NOT to find: $needle"
        echo "    in: $haystack"
        failures=$((failures + 1))
    else
        echo "  PASS: [$current_shell] $description"
    fi
}

# Get completions from a shell via the expect helper, stripping escape codes.
# Requires $expect_helper and $binary to be set by the caller.
get_completions() {
    local shell="$1"
    local cmdline="$2"
    local raw
    raw=$(expect "$expect_helper" "$shell" "$binary" "$cmdline" 2>/dev/null)
    echo "$raw" | $SED $'s/\033\\[[?0-9;]*[a-zA-Z]//g' | tr -d '\r' | tr -cd '[:print:]\n\t'
}

get_completions_in_dir() {
    local shell="$1"
    local cmdline="$2"
    local dir="$3"
    local raw
    raw=$(expect "$expect_helper" "$shell" "$binary" "$cmdline" "$dir" 2>/dev/null)
    echo "$raw" | $SED $'s/\033\\[[?0-9;]*[a-zA-Z]//g' | tr -d '\r' | tr -cd '[:print:]\n\t'
}

# Zsh tab output includes the typed command echoed back.
# Extract only completion candidate lines for non-repeating checks.
get_zsh_completion_lines() {
    local cmdline="$1"
    get_completions zsh "$cmdline" | $SED 's/shell-completion.*//' | grep '^ *--' | grep ' -- ' || true
}

print_results() {
    echo "Results: $tests tests, $failures failures"
    [[ $failures -eq 0 ]]
}
