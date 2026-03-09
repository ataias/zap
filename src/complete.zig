const std = @import("std");
pub const fish = @import("complete/fish.zig");

pub const Shell = enum { fish, zsh, bash };

pub const CompletionHint = union(enum) {
    none,
    file_path,
    file_path_with_extensions: []const []const u8,
    dir_path,
    executable,
    values: []const []const u8,
    from_command: []const u8,
};

pub fn generate(
    writer: *std.Io.Writer,
    comptime Command: type,
    comptime cmd_name: []const u8,
    shell: Shell,
) !void {
    switch (shell) {
        .fish => try fish.generate(writer, Command, cmd_name),
        else => return error.NotImplemented,
    }
}

test {
    _ = fish;
}
