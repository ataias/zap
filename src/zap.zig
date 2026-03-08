const std = @import("std");
pub const introspect = @import("introspect.zig");
pub const tokenizer = @import("tokenizer.zig");
pub const parser = @import("parser.zig");
pub const help = @import("help.zig");
pub const errors = @import("errors.zig");

pub const ArgInfo = introspect.ArgInfo;
pub const ArgKind = introspect.ArgKind;

pub const CommandMeta = struct {
    description: []const u8 = "",
    subcommands: []const type = &.{},
};

pub fn Positional(comptime T: type) type {
    return struct {
        pub const __zap_positional_marker = {};
        pub const Inner = T;
        value: T,
    };
}

pub fn parseFromSlice(comptime T: type, argv: []const []const u8, allocator: std.mem.Allocator, reporter: *std.Io.Writer) errors.ParseError!T {
    return parser.parseArgs(T, argv, allocator, reporter);
}

pub fn run(comptime T: type, init: std.process.Init) !void {
    comptime {
        const has_subcommands = @hasDecl(T, "meta") and @hasField(@TypeOf(T.meta), "subcommands") and T.meta.subcommands.len > 0;
        if (!has_subcommands and !@hasDecl(T, "run")) {
            @compileError("command type '" ++ @typeName(T) ++ "' must have a pub fn run() or subcommands");
        }
    }
    const allocator = init.arena.allocator();
    const argv_slice = try init.minimal.args.toSlice(allocator);
    const argv: []const []const u8 = if (argv_slice.len > 0) argv_slice[1..] else argv_slice;

    var err_buf: [4096]u8 = undefined;
    var err_writer = std.Io.File.stderr().writer(init.io, &err_buf);

    if (@hasDecl(T, "meta") and T.meta.subcommands.len > 0) {
        if (argv.len > 0) {
            const first = argv[0];

            if (std.mem.eql(u8, first, "--help") or std.mem.eql(u8, first, "-h") or std.mem.eql(u8, first, "help")) {
                printHelpAndExit(T, init.io);
            }

            inline for (T.meta.subcommands) |Sub| {
                if (std.mem.eql(u8, first, comptime help.subcommandName(Sub))) {
                    return runSubcommand(Sub, argv[1..], init, &err_writer.interface);
                }
            }

            errors.printError(&err_writer.interface, "unknown subcommand '{s}'", .{first});
            errors.printUsageHint(&err_writer.interface, comptime commandName(T));
            err_writer.interface.flush() catch {};
            std.process.exit(1);
        }

        if (@hasDecl(T, "run")) {
            const instance = parseOrExit(T, argv, init, &err_writer.interface);
            return instance.run(init);
        }

        printHelpAndExit(T, init.io);
    }

    const instance = parseOrExit(T, argv, init, &err_writer.interface);
    return instance.run(init);
}

fn parseOrExit(comptime T: type, argv: []const []const u8, init: std.process.Init, reporter: *std.Io.Writer) T {
    return parseFromSlice(T, argv, init.arena.allocator(), reporter) catch |err| switch (err) {
        error.HelpRequested => printHelpAndExit(T, init.io),
        else => {
            errors.printUsageHint(reporter, comptime commandName(T));
            reporter.flush() catch {};
            std.process.exit(1);
        },
    };
}

fn runSubcommand(comptime Sub: type, argv: []const []const u8, init: std.process.Init, reporter: *std.Io.Writer) !void {
    const instance = parseFromSlice(Sub, argv, init.arena.allocator(), reporter) catch |err| switch (err) {
        error.HelpRequested => printHelpAndExit(Sub, init.io),
        else => {
            errors.printUsageHint(reporter, comptime help.subcommandName(Sub));
            reporter.flush() catch {};
            std.process.exit(1);
        },
    };
    return instance.run(init);
}

fn printHelpAndExit(comptime T: type, io: std.Io) noreturn {
    var buf: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buf);
    help.generateHelp(T, comptime commandName(T), &writer.interface) catch {};
    writer.interface.flush() catch {};
    std.process.exit(0);
}

fn commandName(comptime T: type) []const u8 {
    comptime {
        const full = @typeName(T);
        const short = if (std.mem.lastIndexOfScalar(u8, full, '.')) |dot|
            full[dot + 1 ..]
        else
            full;
        return help.camelToKebab(short);
    }
}

test {
    _ = introspect;
    _ = tokenizer;
    _ = parser;
    _ = help;
    _ = errors;
}
