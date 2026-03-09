const std = @import("std");
pub const introspect = @import("introspect.zig");
pub const tokenizer = @import("tokenizer.zig");
pub const parser = @import("parser.zig");
pub const help = @import("help.zig");
pub const errors = @import("errors.zig");
pub const complete = @import("complete.zig");

pub const ArgInfo = introspect.ArgInfo;
pub const ArgKind = introspect.ArgKind;

pub const CommandMeta = struct {
    description: []const u8 = "",
    subcommands: []const type = &.{},
    hidden_fields: []const []const u8 = &.{},
    hidden_subcommands: []const []const u8 = &.{},
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

    if (argv.len >= 1 and std.mem.eql(u8, argv[0], "--generate-completion-script")) {
        generateCompletionAndExit(T, argv, init);
    }

    var err_buf: [4096]u8 = undefined;
    var err_writer = std.Io.File.stderr().writer(init.io, &err_buf);

    if (@hasDecl(T, "meta") and T.meta.subcommands.len > 0) {
        if (argv.len > 0) {
            const first = argv[0];

            if (std.mem.eql(u8, first, "--help") or std.mem.eql(u8, first, "-h") or std.mem.eql(u8, first, "help")) {
                printHelpAndExit(T, init.io);
            }

            const subcommand_names = comptime blk: {
                var names: [T.meta.subcommands.len][]const u8 = undefined;
                for (T.meta.subcommands, 0..) |Sub, i| {
                    names[i] = help.subcommandName(Sub);
                }
                break :blk names;
            };

            inline for (subcommand_names, T.meta.subcommands) |name, Sub| {
                if (std.mem.eql(u8, first, name)) {
                    return runSubcommand(Sub, argv[1..], init, &err_writer.interface);
                }
            }

            if (errors.suggestClosest(first, &subcommand_names)) |suggestion| {
                errors.printError(&err_writer.interface, "unknown subcommand '{s}', did you mean '{s}'?", .{ first, suggestion });
            } else {
                errors.printError(&err_writer.interface, "unknown subcommand '{s}'", .{first});
            }
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

fn generateCompletionAndExit(comptime T: type, argv: []const []const u8, init: std.process.Init) noreturn {
    const shell_name = if (argv.len >= 2) argv[1] else {
        var err_buf: [256]u8 = undefined;
        var ew = std.Io.File.stderr().writer(init.io, &err_buf);
        ew.interface.writeAll("error: --generate-completion-script requires a shell name (fish, zsh, bash)\n") catch {};
        ew.interface.flush() catch {};
        std.process.exit(1);
    };
    const shell = std.meta.stringToEnum(complete.Shell, shell_name) orelse {
        var err_buf: [256]u8 = undefined;
        var ew = std.Io.File.stderr().writer(init.io, &err_buf);
        ew.interface.print("error: unknown shell '{s}'. Expected: fish, zsh, bash\n", .{shell_name}) catch {};
        ew.interface.flush() catch {};
        std.process.exit(1);
    };
    var buf: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buf);
    complete.generate(&writer.interface, T, comptime commandName(T), shell) catch {
        std.process.exit(1);
    };
    writer.interface.flush() catch {};
    std.process.exit(0);
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
    _ = complete;
}
