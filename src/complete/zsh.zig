const std = @import("std");
const introspect_mod = @import("../introspect.zig");
const help_mod = @import("../help.zig");
const ArgInfo = introspect_mod.ArgInfo;
const ArgKind = introspect_mod.ArgKind;
const complete_mod = @import("../complete.zig");
const CompletionHint = complete_mod.CompletionHint;
const getCompletionHint = complete_mod.getCompletionHint;
const getFieldDescription = complete_mod.getFieldDescription;
const isHiddenComptime = complete_mod.isHiddenComptime;

pub fn generate(
    writer: *std.Io.Writer,
    comptime Command: type,
    comptime cmd_name: []const u8,
) !void {
    try writer.print("#compdef {s}\n", .{cmd_name});
    try writer.print("_{s}() {{\n", .{cmd_name});

    const has_subcommands = @hasDecl(Command, "meta") and
        @hasField(@TypeOf(Command.meta), "subcommands") and
        Command.meta.subcommands.len > 0;

    if (has_subcommands) {
        try writeSubcommandBody(writer, Command);
    } else {
        try writer.writeAll("    ");
        try writeArguments(writer, Command, "        ");
    }

    try writer.writeAll("}\n");
    try writer.print("compdef _{s} {s}\n", .{ cmd_name, cmd_name });
}

fn writeSubcommandBody(
    writer: *std.Io.Writer,
    comptime Command: type,
) !void {
    const hidden_subcommands: []const []const u8 = if (@hasDecl(Command, "meta") and
        @hasField(@TypeOf(Command.meta), "hidden_subcommands"))
        Command.meta.hidden_subcommands
    else
        &.{};

    try writer.writeAll("    local -a commands=(\n");
    inline for (Command.meta.subcommands) |Sub| {
        const sub_name = comptime help_mod.subcommandName(Sub);
        if (comptime isHiddenComptime(hidden_subcommands, sub_name)) continue;
        const sub_desc = if (@hasDecl(Sub, "meta")) Sub.meta.description else "";
        try writer.print("        '{s}", .{sub_name});
        if (sub_desc.len > 0) {
            try writer.writeByte(':');
            try writeZshEscaped(writer, sub_desc);
        }
        try writer.writeAll("'\n");
    }
    try writer.writeAll("    )\n");

    try writer.writeAll("    _arguments \\\n");
    try writer.writeAll("        '(-h --help)'{-h,--help}'[Show help information]' \\\n");
    try writer.writeAll("        '(-): :->command' '(-)*:: :->arg'\n");
    try writer.writeAll("    case $state in\n");
    try writer.writeAll("        command) _describe 'command' commands ;;\n");
    try writer.writeAll("        arg) case $words[1] in\n");

    inline for (Command.meta.subcommands) |Sub| {
        const sub_name = comptime help_mod.subcommandName(Sub);
        if (comptime isHiddenComptime(hidden_subcommands, sub_name)) continue;
        try writer.print("            {s}) ", .{sub_name});
        try writeArguments(writer, Sub, "                ");
        try writer.writeAll("            ;;\n");
    }

    try writer.writeAll("        esac ;;\n");
    try writer.writeAll("    esac\n");
}

fn writeArguments(
    writer: *std.Io.Writer,
    comptime Command: type,
    comptime indent: []const u8,
) !void {
    const arg_infos = comptime introspect_mod.introspect(Command);
    const hidden_fields: []const []const u8 = comptime if (@hasDecl(Command, "meta") and
        @hasField(@TypeOf(Command.meta), "hidden_fields"))
        Command.meta.hidden_fields
    else
        &.{};

    try writer.writeAll("_arguments");

    try writeHelpSpec(writer, indent);

    inline for (0..arg_infos.len) |i| {
        const ai = arg_infos[i];
        if (comptime isHiddenComptime(hidden_fields, ai.field_name)) continue;

        if (ai.kind == .positional) {
            const hint = comptime getCompletionHint(Command, ai.field_name);
            const prefix: []const u8 = if (ai.is_multi) "'*" else "':";
            const label = ai.field_name;

            if (comptime hint != .none) {
                try writer.writeAll(" \\\n");
                try writer.writeAll(indent);
                try writer.print("{s}{s}", .{ prefix, label });
                try writePositionalCompletionAction(writer, hint);
                try writer.writeByte('\'');
            } else if (ai.enum_values) |vals| {
                try writer.writeAll(" \\\n");
                try writer.writeAll(indent);
                try writer.print("{s}{s}:(", .{ prefix, label });
                for (vals, 0..) |v, vi| {
                    if (vi > 0) try writer.writeByte(' ');
                    try writeZshEscaped(writer, v);
                }
                try writer.writeAll(")'");
            } else {
                try writer.writeAll(" \\\n");
                try writer.writeAll(indent);
                try writer.print("{s}{s}:'", .{ prefix, label });
            }
            continue;
        }

        try writer.writeAll(" \\\n");
        try writer.writeAll(indent);
        try writeOptionSpec(writer, Command, ai);
    }
    try writer.writeByte('\n');
}

fn writeHelpSpec(writer: *std.Io.Writer, comptime indent: []const u8) !void {
    try writer.writeAll(" \\\n");
    try writer.writeAll(indent);
    try writer.writeAll("'(-h --help)'{-h,--help}'[Show help information]'");
}

fn writeOptionSpec(
    writer: *std.Io.Writer,
    comptime Command: type,
    comptime ai: ArgInfo,
) !void {
    const desc = comptime getFieldDescription(Command, ai.field_name);

    switch (ai.kind) {
        .flag => {
            if (ai.short_name) |s| {
                try writer.print("'(-{c} --{s})'{{-{c},--{s}}}", .{ s, ai.long_name, s, ai.long_name });
                if (desc) |d| {
                    try writer.writeAll("'[");
                    try writeZshEscaped(writer, d);
                    try writer.writeAll("]'");
                }
            } else {
                try writer.print("'--{s}", .{ai.long_name});
                if (desc) |d| {
                    try writer.writeByte('[');
                    try writeZshEscaped(writer, d);
                    try writer.writeByte(']');
                }
                try writer.writeByte('\'');
            }
        },
        .counted_flag => {
            if (ai.short_name) |s| {
                try writer.print("'*'{{-{c},--{s}}}", .{ s, ai.long_name });
                if (desc) |d| {
                    try writer.writeAll("'[");
                    try writeZshEscaped(writer, d);
                    try writer.writeAll("]'");
                }
            } else {
                try writer.print("'*--{s}", .{ai.long_name});
                if (desc) |d| {
                    try writer.writeByte('[');
                    try writeZshEscaped(writer, d);
                    try writer.writeByte(']');
                }
                try writer.writeByte('\'');
            }
        },
        .option => {
            const hint = comptime getCompletionHint(Command, ai.field_name);
            if (ai.short_name) |s| {
                try writer.print("'(-{c} --{s})'{{-{c},--{s}}}'[", .{ s, ai.long_name, s, ai.long_name });
            } else {
                try writer.print("'--{s}[", .{ai.long_name});
            }
            if (desc) |d| {
                try writeZshEscaped(writer, d);
            }
            try writer.writeByte(']');
            try writeOptionValueAction(writer, hint, ai);
            try writer.writeByte('\'');
        },
        .positional => unreachable,
    }
}

fn writeOptionValueAction(
    writer: *std.Io.Writer,
    hint: CompletionHint,
    ai: ArgInfo,
) !void {
    switch (hint) {
        .none => {
            if (ai.enum_values) |vals| {
                try writer.print(":{s}:(", .{ai.field_name});
                for (vals, 0..) |v, i| {
                    if (i > 0) try writer.writeByte(' ');
                    try writeZshEscaped(writer, v);
                }
                try writer.writeByte(')');
            } else {
                try writer.print(":{s}:", .{ai.field_name});
            }
        },
        .file_path => try writer.writeAll(":file:_files"),
        .file_path_with_extensions => |exts| {
            try writer.writeAll(":file:_files -g \"");
            for (exts, 0..) |ext, i| {
                if (i > 0) try writer.writeByte(' ');
                try writer.writeAll("*.");
                try writeZshEscaped(writer, ext);
            }
            try writer.writeByte('"');
        },
        .dir_path => try writer.writeAll(":directory:_directories"),
        .executable => try writer.writeAll(":command:_command_names"),
        .values => |vals| {
            try writer.print(":{s}:(", .{ai.field_name});
            for (vals, 0..) |v, i| {
                if (i > 0) try writer.writeByte(' ');
                try writeZshEscaped(writer, v);
            }
            try writer.writeByte(')');
        },
        .from_command => |cmd| {
            try writer.print(":{s}:{{compadd -- $(", .{ai.field_name});
            try writeZshEscaped(writer, cmd);
            try writer.writeAll(")}");
        },
    }
}

fn writePositionalCompletionAction(writer: *std.Io.Writer, hint: CompletionHint) !void {
    switch (hint) {
        .none => {},
        .file_path => try writer.writeAll(":_files"),
        .file_path_with_extensions => |exts| {
            try writer.writeAll(":_files -g \"");
            for (exts, 0..) |ext, i| {
                if (i > 0) try writer.writeByte(' ');
                try writer.writeAll("*.");
                try writeZshEscaped(writer, ext);
            }
            try writer.writeByte('"');
        },
        .dir_path => try writer.writeAll(":_directories"),
        .executable => try writer.writeAll(":_command_names"),
        .values => |vals| {
            try writer.writeAll(":(");
            for (vals, 0..) |v, i| {
                if (i > 0) try writer.writeByte(' ');
                try writeZshEscaped(writer, v);
            }
            try writer.writeByte(')');
        },
        .from_command => |cmd| {
            try writer.writeAll(":{compadd -- $(");
            try writeZshEscaped(writer, cmd);
            try writer.writeAll(")}");
        },
    }
}

fn writeZshEscaped(writer: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            ':' => try writer.writeAll("\\:"),
            '[' => try writer.writeAll("\\["),
            ']' => try writer.writeAll("\\]"),
            else => try writer.writeByte(c),
        }
    }
}

// --- Tests ---

const testing = std.testing;
const CommandMeta = @import("../zap.zig").CommandMeta;
const Positional = @import("../zap.zig").Positional;

test "zsh: simple command with flags and options" {
    const Cmd = struct {
        pub const meta = .{
            .description = "A test command",
            .field_descriptions = .{
                .output = "Output path",
                .verbose = "Enable verbose output",
            },
        };

        verbose: bool = false,
        output: []const u8,
        port: u16 = 8080,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\#compdef tool
        \\_tool() {
        \\    _arguments \
        \\        '(-h --help)'{-h,--help}'[Show help information]' \
        \\        '(-v --verbose)'{-v,--verbose}'[Enable verbose output]' \
        \\        '(-o --output)'{-o,--output}'[Output path]:output:' \
        \\        '(-p --port)'{-p,--port}'[]:port:'
        \\}
        \\compdef _tool tool
        \\
    , writer.buffered());
}

test "zsh: command with subcommands" {
    const Add = struct {
        pub const meta: CommandMeta = .{ .description = "Add items" };
        verbose: bool = false,
        pub fn run(_: @This(), _: std.process.Init) !void {}
    };
    const Remove = struct {
        pub const meta: CommandMeta = .{ .description = "Remove items" };
        force: bool = false,
        pub fn run(_: @This(), _: std.process.Init) !void {}
    };
    const Cli = struct {
        pub const meta: CommandMeta = .{
            .description = "My CLI",
            .subcommands = &.{ Add, Remove },
        };
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cli, "mycli");

    try testing.expectEqualStrings(
        \\#compdef mycli
        \\_mycli() {
        \\    local -a commands=(
        \\        'add:Add items'
        \\        'remove:Remove items'
        \\    )
        \\    _arguments \
        \\        '(-h --help)'{-h,--help}'[Show help information]' \
        \\        '(-): :->command' '(-)*:: :->arg'
        \\    case $state in
        \\        command) _describe 'command' commands ;;
        \\        arg) case $words[1] in
        \\            add) _arguments \
        \\                '(-h --help)'{-h,--help}'[Show help information]' \
        \\                '(-v --verbose)'{-v,--verbose}
        \\            ;;
        \\            remove) _arguments \
        \\                '(-h --help)'{-h,--help}'[Show help information]' \
        \\                '(-f --force)'{-f,--force}
        \\            ;;
        \\        esac ;;
        \\    esac
        \\}
        \\compdef _mycli mycli
        \\
    , writer.buffered());
}

test "zsh: enum options auto-complete variant names" {
    const Format = enum { json, yaml, text };
    const Cmd = struct {
        format: Format = .json,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\#compdef tool
        \\_tool() {
        \\    _arguments \
        \\        '(-h --help)'{-h,--help}'[Show help information]' \
        \\        '(-f --format)'{-f,--format}'[]:format:(json yaml text)'
        \\}
        \\compdef _tool tool
        \\
    , writer.buffered());
}

test "zsh: completion hint file_path" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .input = .file_path,
            },
        };
        input: []const u8,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\#compdef tool
        \\_tool() {
        \\    _arguments \
        \\        '(-h --help)'{-h,--help}'[Show help information]' \
        \\        '(-i --input)'{-i,--input}'[]:file:_files'
        \\}
        \\compdef _tool tool
        \\
    , writer.buffered());
}

test "zsh: completion hint file_path_with_extensions" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .config = .{ .file_path_with_extensions = &.{ "json", "yaml" } },
            },
        };
        config: []const u8,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\#compdef tool
        \\_tool() {
        \\    _arguments \
        \\        '(-h --help)'{-h,--help}'[Show help information]' \
        \\        '(-c --config)'{-c,--config}'[]:file:_files -g "*.json *.yaml"'
        \\}
        \\compdef _tool tool
        \\
    , writer.buffered());
}

test "zsh: completion hint dir_path" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .output = .dir_path,
            },
        };
        output: []const u8,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\#compdef tool
        \\_tool() {
        \\    _arguments \
        \\        '(-h --help)'{-h,--help}'[Show help information]' \
        \\        '(-o --output)'{-o,--output}'[]:directory:_directories'
        \\}
        \\compdef _tool tool
        \\
    , writer.buffered());
}

test "zsh: completion hint values" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .color = .{ .values = &.{ "red", "green", "blue" } },
            },
        };
        color: []const u8,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\#compdef tool
        \\_tool() {
        \\    _arguments \
        \\        '(-h --help)'{-h,--help}'[Show help information]' \
        \\        '(-c --color)'{-c,--color}'[]:color:(red green blue)'
        \\}
        \\compdef _tool tool
        \\
    , writer.buffered());
}

test "zsh: completion hint from_command" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .name = .{ .from_command = "docker ps --format '{{.Names}}'" },
            },
        };
        name: []const u8,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\#compdef tool
        \\_tool() {
        \\    _arguments \
        \\        '(-h --help)'{-h,--help}'[Show help information]' \
        \\        '(-n --name)'{-n,--name}'[]:name:{compadd -- $(docker ps --format '{{.Names}}')}'
        \\}
        \\compdef _tool tool
        \\
    , writer.buffered());
}

test "zsh: completion hint executable" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .shell = .executable,
            },
        };
        shell: []const u8,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\#compdef tool
        \\_tool() {
        \\    _arguments \
        \\        '(-h --help)'{-h,--help}'[Show help information]' \
        \\        '(-s --shell)'{-s,--shell}'[]:command:_command_names'
        \\}
        \\compdef _tool tool
        \\
    , writer.buffered());
}

test "zsh: hidden fields excluded" {
    const Cmd = struct {
        pub const meta: CommandMeta = .{
            .description = "A tool",
            .hidden_fields = &.{"debug"},
        };
        verbose: bool = false,
        debug: bool = false,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "--verbose") != null);
    try testing.expect(std.mem.indexOf(u8, output, "--debug") == null);
}

test "zsh: hidden subcommands excluded" {
    const Visible = struct {
        pub const meta: CommandMeta = .{ .description = "Visible cmd" };
        pub fn run(_: @This(), _: std.process.Init) !void {}
    };
    const Hidden = struct {
        pub const meta: CommandMeta = .{ .description = "Hidden cmd" };
        pub fn run(_: @This(), _: std.process.Init) !void {}
    };
    const Cli = struct {
        pub const meta: CommandMeta = .{
            .description = "My CLI",
            .subcommands = &.{ Visible, Hidden },
            .hidden_subcommands = &.{"hidden"},
        };
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cli, "mycli");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "visible") != null);
    try testing.expect(std.mem.indexOf(u8, output, "hidden") == null);
}

test "zsh: counted flags can repeat" {
    const Cmd = struct {
        verbosity: u8 = 0,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\#compdef tool
        \\_tool() {
        \\    _arguments \
        \\        '(-h --help)'{-h,--help}'[Show help information]' \
        \\        '*'{-v,--verbosity}
        \\}
        \\compdef _tool tool
        \\
    , writer.buffered());
}

test "zsh: special character escaping" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try writeZshEscaped(&writer, "a:b[c]d\\e");
    try testing.expectEqualStrings("a\\:b\\[c\\]d\\\\e", writer.buffered());
}

test "zsh: #compdef header present" {
    const Cmd = struct {
        values: []const i64,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    const output = writer.buffered();
    try testing.expect(std.mem.startsWith(u8, output, "#compdef tool\n"));
}

test "zsh: positional with completion hint" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .path = .dir_path,
            },
        };
        path: Positional([]const u8),
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\#compdef tool
        \\_tool() {
        \\    _arguments \
        \\        '(-h --help)'{-h,--help}'[Show help information]' \
        \\        ':path:_directories'
        \\}
        \\compdef _tool tool
        \\
    , writer.buffered());
}

test "zsh: positional with enum type" {
    const Color = enum { red, green, blue };
    const Cmd = struct {
        color: Positional(Color),
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\#compdef tool
        \\_tool() {
        \\    _arguments \
        \\        '(-h --help)'{-h,--help}'[Show help information]' \
        \\        ':color:(red green blue)'
        \\}
        \\compdef _tool tool
        \\
    , writer.buffered());
}
