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
    const has_subcommands = @hasDecl(Command, "meta") and
        @hasField(@TypeOf(Command.meta), "subcommands") and
        Command.meta.subcommands.len > 0;

    if (has_subcommands) {
        try writeCommand(writer, Command, cmd_name, "__fish_use_subcommand");

        const hidden_subcommands: []const []const u8 = if (@hasDecl(Command, "meta") and
            @hasField(@TypeOf(Command.meta), "hidden_subcommands"))
            Command.meta.hidden_subcommands
        else
            &.{};

        inline for (Command.meta.subcommands) |Sub| {
            const sub_name = comptime help_mod.subcommandName(Sub);
            if (comptime isHiddenComptime(hidden_subcommands, sub_name)) continue;
            const sub_desc = if (@hasDecl(Sub, "meta")) Sub.meta.description else "";
            try writer.print("complete -c {s} -n '__fish_use_subcommand' -f -a {s}", .{ cmd_name, sub_name });
            if (sub_desc.len > 0) {
                try writer.writeAll(" -d '");
                try writeFishEscaped(writer, sub_desc);
                try writer.writeByte('\'');
            }
            try writer.writeByte('\n');
        }

        inline for (Command.meta.subcommands) |Sub| {
            const sub_name = comptime help_mod.subcommandName(Sub);
            if (comptime isHiddenComptime(hidden_subcommands, sub_name)) continue;
            try writeCommand(writer, Sub, cmd_name, "__fish_seen_subcommand_from " ++ sub_name);
        }
    } else {
        try writeCommand(writer, Command, cmd_name, null);
    }
}

fn writeCommand(
    writer: *std.Io.Writer,
    comptime Command: type,
    comptime cmd_name: []const u8,
    comptime condition: ?[]const u8,
) !void {
    const arg_infos = comptime introspect_mod.introspect(Command);
    const hidden_fields: []const []const u8 = comptime if (@hasDecl(Command, "meta") and
        @hasField(@TypeOf(Command.meta), "hidden_fields"))
        Command.meta.hidden_fields
    else
        &.{};

    try writer.print("complete -c {s}", .{cmd_name});
    if (condition) |cond| {
        try writer.print(" -n '{s}'", .{cond});
    }
    try writer.writeAll(" -s h -l help -f -d 'Show help information'\n");

    inline for (0..arg_infos.len) |i| {
        const ai = arg_infos[i];
        if (comptime isHiddenComptime(hidden_fields, ai.field_name)) continue;

        if (ai.kind == .positional) {
            const hint = comptime getCompletionHint(Command, ai.field_name);
            if (comptime hint != .none or ai.enum_values != null) {
                try writer.print("complete -c {s}", .{cmd_name});
                if (condition) |cond| {
                    try writer.print(" -n '{s}'", .{cond});
                }
                if (comptime hint != .file_path) {
                    try writer.writeAll(" -f");
                }
                if (comptime hint != .none) {
                    try writeCompletionHint(writer, hint);
                } else if (ai.enum_values) |vals| {
                    try writeEnumValues(writer, vals);
                }
                try writer.writeByte('\n');
            }
            continue;
        }

        try writer.print("complete -c {s}", .{cmd_name});
        // Hide bool flags after first use; counted flags stay repeatable.
        // Options (.option) are excluded: the condition would also block
        // their value completions (-a), breaking e.g. `--format <TAB>`.
        if (ai.kind == .flag) {
            if (condition) |cond| {
                try writer.print(" -n '{s}; and not __fish_contains_opt", .{cond});
            } else {
                try writer.writeAll(" -n 'not __fish_contains_opt");
            }
            if (ai.short_name) |s| {
                try writer.print(" {c}", .{s});
            }
            try writer.print(" {s}'", .{ai.long_name});
        } else {
            if (condition) |cond| {
                try writer.print(" -n '{s}'", .{cond});
            }
        }

        if (ai.short_name) |s| {
            try writer.print(" -s {c}", .{s});
        }
        try writer.print(" -l {s}", .{ai.long_name});

        switch (ai.kind) {
            .flag => try writer.writeAll(" -f"),
            .counted_flag => try writer.writeAll(" -f"),
            .option => {
                try writer.writeAll(" -r");
                const hint = comptime getCompletionHint(Command, ai.field_name);
                if (comptime hint != .file_path) {
                    try writer.writeAll(" -f");
                }
                if (comptime hint != .none) {
                    try writeCompletionHint(writer, hint);
                } else if (ai.enum_values) |vals| {
                    try writeEnumValues(writer, vals);
                }
            },
            .positional => unreachable,
        }

        const desc = comptime getFieldDescription(Command, ai.field_name);
        if (desc) |d| {
            try writer.writeAll(" -d '");
            try writeFishEscaped(writer, d);
            try writer.writeByte('\'');
        }

        try writer.writeByte('\n');
    }
}

fn writeEnumValues(writer: *std.Io.Writer, vals: []const []const u8) !void {
    try writer.writeAll(" -a '");
    for (vals, 0..) |v, i| {
        if (i > 0) try writer.writeByte(' ');
        try writeFishEscaped(writer, v);
    }
    try writer.writeByte('\'');
}

fn writeCompletionHint(writer: *std.Io.Writer, hint: CompletionHint) !void {
    switch (hint) {
        .none => {},
        .file_path => try writer.writeAll(" -F"),
        .file_path_with_extensions => |exts| {
            try writer.writeAll(" -a '(set -l tok (commandline -ct); for f in");
            for (exts) |ext| {
                try writer.writeAll(" $tok*.");
                try writeFishEscaped(writer, ext);
            }
            try writer.writeAll(" $tok*/; test -e \"$f\"; and echo $f; end)'");
        },
        .dir_path => try writer.writeAll(" -a '(__fish_complete_directories)'"),
        .executable => try writer.writeAll(" -a '(__fish_complete_command)'"),
        .values => |vals| try writeEnumValues(writer, vals),
        .from_command => |cmd| {
            try writer.writeAll(" -a '(");
            try writeFishEscaped(writer, cmd);
            try writer.writeAll(")'");
        },
    }
}

fn writeFishEscaped(writer: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        if (c == '\'') {
            try writer.writeAll("'\\''");
        } else {
            try writer.writeByte(c);
        }
    }
}

// --- Tests ---

const testing = std.testing;
const CommandMeta = @import("../zap.zig").CommandMeta;
const Positional = @import("../zap.zig").Positional;

test "fish: simple command with flags and options" {
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
    try generate(&writer, Cmd, "test-cmd");

    try testing.expectEqualStrings(
        \\complete -c test-cmd -s h -l help -f -d 'Show help information'
        \\complete -c test-cmd -n 'not __fish_contains_opt v verbose' -s v -l verbose -f -d 'Enable verbose output'
        \\complete -c test-cmd -s o -l output -r -f -d 'Output path'
        \\complete -c test-cmd -s p -l port -r -f
        \\
    , writer.buffered());
}

test "fish: command with subcommands" {
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
        \\complete -c mycli -n '__fish_use_subcommand' -s h -l help -f -d 'Show help information'
        \\complete -c mycli -n '__fish_use_subcommand' -f -a add -d 'Add items'
        \\complete -c mycli -n '__fish_use_subcommand' -f -a remove -d 'Remove items'
        \\complete -c mycli -n '__fish_seen_subcommand_from add' -s h -l help -f -d 'Show help information'
        \\complete -c mycli -n '__fish_seen_subcommand_from add; and not __fish_contains_opt v verbose' -s v -l verbose -f
        \\complete -c mycli -n '__fish_seen_subcommand_from remove' -s h -l help -f -d 'Show help information'
        \\complete -c mycli -n '__fish_seen_subcommand_from remove; and not __fish_contains_opt f force' -s f -l force -f
        \\
    , writer.buffered());
}

test "fish: enum options auto-complete variant names" {
    const Format = enum { json, yaml, text };
    const Cmd = struct {
        format: Format = .json,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -s f -l format -r -f -a 'json yaml text'
        \\
    , writer.buffered());
}

test "fish: completion hint file_path" {
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
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -s i -l input -r -F
        \\
    , writer.buffered());
}

test "fish: completion hint file_path_with_extensions" {
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
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -s c -l config -r -f -a '(set -l tok (commandline -ct); for f in $tok*.json $tok*.yaml $tok*/; test -e "$f"; and echo $f; end)'
        \\
    , writer.buffered());
}

test "fish: completion hint dir_path" {
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
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -s o -l output -r -f -a '(__fish_complete_directories)'
        \\
    , writer.buffered());
}

test "fish: completion hint values" {
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
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -s c -l color -r -f -a 'red green blue'
        \\
    , writer.buffered());
}

test "fish: completion hint from_command" {
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
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -s n -l name -r -f -a '(docker ps --format '\''{{.Names}}'\'')'
        \\
    , writer.buffered());
}

test "fish: completion hint executable" {
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
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -s s -l shell -r -f -a '(__fish_complete_command)'
        \\
    , writer.buffered());
}

test "fish: single-quote escaping in values" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .name = .{ .values = &.{ "foo", "it's", "bar" } },
            },
        };
        name: []const u8,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -s n -l name -r -f -a 'foo it'\''s bar'
        \\
    , writer.buffered());
}

test "fish: positional with completion hint" {
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
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -f -a '(__fish_complete_directories)'
        \\
    , writer.buffered());
}

test "fish: positional with enum type" {
    const Color = enum { red, green, blue };
    const Cmd = struct {
        color: Positional(Color),
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -f -a 'red green blue'
        \\
    , writer.buffered());
}

test "fish: --help always present" {
    const Cmd = struct {
        values: []const i64,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "-s h -l help -f -d 'Show help information'") != null);
}

test "fish: counted flags can repeat" {
    const Cmd = struct {
        verbosity: u8 = 0,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -s v -l verbosity -f
        \\
    , writer.buffered());
}

test "fish: hidden fields excluded" {
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
    try testing.expect(std.mem.indexOf(u8, output, "-l verbose") != null);
    try testing.expect(std.mem.indexOf(u8, output, "-l debug") == null);
}

test "fish: hidden subcommands excluded" {
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

test "fish: command with only positionals still generates --help" {
    const Cmd = struct {
        values: []const i64,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "adder");

    try testing.expectEqualStrings(
        \\complete -c adder -s h -l help -f -d 'Show help information'
        \\
    , writer.buffered());
}

test "fish: writeFishEscaped handles single quotes" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try writeFishEscaped(&writer, "it's");
    try testing.expectEqualStrings("it'\\''s", writer.buffered());
}

test "fish: description with single quote is escaped" {
    const Cmd = struct {
        pub const meta = .{
            .field_descriptions = .{
                .name = "it's a name",
            },
        };
        name: []const u8,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -s n -l name -r -f -d 'it'\''s a name'
        \\
    , writer.buffered());
}

test "fish: completion hint overrides enum auto-completion" {
    const Format = enum { json, yaml };
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .format = .{ .values = &.{ "custom1", "custom2" } },
            },
        };
        format: Format = .json,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\complete -c tool -s h -l help -f -d 'Show help information'
        \\complete -c tool -s f -l format -r -f -a 'custom1 custom2'
        \\
    , writer.buffered());
}
