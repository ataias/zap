const std = @import("std");
const zap = @import("zap");

const Add = struct {
    pub const meta: zap.CommandMeta = .{
        .description = "Add numbers and print the result",
    };

    verbose: bool = false,
    values: []const i64,

    pub fn run(self: @This(), init: std.process.Init) !void {
        var sum: i64 = 0;
        for (self.values) |v| sum += v;

        var buf: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        if (self.verbose) {
            for (self.values, 0..) |v, i| {
                if (i > 0) try writer.interface.writeAll(" + ");
                try writer.interface.print("{d}", .{v});
            }
            try writer.interface.print(" = {d}\n", .{sum});
        } else {
            try writer.interface.print("{d}\n", .{sum});
        }
        try writer.interface.flush();
    }
};

pub fn main(init: std.process.Init) !void {
    return zap.run(Add, init);
}
