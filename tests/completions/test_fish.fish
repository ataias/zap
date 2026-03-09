#!/usr/bin/env fish
# Fish shell completion integration tests for ZAP
# Usage: fish test_fish.fish /path/to/shell-completion

set binary $argv[1]
set failures 0
set tests 0

function assert_contains
    set -l description $argv[1]
    set -l haystack $argv[2]
    set -l needle $argv[3]
    set tests (math $tests + 1)
    if string match -q -- "*$needle*" $haystack
        echo "  PASS: $description"
    else
        echo "  FAIL: $description"
        echo "    expected to find: $needle"
        echo "    in: $haystack"
        set failures (math $failures + 1)
    end
end

function assert_not_contains
    set -l description $argv[1]
    set -l haystack $argv[2]
    set -l needle $argv[3]
    set tests (math $tests + 1)
    if string match -q -- "*$needle*" $haystack
        echo "  FAIL: $description"
        echo "    expected NOT to find: $needle"
        echo "    in: $haystack"
        set failures (math $failures + 1)
    else
        echo "  PASS: $description"
    end
end

# Generate the completion script to a temp file
set tmpfile (mktemp /tmp/zap_fish_test.XXXXXX)
$binary --generate-completion-script fish > $tmpfile 2>&1
set gen_status $status

if test $gen_status -ne 0
    echo "FAIL: failed to generate completion script (exit $gen_status)"
    cat $tmpfile
    rm -f $tmpfile
    exit 1
end

set script (cat $tmpfile)

# Source the generated script
source $tmpfile
if test $status -ne 0
    echo "FAIL: generated script has syntax errors"
    rm -f $tmpfile
    exit 1
end
rm -f $tmpfile

echo "Running fish completion tests..."

# Root-level: subcommand names are offered
set completions (complete -C "shell-completion ")
assert_contains "root offers deploy subcommand" "$completions" "deploy"
assert_contains "root offers status subcommand" "$completions" "status"

# Root-level: --help is offered (when typing -)
set flag_completions (complete -C "shell-completion -")
assert_contains "root offers --help" "$flag_completions" "--help"

# Root-level: hidden subcommand NOT offered
assert_not_contains "root hides debug-info" "$completions" "debug-info"

# Subcommand level: correct flags for deploy
set completions (complete -C "shell-completion deploy -")
assert_contains "deploy offers --target" "$completions" "--target"
assert_contains "deploy offers --format" "$completions" "--format"
assert_contains "deploy offers --port" "$completions" "--port"
assert_contains "deploy offers --verbose" "$completions" "--verbose"
assert_contains "deploy offers --help" "$completions" "--help"

# Subcommand level: hidden field NOT offered
assert_not_contains "deploy hides --debug-trace" "$completions" "--debug-trace"

# Enum option: variant names in generated script
assert_contains "format enum values in script" "$script" "json yaml text"

# values hint: listed values in generated script
assert_contains "target values in script" "$script" "prod staging dev"

# Description present in script
assert_contains "deploy description in script" "$script" "Deploy the application"

echo ""
echo "Results: $tests tests, $failures failures"

if test $failures -gt 0
    exit 1
end
