const std = @import("std");
pub const core = @import("core/root.zig");
pub const introspect = @import("core/introspect.zig");
pub const tokenizer = @import("tokenizer.zig");
pub const parser = @import("parser.zig");
pub const help = @import("help.zig");
pub const errors = @import("errors.zig");
pub const complete = @import("complete.zig");

pub const ArgInfo = introspect.ArgInfo;
pub const ArgKind = introspect.ArgKind;

pub const CommandMeta = core.CommandMeta;
pub const Positional = core.Positional;

pub fn parseFromSlice(comptime T: type, argv: []const []const u8, allocator: std.mem.Allocator, reporter: *std.Io.Writer) core.ParseError!T {
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
    const cmd_name = comptime commandName(T);

    if (@hasDecl(T, "meta") and T.meta.subcommands.len > 0) {
        return dispatchSubcommands(T, cmd_name, argv, init, &err_writer.interface);
    }

    const instance = parseOrExit(T, cmd_name, argv, init, &err_writer.interface);
    return instance.run(init);
}

fn dispatchSubcommands(
    comptime T: type,
    comptime cmd_name: []const u8,
    argv: []const []const u8,
    init: std.process.Init,
    reporter: *std.Io.Writer,
) !void {
    if (argv.len > 0) {
        const first = argv[0];

        if (std.mem.eql(u8, first, "--help") or std.mem.eql(u8, first, "-h") or std.mem.eql(u8, first, "help")) {
            printHelpAndExit(T, cmd_name, init.io);
        }

        const subcommand_names = comptime blk: {
            var names: [T.meta.subcommands.len][]const u8 = undefined;
            for (T.meta.subcommands, 0..) |Sub, i| {
                names[i] = core.subcommandName(Sub);
            }
            break :blk names;
        };

        inline for (subcommand_names, T.meta.subcommands) |name, Sub| {
            if (std.mem.eql(u8, first, name)) {
                return runSubcommand(Sub, comptime cmd_name ++ " " ++ name, argv[1..], init, reporter);
            }
        }

        if (errors.suggestClosest(first, &subcommand_names)) |suggestion| {
            errors.printError(reporter, "unknown subcommand '{s}', did you mean '{s}'?", .{ first, suggestion });
        } else {
            errors.printError(reporter, "unknown subcommand '{s}'", .{first});
        }
        errors.printUsageHint(reporter, cmd_name);
        reporter.flush() catch {};
        std.process.exit(1);
    }

    if (@hasDecl(T, "run")) {
        const instance = parseOrExit(T, cmd_name, argv, init, reporter);
        return instance.run(init);
    }

    printHelpAndExit(T, cmd_name, init.io);
}

fn runSubcommand(
    comptime Sub: type,
    comptime cmd_name: []const u8,
    argv: []const []const u8,
    init: std.process.Init,
    reporter: *std.Io.Writer,
) !void {
    comptime {
        const has_subcommands = @hasDecl(Sub, "meta") and @hasField(@TypeOf(Sub.meta), "subcommands") and Sub.meta.subcommands.len > 0;
        if (!has_subcommands and !@hasDecl(Sub, "run")) {
            @compileError("command type '" ++ @typeName(Sub) ++ "' must have a pub fn run() or subcommands");
        }
    }

    if (@hasDecl(Sub, "meta") and @hasField(@TypeOf(Sub.meta), "subcommands") and Sub.meta.subcommands.len > 0) {
        return dispatchSubcommands(Sub, cmd_name, argv, init, reporter);
    }

    const instance = parseFromSlice(Sub, argv, init.arena.allocator(), reporter) catch |err| switch (err) {
        error.HelpRequested => printHelpAndExit(Sub, cmd_name, init.io),
        else => {
            errors.printUsageHint(reporter, cmd_name);
            reporter.flush() catch {};
            std.process.exit(1);
        },
    };
    return instance.run(init);
}

fn parseOrExit(comptime T: type, comptime cmd_name: []const u8, argv: []const []const u8, init: std.process.Init, reporter: *std.Io.Writer) T {
    return parseFromSlice(T, argv, init.arena.allocator(), reporter) catch |err| switch (err) {
        error.HelpRequested => printHelpAndExit(T, cmd_name, init.io),
        else => {
            errors.printUsageHint(reporter, cmd_name);
            reporter.flush() catch {};
            std.process.exit(1);
        },
    };
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

fn printHelpAndExit(comptime T: type, comptime cmd_name: []const u8, io: std.Io) noreturn {
    var buf: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buf);
    help.generateHelp(T, cmd_name, &writer.interface) catch {};
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
        return core.camelToKebab(short);
    }
}

test {
    _ = core;
    _ = introspect;
    _ = tokenizer;
    _ = parser;
    _ = help;
    _ = errors;
    _ = complete;
}
