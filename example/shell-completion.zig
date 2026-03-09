const std = @import("std");
const zap = @import("zap");

const Format = enum { json, yaml, text };

const Deploy = struct {
    pub const meta = .{
        .description = "Deploy the application",
        .hidden_fields = &.{"debug_trace"},
        .field_descriptions = .{
            .target = "Deployment target",
            .format = "Output format",
            .port = "Port to listen on",
            .verbose = "Enable verbose output",
            .count = "Repeat count",
        },
        .field_completions = .{
            .target = .{ .values = &.{ "prod", "staging", "dev" } },
        },
    };

    target: []const u8,
    format: Format = .json,
    port: u16 = 8080,
    verbose: bool = false,
    count: u8 = 0,
    debug_trace: bool = false,

    pub fn run(self: @This(), init: std.process.Init) !void {
        var buf: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        try writer.interface.print("deploying to {s} on port {d} (format: {s})\n", .{
            self.target,
            self.port,
            @tagName(self.format),
        });
        if (self.debug_trace) {
            try writer.interface.writeAll("debug trace enabled\n");
        }
        try writer.interface.flush();
    }
};

const Status = struct {
    pub const meta: zap.CommandMeta = .{
        .description = "Show deployment status",
    };

    verbose: bool = false,

    pub fn run(self: @This(), init: std.process.Init) !void {
        var buf: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        if (self.verbose) {
            try writer.interface.writeAll("status: running (verbose)\n");
        } else {
            try writer.interface.writeAll("status: running\n");
        }
        try writer.interface.flush();
    }
};

const DebugInfo = struct {
    pub const meta: zap.CommandMeta = .{
        .description = "Show internal debug info",
    };

    pub fn run(_: @This(), init: std.process.Init) !void {
        var buf: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        try writer.interface.writeAll("debug info output\n");
        try writer.interface.flush();
    }
};

const ShellCompletion = struct {
    pub const meta: zap.CommandMeta = .{
        .description = "A CLI tool for testing shell completions",
        .subcommands = &.{ Deploy, Status, DebugInfo },
        .hidden_subcommands = &.{"debug-info"},
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(allocator);
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "--generate-completion-script")) {
        const shell_name = if (argv.len >= 3) argv[2] else {
            var err_buf: [256]u8 = undefined;
            var err_writer = std.Io.File.stderr().writer(init.io, &err_buf);
            err_writer.interface.writeAll("error: missing shell name (fish, zsh, bash)\n") catch {};
            err_writer.interface.flush() catch {};
            std.process.exit(1);
        };
        const shell = std.meta.stringToEnum(zap.complete.Shell, shell_name) orelse {
            var err_buf: [256]u8 = undefined;
            var err_writer = std.Io.File.stderr().writer(init.io, &err_buf);
            err_writer.interface.print("error: unknown shell '{s}'\n", .{shell_name}) catch {};
            err_writer.interface.flush() catch {};
            std.process.exit(1);
        };
        var buf: [8192]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        zap.complete.generate(&writer.interface, ShellCompletion, "shell-completion", shell) catch {
            std.process.exit(1);
        };
        writer.interface.flush() catch {};
        std.process.exit(0);
    }
    return zap.run(ShellCompletion, init);
}
