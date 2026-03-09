const std = @import("std");
const zap = @import("zap");

const Args = struct {
    pub const meta: zap.CommandMeta = .{
        .description = "Test that zap works as a packaged dependency",
    };

    test_flag: bool = false,

    pub fn run(self: @This(), init: std.process.Init) !void {
        var buf: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buf);
        if (self.test_flag) {
            try writer.interface.writeAll("SUCCESS: zap works as a packaged dependency\n");
            try writer.interface.flush();
        } else {
            try writer.interface.writeAll("FAILURE: --test-flag was not parsed\n");
            try writer.interface.flush();
            std.process.exit(1);
        }
    }
};

pub fn main(init: std.process.Init) !void {
    return zap.run(Args, init);
}
