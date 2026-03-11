const std = @import("std");
const zap = @import("zap");

fn slowSquare(io: std.Io, x: i64) std.Io.Cancelable!i64 {
    try io.sleep(std.Io.Duration.fromSeconds(1), .awake);
    return x * x;
}

const AsyncSquare = struct {
    pub const meta: zap.CommandMeta = .{
        .description = "Compute a square asynchronously",
    };

    value: zap.Positional(i64),

    pub fn run(self: @This(), init: std.process.Init) !void {
        const io = init.io;
        var buf: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(io, &buf);

        const x = self.value.value;
        var future = io.async(slowSquare, .{ io, x });

        try writer.interface.print("Computing {d}^2 asynchronously (1s delay)...\n", .{x});

        var sum: i64 = 0;
        var i: i64 = 0;
        while (i < x) : (i += 1) {
            sum += i;
        }
        try writer.interface.print("Meanwhile, sum(0..{d}) = {d}\n", .{ x, sum });
        try writer.interface.flush();

        const result = try future.await(io);
        try writer.interface.print("Result: {d}^2 = {d}\n", .{ x, result });
        try writer.interface.flush();
    }
};

pub fn main(init: std.process.Init) !void {
    return zap.run(AsyncSquare, init);
}
