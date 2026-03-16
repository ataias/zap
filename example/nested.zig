const std = @import("std");
const zap = @import("zap");

const Start = struct {
    pub const meta: zap.CommandMeta = .{ .description = "Start the server" };
    port: u16 = 8080,

    pub fn run(self: @This(), init: std.process.Init) !void {
        var buf: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        try writer.interface.print("starting server on port {d}\n", .{self.port});
        try writer.interface.flush();
    }
};

const Stop = struct {
    pub const meta: zap.CommandMeta = .{ .description = "Stop the server" };
    force: bool = false,

    pub fn run(self: @This(), init: std.process.Init) !void {
        var buf: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        if (self.force) {
            try writer.interface.writeAll("force stopping server\n");
        } else {
            try writer.interface.writeAll("stopping server\n");
        }
        try writer.interface.flush();
    }
};

const Server = struct {
    pub const meta: zap.CommandMeta = .{
        .description = "Server management",
        .subcommands = &.{ Start, Stop },
    };
};

const Version = struct {
    pub const meta: zap.CommandMeta = .{ .description = "Print version" };

    pub fn run(_: @This(), init: std.process.Init) !void {
        var buf: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        try writer.interface.writeAll("1.0.0\n");
        try writer.interface.flush();
    }
};

const Nested = struct {
    pub const meta: zap.CommandMeta = .{
        .description = "A CLI with nested subcommands",
        .subcommands = &.{ Server, Version },
    };
};

pub fn main(init: std.process.Init) !void {
    return zap.run(Nested, init);
}
