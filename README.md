# zap

> **Work in progress** -- the API is not yet stable and may change.

A CLI argument parsing library for Zig that uses compile-time reflection to turn
struct definitions into fully featured command-line interfaces. No macros, no
code generation, no runtime overhead -- just define a struct and `zap.run` it.

Zero dependencies beyond the Zig standard library.

## Quick start

```zig
const std = @import("std");
const zap = @import("zap");

const Add = struct {
    pub const meta: zap.CommandMeta = .{
        .description = "Add numbers and print the result",
    };

    verbose: bool = false,
    values: []const i64,

    pub fn run(self: @This(), init: std.process.Init) !void {
        var sum: i64 = 0;
        for (self.values) |v| sum += v;

        var buf: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        if (self.verbose) {
            for (self.values, 0..) |v, i| {
                if (i > 0) try writer.interface.writeAll(" + ");
                try writer.interface.print("{d}", .{v});
            }
            try writer.interface.print(" = {d}\n", .{sum});
        } else {
            try writer.interface.print("{d}\n", .{sum});
        }
        try writer.interface.flush();
    }
};

pub fn main(init: std.process.Init) !void {
    return zap.run(Add, init);
}
```

```
$ add 1 2 3
6

$ add --verbose 1 2 3
1 + 2 + 3 = 6

$ add --help
USAGE: add [options] <values>...

Add numbers and print the result

ARGUMENTS:
  <values>...

OPTIONS:
  -v, --verbose         (default: false)
  -h, --help             Show help information
```

## Installation

Requires Zig `master` (minimum `0.16.0-dev.2261+d6b3dd25a`).

Add zap as a dependency in your `build.zig.zon`:

```
zig fetch --save git+https://github.com/ataias/zap
```

Then in your `build.zig`:

```zig
const zap_dep = b.dependency("zap", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zap", zap_dep.module("zap"));
```

## How it works

Struct fields map directly to CLI arguments:

| Field type | CLI form | Example |
|---|---|---|
| `bool` | Flag | `--verbose`, `-v` |
| `u8` (default 0) | Counted flag | `-vvv` sets to 3 |
| Integer/Float | Option | `--port 3000` |
| `enum` | Option | `--color red` |
| `[]const u8` | String option | `--name alice` |
| `Positional(T)` | Positional | `<file>` |
| `[]const T` | Multi positional | `<values>...` |
| `?T` | Optional argument | omitting is valid |

Fields with default values become optional. Fields without defaults are required.

### Naming conventions

- Struct field names use `snake_case`; zap converts them to `--kebab-case` on the CLI (`hex_output` becomes `--hex-output`)
- Short flags (`-v`, `-f`, etc.) are assigned automatically from the first character of each field name, with collisions resolved at compile time
- Struct names use `CamelCase`; subcommand names are derived as `kebab-case` (`HexOutput` becomes `hex-output`)

## Subcommands

Define subcommands by listing them in `meta.subcommands`:

```zig
const Add = struct {
    pub const meta: zap.CommandMeta = .{ .description = "Add numbers" };
    values: []const i64,
    pub fn run(self: @This(), init: std.process.Init) !void { ... }
};

const Multiply = struct {
    pub const meta: zap.CommandMeta = .{ .description = "Multiply numbers" };
    values: []const i64,
    pub fn run(self: @This(), init: std.process.Init) !void { ... }
};

const Math = struct {
    pub const meta: zap.CommandMeta = .{
        .description = "A math utility",
        .subcommands = &.{ Add, Multiply },
    };
};

pub fn main(init: std.process.Init) !void {
    return zap.run(Math, init);
}
```

```
$ math add 2 3
5

$ math multiply 2 3 4
24

$ math --help
USAGE: math <subcommand>

A math utility

SUBCOMMANDS:
  add                    Add numbers
  multiply               Multiply numbers

OPTIONS:
  -h, --help             Show help information
```

## Field descriptions

Provide per-field descriptions via `meta.field_descriptions`:

```zig
const Cp = struct {
    pub const meta = .{
        .description = "Copy files",
        .field_descriptions = .{
            .output = "Destination path",
            .force = "Overwrite without prompting",
        },
    };

    output: []const u8,
    force: bool = false,
};
```

```
USAGE: cp [options]

Copy files

OPTIONS:
  -o, --output          Destination path
  -f, --force           Overwrite without prompting (default: false)
  -h, --help             Show help information
```

## Shell completions

Zap generates shell completion scripts for fish, zsh, and bash. Every command
built with `zap.run` automatically supports `--generate-completion-script`:

```
$ myapp --generate-completion-script fish | source  # fish
$ myapp --generate-completion-script zsh  >_myapp && source _myapp  # zsh
$ eval "$(myapp --generate-completion-script bash)"  # bash
```

Fine-tune what the shell suggests by adding `field_completions` to your command
metadata:

```zig
pub const meta = .{
    .field_completions = .{
        .target = .{ .values = &.{ "prod", "staging", "dev" } },
        .config = .{ .file_path_with_extensions = &.{ "json", "yaml" } },
        .service = .{ .from_command = "echo web api worker" },
    },
};
```

Available completion hints:

| Hint | Completes with |
|---|---|
| `.file_path` | File paths |
| `.file_path_with_extensions` | Files matching given extensions |
| `.dir_path` | Directory paths |
| `.executable` | Executable commands |
| `.values` | A fixed set of strings |
| `.from_command` | Output of a shell command |

Enum fields automatically complete with their variant names.

## Hidden fields and subcommands

Fields and subcommands can be hidden from help output while still being
functional:

```zig
pub const meta: zap.CommandMeta = .{
    .hidden_fields = &.{"debug_trace"},
    .hidden_subcommands = &.{"debug-info"},
    .subcommands = &.{ Deploy, Status, DebugInfo },
};
```

Hidden items are omitted from `--help` and completion scripts but are still
accepted when used directly.

## Error handling

Zap produces clear error messages and suggests corrections for typos using
Levenshtein distance:

```
$ add --badopt
error: unknown option '--badopt'
Usage: add [options] <values>...

$ add --verbos
error: unknown option '--verbos', did you mean '--verbose'?

$ math ad
error: unknown subcommand 'ad', did you mean 'add'?
```

## Building and testing

```sh
# Run all tests (unit + integration)
zig build test

# Run with a specific optimization level
zig build test -Doptimize=ReleaseSafe

# Build the examples
zig build
```

## Cross-compilation

Zap is tested against the following targets in CI:

- `aarch64-linux`
- `x86_64-macos`, `aarch64-macos`
- `x86_64-windows`
- `x86_64-freebsd`, `aarch64-freebsd`

## License

MIT
