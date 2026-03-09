const std = @import("std");
pub const fish = @import("complete/fish.zig");
pub const zsh = @import("complete/zsh.zig");
pub const bash = @import("complete/bash.zig");

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
        .zsh => try zsh.generate(writer, Command, cmd_name),
        .bash => try bash.generate(writer, Command, cmd_name),
    }
}

pub fn getCompletionHint(comptime Command: type, comptime field_name: []const u8) CompletionHint {
    if (@hasDecl(Command, "meta") and @hasField(@TypeOf(Command.meta), "field_completions")) {
        const completions = Command.meta.field_completions;
        inline for (@typeInfo(@TypeOf(completions)).@"struct".fields) |f| {
            if (std.mem.eql(u8, f.name, field_name)) {
                return coerceToCompletionHint(@field(completions, f.name));
            }
        }
    }
    return .none;
}

fn coerceToCompletionHint(val: anytype) CompletionHint {
    const T = @TypeOf(val);
    if (T == CompletionHint) return val;

    if (@typeInfo(T) == .@"struct") {
        const fields = @typeInfo(T).@"struct".fields;
        if (fields.len == 1) {
            const name = fields[0].name;
            if (std.mem.eql(u8, name, "values"))
                return .{ .values = val.values };
            if (std.mem.eql(u8, name, "from_command"))
                return .{ .from_command = val.from_command };
            if (std.mem.eql(u8, name, "file_path_with_extensions"))
                return .{ .file_path_with_extensions = val.file_path_with_extensions };
        }
        @compileError("unrecognized completion hint struct");
    }

    return val;
}

pub fn getFieldDescription(comptime Command: type, comptime field_name: []const u8) ?[]const u8 {
    if (@hasDecl(Command, "meta") and @hasField(@TypeOf(Command.meta), "field_descriptions")) {
        const descs = Command.meta.field_descriptions;
        inline for (@typeInfo(@TypeOf(descs)).@"struct".fields) |f| {
            if (std.mem.eql(u8, f.name, field_name)) {
                return @field(descs, f.name);
            }
        }
    }
    return null;
}

pub fn isHiddenComptime(comptime hidden: []const []const u8, comptime name: []const u8) bool {
    for (hidden) |h| {
        if (std.mem.eql(u8, h, name)) return true;
    }
    return false;
}

test {
    _ = fish;
    _ = zsh;
    _ = bash;
}
