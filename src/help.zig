const std = @import("std");
const introspect_mod = @import("introspect.zig");
const ArgInfo = introspect_mod.ArgInfo;
const ArgKind = introspect_mod.ArgKind;

pub fn generateHelp(
    comptime T: type,
    command_name: []const u8,
    writer: *std.Io.Writer,
) !void {
    const arg_infos = comptime introspect_mod.introspect(T);
    const description = if (@hasDecl(T, "meta")) T.meta.description else "";
    const field_descriptions = if (@hasDecl(T, "meta") and @hasField(@TypeOf(T.meta), "field_descriptions"))
        T.meta.field_descriptions
    else
        null;
    const hidden_fields: []const []const u8 = if (@hasDecl(T, "meta") and @hasField(@TypeOf(T.meta), "hidden_fields"))
        T.meta.hidden_fields
    else
        &.{};
    const hidden_subcommands: []const []const u8 = if (@hasDecl(T, "meta") and @hasField(@TypeOf(T.meta), "hidden_subcommands"))
        T.meta.hidden_subcommands
    else
        &.{};

    const has_subcommands = @hasDecl(T, "meta") and @hasField(@TypeOf(T.meta), "subcommands") and T.meta.subcommands.len > 0;

    try writer.print("USAGE: {s}", .{command_name});

    if (has_subcommands) {
        try writer.writeAll(" <subcommand>");
    }

    var has_options = false;
    for (arg_infos) |ai| {
        if (ai.kind != .positional and !isHidden(hidden_fields, ai.field_name)) has_options = true;
    }
    if (has_options) try writer.writeAll(" [options]");

    for (arg_infos) |ai| {
        if (ai.kind == .positional and !isHidden(hidden_fields, ai.field_name)) {
            if (ai.required) {
                if (ai.is_multi) {
                    try writer.print(" <{s}>...", .{ai.long_name});
                } else {
                    try writer.print(" <{s}>", .{ai.long_name});
                }
            } else {
                if (ai.is_multi) {
                    try writer.print(" [<{s}>...]", .{ai.long_name});
                } else {
                    try writer.print(" [<{s}>]", .{ai.long_name});
                }
            }
        }
    }
    try writer.writeAll("\n");

    if (description.len > 0) {
        try writer.print("\n{s}\n", .{description});
    }

    if (has_subcommands) {
        try writer.writeAll("\nSUBCOMMANDS:\n");
        inline for (T.meta.subcommands) |Sub| {
            const sub_name = comptime subcommandName(Sub);
            if (comptime isHiddenComptime(hidden_subcommands, sub_name)) continue;
            const sub_desc = if (@hasDecl(Sub, "meta")) Sub.meta.description else "";
            try writer.print("  {s: <22} {s}\n", .{ sub_name, sub_desc });
        }
    }

    var has_positionals = false;
    for (arg_infos) |ai| {
        if (ai.kind == .positional and !isHidden(hidden_fields, ai.field_name)) {
            has_positionals = true;
            break;
        }
    }

    if (has_positionals) {
        try writer.writeAll("\nARGUMENTS:\n");
        for (arg_infos) |ai| {
            if (ai.kind != .positional) continue;
            if (isHidden(hidden_fields, ai.field_name)) continue;
            const desc = getFieldDescription(field_descriptions, ai.field_name);
            if (ai.is_multi) {
                try writer.print("  <{s}>...", .{ai.long_name});
            } else {
                try writer.print("  <{s}>", .{ai.long_name});
            }
            if (desc) |d| {
                const used = ai.long_name.len + if (ai.is_multi) @as(usize, 5) else @as(usize, 2);
                const col = 24;
                const pad = if (used < col) col - used else 1;
                try writer.splatByteAll(' ', pad);
                try writer.print("{s}", .{d});
            }
            try writer.writeAll("\n");
        }
    }

    try writer.writeAll("\nOPTIONS:\n");
    for (arg_infos) |ai| {
        if (ai.kind == .positional) continue;
        if (isHidden(hidden_fields, ai.field_name)) continue;
        try writeOptionLine(writer, ai, getFieldDescription(field_descriptions, ai.field_name));
    }
    try writer.writeAll("  -h, --help             Show help information\n");
}

fn isHidden(hidden: []const []const u8, name: []const u8) bool {
    for (hidden) |h| {
        if (std.mem.eql(u8, h, name)) return true;
    }
    return false;
}

fn isHiddenComptime(comptime hidden: []const []const u8, comptime name: []const u8) bool {
    for (hidden) |h| {
        if (std.mem.eql(u8, h, name)) return true;
    }
    return false;
}

fn writeOptionLine(writer: *std.Io.Writer, ai: ArgInfo, desc: ?[]const u8) !void {
    if (ai.short_name) |s| {
        try writer.print("  -{c}, --{s}", .{ s, ai.long_name });
    } else {
        try writer.print("      --{s}", .{ai.long_name});
    }

    const name_len = ai.long_name.len;
    const prefix_len: usize = name_len + 8;
    const col = 24;
    const pad = if (prefix_len < col) col - prefix_len else 1;
    try writer.splatByteAll(' ', pad);

    if (desc) |d| {
        try writer.writeAll(d);
        if (ai.default_text != null) try writer.writeAll(" ");
    }
    if (ai.default_text) |dt| {
        try writer.print("(default: {s})", .{dt});
    }
    try writer.writeAll("\n");
}

fn getFieldDescription(field_descriptions: anytype, field_name: []const u8) ?[]const u8 {
    if (@TypeOf(field_descriptions) == @TypeOf(null)) return null;
    const descs = field_descriptions;
    inline for (@typeInfo(@TypeOf(descs)).@"struct".fields) |f| {
        if (std.mem.eql(u8, f.name, field_name)) {
            return @field(descs, f.name);
        }
    }
    return null;
}

pub fn subcommandName(comptime T: type) []const u8 {
    comptime {
        const full = @typeName(T);
        const short = if (std.mem.lastIndexOfScalar(u8, full, '.')) |dot|
            full[dot + 1 ..]
        else
            full;
        return camelToKebab(short);
    }
}

pub fn camelToKebab(comptime name: []const u8) []const u8 {
    comptime {
        var len: usize = 0;
        for (name, 0..) |c, i| {
            if (c >= 'A' and c <= 'Z' and i > 0) len += 1;
            len += 1;
        }
        var result: [len]u8 = undefined;
        var j: usize = 0;
        for (name, 0..) |c, i| {
            if (c >= 'A' and c <= 'Z' and i > 0) {
                result[j] = '-';
                j += 1;
            }
            result[j] = if (c >= 'A' and c <= 'Z') c + 32 else c;
            j += 1;
        }
        const final = result;
        return &final;
    }
}

// --- Tests ---

const testing = std.testing;
const CommandMeta = @import("zap.zig").CommandMeta;

test "help for simple command" {
    const Cmd = struct {
        pub const meta: CommandMeta = .{
            .description = "Add numbers and print the result",
        };

        verbose: bool = false,
        hex_output: bool = false,
        values: []const i64,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generateHelp(Cmd, "add", &writer);

    try testing.expectEqualStrings(
        \\USAGE: add [options] <values>...
        \\
        \\Add numbers and print the result
        \\
        \\ARGUMENTS:
        \\  <values>...
        \\
        \\OPTIONS:
        \\  -v, --verbose         (default: false)
        \\      --hex-output      (default: false)
        \\  -h, --help             Show help information
        \\
    , writer.buffered());
}

test "help with field descriptions" {
    const Cmd = struct {
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

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generateHelp(Cmd, "cp", &writer);

    try testing.expectEqualStrings(
        \\USAGE: cp [options]
        \\
        \\Copy files
        \\
        \\OPTIONS:
        \\  -o, --output          Destination path
        \\  -f, --force           Overwrite without prompting (default: false)
        \\  -h, --help             Show help information
        \\
    , writer.buffered());
}

test "help with subcommands" {
    const Add = struct {
        pub const meta: CommandMeta = .{ .description = "Add numbers" };
        values: []const i64,
        pub fn run(_: @This()) !void {}
    };
    const Multiply = struct {
        pub const meta: CommandMeta = .{ .description = "Multiply numbers" };
        values: []const i64,
        pub fn run(_: @This()) !void {}
    };
    const Math = struct {
        pub const meta: CommandMeta = .{
            .description = "A math utility",
            .subcommands = &.{ Add, Multiply },
        };
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generateHelp(Math, "math", &writer);

    try testing.expectEqualStrings(
        \\USAGE: math <subcommand>
        \\
        \\A math utility
        \\
        \\SUBCOMMANDS:
        \\  add                    Add numbers
        \\  multiply               Multiply numbers
        \\
        \\OPTIONS:
        \\  -h, --help             Show help information
        \\
    , writer.buffered());

    // Subcommand help: `math add --help`
    writer = std.Io.Writer.fixed(&buf);
    try generateHelp(Add, "math add", &writer);

    try testing.expectEqualStrings(
        \\USAGE: math add <values>...
        \\
        \\Add numbers
        \\
        \\ARGUMENTS:
        \\  <values>...
        \\
        \\OPTIONS:
        \\  -h, --help             Show help information
        \\
    , writer.buffered());
}

test "help with optional positional" {
    const Cmd = struct {
        pub const meta: CommandMeta = .{ .description = "Greet someone" };
        name: ?@import("zap.zig").Positional([]const u8) = null,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generateHelp(Cmd, "greet", &writer);

    try testing.expectEqualStrings(
        \\USAGE: greet [<name>]
        \\
        \\Greet someone
        \\
        \\ARGUMENTS:
        \\  <name>
        \\
        \\OPTIONS:
        \\  -h, --help             Show help information
        \\
    , writer.buffered());
}

test "help with hidden field" {
    const Cmd = struct {
        pub const meta: CommandMeta = .{
            .description = "Start the server",
            .hidden_fields = &.{"debug_dump"},
        };

        port: u16 = 8080,
        verbose: bool = false,
        debug_dump: bool = false,
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generateHelp(Cmd, "server", &writer);

    try testing.expectEqualStrings(
        \\USAGE: server [options]
        \\
        \\Start the server
        \\
        \\OPTIONS:
        \\  -p, --port            (default: 8080)
        \\  -v, --verbose         (default: false)
        \\  -h, --help             Show help information
        \\
    , writer.buffered());
}

test "help with hidden subcommand" {
    const Migrate = struct {
        pub const meta: CommandMeta = .{ .description = "Run migrations" };
        pub fn run(_: @This(), _: std.process.Init) !void {}
    };
    const DebugSchema = struct {
        pub const meta: CommandMeta = .{ .description = "Dump raw schema" };
        pub fn run(_: @This(), _: std.process.Init) !void {}
    };
    const Db = struct {
        pub const meta: CommandMeta = .{
            .description = "Database management",
            .subcommands = &.{ Migrate, DebugSchema },
            .hidden_subcommands = &.{"debug-schema"},
        };
    };

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generateHelp(Db, "db", &writer);

    try testing.expectEqualStrings(
        \\USAGE: db <subcommand>
        \\
        \\Database management
        \\
        \\SUBCOMMANDS:
        \\  migrate                Run migrations
        \\
        \\OPTIONS:
        \\  -h, --help             Show help information
        \\
    , writer.buffered());
}

test "camelToKebab" {
    try testing.expectEqualStrings("add", comptime camelToKebab("Add"));
    try testing.expectEqualStrings("multiply", comptime camelToKebab("Multiply"));
    try testing.expectEqualStrings("hex-output", comptime camelToKebab("HexOutput"));
    try testing.expectEqualStrings("standard-deviation", comptime camelToKebab("StandardDeviation"));
}
