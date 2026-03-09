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
            .service = "Service name",
            .config = "Config file path",
        },
        .field_completions = .{
            .target = .{ .values = &.{ "prod", "staging", "dev" } },
            .service = .{ .from_command = "echo web api worker" },
            .config = .{ .file_path_with_extensions = &.{ "json", "yaml" } },
        },
    };

    target: []const u8,
    format: Format = .json,
    port: u16 = 8080,
    verbose: bool = false,
    count: u8 = 0,
    service: []const u8 = "web",
    config: []const u8 = "config.json",
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
    return zap.run(ShellCompletion, init);
}
