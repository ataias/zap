const std = @import("std");

pub const ParseError = error{
    MissingRequiredOption,
    MissingRequiredArgument,
    UnknownOption,
    InvalidValue,
    UnexpectedPositional,
    MissingOptionValue,
    HelpRequested,
};

pub fn printError(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("error: " ++ fmt ++ "\n", args);
}

pub fn printUsageHint(command_name: []const u8) void {
    std.debug.print("See '{s} --help' for more information.\n", .{command_name});
}

pub fn levenshteinDistance(a: []const u8, b: []const u8) usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    var prev_row: [256]usize = undefined;
    var curr_row: [256]usize = undefined;

    if (b.len + 1 > 256) return @max(a.len, b.len);

    for (0..b.len + 1) |j| prev_row[j] = j;

    for (a, 0..) |ca, i| {
        curr_row[0] = i + 1;
        for (b, 0..) |cb, j| {
            const cost: usize = if (ca == cb) 0 else 1;
            curr_row[j + 1] = @min(
                @min(curr_row[j] + 1, prev_row[j + 1] + 1),
                prev_row[j] + cost,
            );
        }
        @memcpy(prev_row[0 .. b.len + 1], curr_row[0 .. b.len + 1]);
    }

    return prev_row[b.len];
}

pub fn suggestClosest(name: []const u8, candidates: []const []const u8) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_dist: usize = std.math.maxInt(usize);

    for (candidates) |candidate| {
        const dist = levenshteinDistance(name, candidate);
        if (dist < best_dist and dist <= 3) {
            best_dist = dist;
            best = candidate;
        }
    }
    return best;
}

// --- Tests ---

const testing = std.testing;

test "levenshtein identical" {
    try testing.expectEqual(@as(usize, 0), levenshteinDistance("hello", "hello"));
}

test "levenshtein one edit" {
    try testing.expectEqual(@as(usize, 1), levenshteinDistance("verbose", "verbos"));
}

test "levenshtein empty" {
    try testing.expectEqual(@as(usize, 5), levenshteinDistance("", "hello"));
    try testing.expectEqual(@as(usize, 5), levenshteinDistance("hello", ""));
}

test "suggest closest" {
    const candidates = &[_][]const u8{ "verbose", "version", "output" };
    try testing.expectEqualStrings("verbose", suggestClosest("vrebose", candidates).?);
    try testing.expect(suggestClosest("zzzzzzz", candidates) == null);
}
