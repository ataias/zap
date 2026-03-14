const std = @import("std");
const introspect_mod = @import("introspect.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const ArgInfo = introspect_mod.ArgInfo;
const ArgKind = introspect_mod.ArgKind;
const zap = @import("zap.zig");
const errors = @import("errors.zig");
const ParseError = errors.ParseError;

fn isPositionalWrapper(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "__zap_positional_marker");
}

fn unwrapOptional(comptime T: type) struct { child: type, is_optional: bool } {
    return switch (@typeInfo(T)) {
        .optional => |opt| .{ .child = opt.child, .is_optional = true },
        else => .{ .child = T, .is_optional = false },
    };
}

fn parseValue(comptime T: type, str: []const u8) !T {
    const info = @typeInfo(T);
    if (T == []const u8) return str;

    if (info == .bool) {
        if (std.mem.eql(u8, str, "true")) return true;
        if (std.mem.eql(u8, str, "false")) return false;
        return error.InvalidValue;
    }

    if (info == .int) {
        return std.fmt.parseInt(T, str, 10) catch return error.InvalidValue;
    }

    if (info == .float) {
        return std.fmt.parseFloat(T, str) catch return error.InvalidValue;
    }

    if (info == .@"enum") {
        return std.meta.stringToEnum(T, str) orelse return error.InvalidValue;
    }

    @compileError("unsupported parse type: " ++ @typeName(T));
}

fn fieldIndex(comptime T: type, comptime name: []const u8) comptime_int {
    const fields = @typeInfo(T).@"struct".fields;
    for (fields, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, name)) return i;
    }
    @compileError("field not found: " ++ name);
}

pub fn parseArgs(comptime T: type, argv: []const []const u8, allocator: std.mem.Allocator, reporter: *std.Io.Writer) ParseError!T {
    const arg_infos = comptime introspect_mod.introspect(T);
    const fields = @typeInfo(T).@"struct".fields;

    var result: T = undefined;
    var field_set = [_]bool{false} ** fields.len;

    inline for (fields, 0..) |f, i| {
        if (f.defaultValue()) |val| {
            @field(result, f.name) = val;
            field_set[i] = true;
        }
    }

    var positional_strings: std.ArrayList([]const u8) = .empty;
    defer positional_strings.deinit(allocator);
    var single_positional_index: usize = 0;

    var tokenizer = Tokenizer.init(argv);

    while (tokenizer.next()) |token| {
        switch (token) {
            .long_flag => |name| {
                if (std.mem.eql(u8, name, "help")) return ParseError.HelpRequested;

                const fi = findFieldByLong(arg_infos, name) orelse {
                    reportUnknown(reporter, name, arg_infos);
                    return ParseError.UnknownOption;
                };

                inline for (fields, 0..) |f, i| {
                    if (comptime arg_infos[i].kind != .positional) {
                        if (i == fi) {
                            try setFlag(T, &result, f, &field_set, i, &tokenizer, reporter);
                        }
                    }
                }
            },
            .long_option => |opt| {
                if (std.mem.eql(u8, opt.name, "help")) return ParseError.HelpRequested;

                const fi = findFieldByLong(arg_infos, opt.name) orelse {
                    reportUnknown(reporter, opt.name, arg_infos);
                    return ParseError.UnknownOption;
                };

                inline for (fields, 0..) |f, i| {
                    if (comptime arg_infos[i].kind != .positional) {
                        if (i == fi) {
                            try setOption(T, &result, f, &field_set, i, opt.value, reporter);
                        }
                    }
                }
            },
            .short_flags => |flags| {
                for (flags) |ch| {
                    if (ch == 'h') return ParseError.HelpRequested;

                    const fi = findFieldByShort(arg_infos, ch) orelse {
                        errors.printError(reporter, "unknown option '-{c}'", .{ch});
                        return ParseError.UnknownOption;
                    };

                    inline for (fields, 0..) |f, i| {
                        if (comptime arg_infos[i].kind != .positional) {
                            if (i == fi) {
                                try handleShortFlag(T, &result, f, &field_set, i, reporter);
                            }
                        }
                    }
                }
            },
            .positional => |value| {
                handlePositional(T, &result, &field_set, &positional_strings, &single_positional_index, value, allocator, reporter) catch |e| return e;
            },
            .terminator => {},
        }
    }

    // Assign collected multi-positional values
    inline for (fields, 0..) |f, i| {
        if (arg_infos[i].is_multi and positional_strings.items.len > 0) {
            const core_type = sliceElementType(f.type);
            var typed_values: std.ArrayList(core_type) = .empty;
            for (positional_strings.items) |str| {
                const parsed = parseValue(core_type, str) catch {
                    errors.printError(reporter, "invalid value '{s}' for argument <{s}>: expected {s}", .{ str, arg_infos[i].long_name, arg_infos[i].type_name });
                    return ParseError.InvalidValue;
                };
                typed_values.append(allocator, parsed) catch return ParseError.InvalidValue;
            }
            @field(result, f.name) = typed_values.toOwnedSlice(allocator) catch return ParseError.InvalidValue;
            field_set[i] = true;
        }
    }

    // Check required fields
    inline for (0..fields.len) |i| {
        if (arg_infos[i].required and !field_set[i]) {
            if (arg_infos[i].kind == .positional) {
                errors.printError(reporter, "missing required argument <{s}>", .{arg_infos[i].long_name});
                return ParseError.MissingRequiredArgument;
            } else {
                errors.printError(reporter, "missing required option '--{s}'", .{arg_infos[i].long_name});
                return ParseError.MissingRequiredOption;
            }
        }
    }

    return result;
}

fn sliceElementType(comptime T: type) type {
    const opt_info = unwrapOptional(T);
    const inner = opt_info.child;
    const info = @typeInfo(inner);
    if (info == .pointer and info.pointer.size == .slice) {
        return info.pointer.child;
    }
    @compileError("not a slice type: " ++ @typeName(T));
}

fn findFieldByLong(arg_infos: []const ArgInfo, name: []const u8) ?usize {
    for (arg_infos, 0..) |ai, i| {
        if (std.mem.eql(u8, ai.long_name, name)) return i;
    }
    return null;
}

fn findFieldByShort(arg_infos: []const ArgInfo, ch: u8) ?usize {
    for (arg_infos, 0..) |ai, i| {
        if (ai.short_name) |s| {
            if (s == ch) return i;
        }
    }
    return null;
}

fn reportUnknown(reporter: *std.Io.Writer, name: []const u8, arg_infos: []const ArgInfo) void {
    var candidates: [64][]const u8 = undefined;
    var count: usize = 0;
    for (arg_infos) |ai| {
        if (count < 64) {
            candidates[count] = ai.long_name;
            count += 1;
        }
    }
    if (errors.suggestClosest(name, candidates[0..count])) |suggestion| {
        errors.printError(reporter, "unknown option '--{s}', did you mean '--{s}'?", .{ name, suggestion });
    } else {
        errors.printError(reporter, "unknown option '--{s}'", .{name});
    }
}

fn setFlag(
    comptime T: type,
    result: *T,
    comptime f: std.builtin.Type.StructField,
    field_set: []bool,
    comptime i: usize,
    tokenizer: *Tokenizer,
    reporter: *std.Io.Writer,
) ParseError!void {
    const opt_info = unwrapOptional(f.type);
    const inner = opt_info.child;

    if (inner == bool) {
        if (opt_info.is_optional) {
            @field(result, f.name) = true;
        } else {
            @field(result, f.name) = true;
        }
        field_set[i] = true;
    } else if (@typeInfo(inner) == .int) {
        const info = comptime introspect_mod.introspect(T);
        if (info[i].kind == .counted_flag) {
            @field(result, f.name) += 1;
            field_set[i] = true;
        } else {
            const val_str = if (tokenizer.next()) |tok| switch (tok) {
                .positional => |v| v,
                else => {
                    errors.printError(reporter, "missing value for option '--{s}'", .{f.name});
                    return ParseError.MissingOptionValue;
                },
            } else {
                errors.printError(reporter, "missing value for option '--{s}'", .{f.name});
                return ParseError.MissingOptionValue;
            };
            const val = parseValue(inner, val_str) catch {
                errors.printError(reporter, "invalid value '{s}' for option '--{s}': expected {s}", .{ val_str, f.name, "integer" });
                return ParseError.InvalidValue;
            };
            if (opt_info.is_optional) {
                @field(result, f.name) = val;
            } else {
                @field(result, f.name) = val;
            }
            field_set[i] = true;
        }
    } else {
        const val_str = if (tokenizer.next()) |tok| switch (tok) {
            .positional => |v| v,
            else => {
                errors.printError(reporter, "missing value for option '--{s}'", .{f.name});
                return ParseError.MissingOptionValue;
            },
        } else {
            errors.printError(reporter, "missing value for option '--{s}'", .{f.name});
            return ParseError.MissingOptionValue;
        };
        const val = parseValue(inner, val_str) catch {
            errors.printError(reporter, "invalid value '{s}' for option '--{s}'", .{ val_str, f.name });
            return ParseError.InvalidValue;
        };
        if (opt_info.is_optional) {
            @field(result, f.name) = val;
        } else {
            @field(result, f.name) = val;
        }
        field_set[i] = true;
    }
}

fn setOption(
    comptime _: type,
    result: anytype,
    comptime f: std.builtin.Type.StructField,
    field_set: []bool,
    comptime i: usize,
    value: []const u8,
    reporter: *std.Io.Writer,
) ParseError!void {
    const opt_info = unwrapOptional(f.type);
    const inner = opt_info.child;
    const parsed = parseValue(inner, value) catch {
        errors.printError(reporter, "invalid value '{s}' for option '--{s}'", .{ value, f.name });
        return ParseError.InvalidValue;
    };
    @field(result, f.name) = parsed;
    field_set[i] = true;
}

fn handleShortFlag(
    comptime _: type,
    result: anytype,
    comptime f: std.builtin.Type.StructField,
    field_set: []bool,
    comptime i: usize,
    reporter: *std.Io.Writer,
) ParseError!void {
    const opt_info = unwrapOptional(f.type);
    const inner = opt_info.child;

    if (inner == bool) {
        @field(result, f.name) = if (opt_info.is_optional) @as(?bool, true) else true;
        field_set[i] = true;
    } else if (@typeInfo(inner) == .int) {
        @field(result, f.name) += 1;
        field_set[i] = true;
    } else {
        errors.printError(reporter, "short flag '-{c}' requires a value; use '--{s} <value>'", .{ f.name[0], f.name });
        return ParseError.MissingOptionValue;
    }
}

fn handlePositional(
    comptime T: type,
    result: *T,
    field_set: []bool,
    positional_strings: *std.ArrayList([]const u8),
    single_positional_index: *usize,
    value: []const u8,
    allocator: std.mem.Allocator,
    reporter: *std.Io.Writer,
) ParseError!void {
    const arg_infos = comptime introspect_mod.introspect(T);
    const fields = @typeInfo(T).@"struct".fields;

    comptime var multi_idx: ?usize = null;
    comptime var single_positionals: [fields.len]usize = undefined;
    comptime var single_count: usize = 0;

    inline for (arg_infos, 0..) |ai, i| {
        if (ai.kind == .positional) {
            if (ai.is_multi) {
                multi_idx = i;
            } else {
                single_positionals[single_count] = i;
                single_count += 1;
            }
        }
    }

    if (single_positional_index.* < single_count) {
        const target_i = single_positionals[single_positional_index.*];
        single_positional_index.* += 1;

        inline for (fields, 0..) |f, i| {
            if (comptime arg_infos[i].kind == .positional and !arg_infos[i].is_multi) {
                const opt_info = comptime unwrapOptional(f.type);
                const inner = opt_info.child;
                const is_wrap = comptime isPositionalWrapper(inner);
                const actual_type = if (is_wrap) inner.Inner else inner;
                if (i == target_i) {
                    const parsed = parseValue(actual_type, value) catch {
                        errors.printError(reporter, "invalid value '{s}' for argument <{s}>", .{ value, arg_infos[i].long_name });
                        return ParseError.InvalidValue;
                    };
                    if (opt_info.is_optional) {
                        @field(result, f.name) = parsed;
                    } else if (is_wrap) {
                        @field(result, f.name) = .{ .value = parsed };
                    } else {
                        @field(result, f.name) = parsed;
                    }
                    field_set[i] = true;
                }
            }
        }
        return;
    }

    if (multi_idx != null) {
        positional_strings.append(allocator, value) catch return ParseError.InvalidValue;
        return;
    }

    errors.printError(reporter, "unexpected positional argument '{s}'", .{value});
    return ParseError.UnexpectedPositional;
}

// --- Tests ---

const testing = std.testing;

fn testReporter(buf: []u8) std.Io.Writer {
    return std.Io.Writer.fixed(buf);
}

test "parse simple flags" {
    const Cmd = struct {
        verbose: bool = false,
        hex_output: bool = false,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    const result = try parseArgs(Cmd, &.{ "--verbose", "--hex-output" }, testing.allocator, &reporter);
    try testing.expect(result.verbose);
    try testing.expect(result.hex_output);
}

test "parse short flags combined" {
    const Cmd = struct {
        verbose: bool = false,
        force: bool = false,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    const result = try parseArgs(Cmd, &.{"-vf"}, testing.allocator, &reporter);
    try testing.expect(result.verbose);
    try testing.expect(result.force);
}

test "parse option with value" {
    const Cmd = struct {
        port: u16 = 8080,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    const result = try parseArgs(Cmd, &.{ "--port", "3000" }, testing.allocator, &reporter);
    try testing.expectEqual(@as(u16, 3000), result.port);
}

test "parse option with equals" {
    const Cmd = struct {
        port: u16 = 8080,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    const result = try parseArgs(Cmd, &.{"--port=3000"}, testing.allocator, &reporter);
    try testing.expectEqual(@as(u16, 3000), result.port);
}

test "parse string option" {
    const Cmd = struct {
        output: []const u8,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    const result = try parseArgs(Cmd, &.{ "--output", "foo.txt" }, testing.allocator, &reporter);
    try testing.expectEqualStrings("foo.txt", result.output);
}

test "parse enum option" {
    const Mode = enum { fast, slow };
    const Cmd = struct {
        mode: Mode = .fast,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    const result = try parseArgs(Cmd, &.{ "--mode", "slow" }, testing.allocator, &reporter);
    try testing.expectEqual(Mode.slow, result.mode);
}

test "parse multi-positional" {
    const Cmd = struct {
        values: []const i64,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    const result = try parseArgs(Cmd, &.{ "1", "2", "3" }, testing.allocator, &reporter);
    defer testing.allocator.free(result.values);
    try testing.expectEqual(@as(usize, 3), result.values.len);
    try testing.expectEqual(@as(i64, 1), result.values[0]);
    try testing.expectEqual(@as(i64, 2), result.values[1]);
    try testing.expectEqual(@as(i64, 3), result.values[2]);
}

test "missing required option" {
    const Cmd = struct {
        output: []const u8,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    try testing.expectError(ParseError.MissingRequiredOption, parseArgs(Cmd, &.{}, testing.allocator, &reporter));
    try testing.expectEqualStrings("error: missing required option '--output'\n", reporter.buffered());
}

test "unknown option" {
    const Cmd = struct {
        verbose: bool = false,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    try testing.expectError(ParseError.UnknownOption, parseArgs(Cmd, &.{"--vrebose"}, testing.allocator, &reporter));
    try testing.expectEqualStrings("error: unknown option '--vrebose', did you mean '--verbose'?\n", reporter.buffered());
}

test "invalid value" {
    const Cmd = struct {
        port: u16 = 8080,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    try testing.expectError(ParseError.InvalidValue, parseArgs(Cmd, &.{ "--port", "abc" }, testing.allocator, &reporter));
    try testing.expectEqualStrings("error: invalid value 'abc' for option '--port': expected integer\n", reporter.buffered());
}

test "help requested" {
    const Cmd = struct {
        verbose: bool = false,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    try testing.expectError(ParseError.HelpRequested, parseArgs(Cmd, &.{"--help"}, testing.allocator, &reporter));
    try testing.expectError(ParseError.HelpRequested, parseArgs(Cmd, &.{"-h"}, testing.allocator, &reporter));
}

test "terminator sends remaining to positionals" {
    const Cmd = struct {
        verbose: bool = false,
        values: []const i64,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    const result = try parseArgs(Cmd, &.{ "--verbose", "--", "1", "2" }, testing.allocator, &reporter);
    defer testing.allocator.free(result.values);
    try testing.expect(result.verbose);
    try testing.expectEqual(@as(usize, 2), result.values.len);
}

test "counted flag" {
    const Cmd = struct {
        count: u8 = 0,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    const result = try parseArgs(Cmd, &.{ "-c", "-c", "-c" }, testing.allocator, &reporter);
    try testing.expectEqual(@as(u8, 3), result.count);
}

test "missing required argument" {
    const Cmd = struct {
        name: zap.Positional([]const u8),
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    try testing.expectError(ParseError.MissingRequiredArgument, parseArgs(Cmd, &.{}, testing.allocator, &reporter));
    try testing.expectEqualStrings("error: missing required argument <name>\n", reporter.buffered());
}

test "unexpected positional" {
    const Cmd = struct {
        verbose: bool = false,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    try testing.expectError(ParseError.UnexpectedPositional, parseArgs(Cmd, &.{"foo"}, testing.allocator, &reporter));
    try testing.expectEqualStrings("error: unexpected positional argument 'foo'\n", reporter.buffered());
}

test "missing option value" {
    const Cmd = struct {
        output: []const u8,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    try testing.expectError(ParseError.MissingOptionValue, parseArgs(Cmd, &.{"--output"}, testing.allocator, &reporter));
    try testing.expectEqualStrings("error: missing value for option '--output'\n", reporter.buffered());
}

test "optional option" {
    const Cmd = struct {
        output: ?[]const u8 = null,
    };
    var buf: [4096]u8 = undefined;
    var reporter = testReporter(&buf);
    const result = try parseArgs(Cmd, &.{}, testing.allocator, &reporter);
    try testing.expect(result.output == null);

    const result2 = try parseArgs(Cmd, &.{ "--output", "foo" }, testing.allocator, &reporter);
    try testing.expectEqualStrings("foo", result2.output.?);
}
