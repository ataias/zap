const std = @import("std");
const zap = @import("zap");

const Add = struct {
    pub const meta: zap.CommandMeta = .{ .description = "Add numbers" };
    values: []const i64,

    pub fn run(self: @This(), init: std.process.Init) !void {
        var sum: i64 = 0;
        for (self.values) |v| sum += v;
        var buf: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        try writer.interface.print("{d}\n", .{sum});
        try writer.interface.flush();
    }
};

const Multiply = struct {
    pub const meta: zap.CommandMeta = .{ .description = "Multiply numbers" };
    values: []const i64,

    pub fn run(self: @This(), init: std.process.Init) !void {
        var product: i64 = 1;
        for (self.values) |v| product *= v;
        var buf: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        try writer.interface.print("{d}\n", .{product});
        try writer.interface.flush();
    }
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
