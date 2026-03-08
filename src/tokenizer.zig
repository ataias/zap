const std = @import("std");

pub const Token = union(enum) {
    long_flag: []const u8,
    long_option: struct {
        name: []const u8,
        value: []const u8,
    },
    short_flags: []const u8,
    positional: []const u8,
    terminator,
};

pub const Tokenizer = struct {
    args: []const []const u8,
    index: usize,
    terminated: bool,

    pub fn init(args: []const []const u8) Tokenizer {
        return .{
            .args = args,
            .index = 0,
            .terminated = false,
        };
    }

    pub fn next(self: *Tokenizer) ?Token {
        if (self.index >= self.args.len) return null;

        const arg = self.args[self.index];
        self.index += 1;

        if (self.terminated) {
            return .{ .positional = arg };
        }

        if (std.mem.eql(u8, arg, "--")) {
            self.terminated = true;
            return .terminator;
        }

        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-') {
            const rest = arg[2..];
            if (std.mem.indexOfScalar(u8, rest, '=')) |eq_pos| {
                return .{ .long_option = .{
                    .name = rest[0..eq_pos],
                    .value = rest[eq_pos + 1 ..],
                } };
            }
            return .{ .long_flag = rest };
        }

        if (arg.len > 1 and arg[0] == '-' and arg[1] != '-') {
            return .{ .short_flags = arg[1..] };
        }

        return .{ .positional = arg };
    }

    pub fn collectAll(self: *Tokenizer, allocator: std.mem.Allocator) ![]const Token {
        var tokens: std.ArrayList(Token) = .{};
        defer tokens.deinit(allocator);
        while (self.next()) |tok| {
            try tokens.append(allocator, tok);
        }
        return try tokens.toOwnedSlice(allocator);
    }
};

// --- Tests ---

const testing = std.testing;

test "long flag" {
    var t = Tokenizer.init(&.{"--verbose"});
    const tok = t.next().?;
    try testing.expectEqualStrings("verbose", tok.long_flag);
    try testing.expect(t.next() == null);
}

test "long option with equals" {
    var t = Tokenizer.init(&.{"--port=3000"});
    const tok = t.next().?;
    try testing.expectEqualStrings("port", tok.long_option.name);
    try testing.expectEqualStrings("3000", tok.long_option.value);
}

test "short flags" {
    var t = Tokenizer.init(&.{"-vx"});
    const tok = t.next().?;
    try testing.expectEqualStrings("vx", tok.short_flags);
}

test "positional" {
    var t = Tokenizer.init(&.{"hello"});
    const tok = t.next().?;
    try testing.expectEqualStrings("hello", tok.positional);
}

test "terminator" {
    var t = Tokenizer.init(&.{ "--", "--verbose", "file" });
    try testing.expect(t.next().? == .terminator);
    try testing.expectEqualStrings("--verbose", t.next().?.positional);
    try testing.expectEqualStrings("file", t.next().?.positional);
    try testing.expect(t.next() == null);
}

test "mixed args" {
    var t = Tokenizer.init(&.{ "--output", "foo.txt", "-v", "pos1", "--", "--not-a-flag" });
    try testing.expectEqualStrings("output", t.next().?.long_flag);
    try testing.expectEqualStrings("foo.txt", t.next().?.positional);
    try testing.expectEqualStrings("v", t.next().?.short_flags);
    try testing.expectEqualStrings("pos1", t.next().?.positional);
    try testing.expect(t.next().? == .terminator);
    try testing.expectEqualStrings("--not-a-flag", t.next().?.positional);
}

test "single dash is positional" {
    var t = Tokenizer.init(&.{"-"});
    const tok = t.next().?;
    try testing.expectEqualStrings("-", tok.positional);
}

test "empty string is positional" {
    var t = Tokenizer.init(&.{""});
    const tok = t.next().?;
    try testing.expectEqualStrings("", tok.positional);
}
