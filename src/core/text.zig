const std = @import("std");

pub fn snakeToKebab(comptime name: []const u8) []const u8 {
    comptime {
        var result: [name.len]u8 = undefined;
        for (name, 0..) |c, i| {
            result[i] = if (c == '_') '-' else c;
        }
        const final = result;
        return &final;
    }
}

pub fn camelToKebab(comptime name: []const u8) []const u8 {
    comptime {
        var len: usize = 0;
        for (name, 0..) |c, i| {
            if (c >= 'A' and c <= 'Z' and i > 0) len += 1;
            len += 1;
        }
        var result: [len]u8 = undefined;
        var j: usize = 0;
        for (name, 0..) |c, i| {
            if (c >= 'A' and c <= 'Z' and i > 0) {
                result[j] = '-';
                j += 1;
            }
            result[j] = if (c >= 'A' and c <= 'Z') c + 32 else c;
            j += 1;
        }
        const final = result;
        return &final;
    }
}

pub fn subcommandName(comptime T: type) []const u8 {
    comptime {
        const full = @typeName(T);
        const short = if (std.mem.lastIndexOfScalar(u8, full, '.')) |dot|
            full[dot + 1 ..]
        else
            full;
        return camelToKebab(short);
    }
}

// --- Tests ---

const testing = std.testing;

test "camelToKebab" {
    try testing.expectEqualStrings("add", comptime camelToKebab("Add"));
    try testing.expectEqualStrings("multiply", comptime camelToKebab("Multiply"));
    try testing.expectEqualStrings("hex-output", comptime camelToKebab("HexOutput"));
    try testing.expectEqualStrings("standard-deviation", comptime camelToKebab("StandardDeviation"));
}

test "snakeToKebab" {
    try testing.expectEqualStrings("hex-output", comptime snakeToKebab("hex_output"));
    try testing.expectEqualStrings("verbose", comptime snakeToKebab("verbose"));
}
