const std = @import("std");

pub const ArgKind = enum {
    flag,
    counted_flag,
    option,
    positional,
};

pub const ArgInfo = struct {
    field_name: []const u8,
    long_name: []const u8,
    short_name: ?u8,
    kind: ArgKind,
    required: bool,
    type_name: []const u8,
    default_text: ?[]const u8,
    is_multi: bool,
    enum_values: ?[]const []const u8,
};

fn isPositionalWrapper(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "__zap_positional_marker");
}

fn unwrapPositional(comptime T: type) type {
    if (isPositionalWrapper(T)) return T.Inner;
    return T;
}

fn unwrapOptional(comptime T: type) struct { child: type, is_optional: bool } {
    return switch (@typeInfo(T)) {
        .optional => |opt| .{ .child = opt.child, .is_optional = true },
        else => .{ .child = T, .is_optional = false },
    };
}

fn snakeToKebab(comptime name: []const u8) []const u8 {
    comptime {
        var result: [name.len]u8 = undefined;
        for (name, 0..) |c, i| {
            result[i] = if (c == '_') '-' else c;
        }
        const final = result;
        return &final;
    }
}

fn typeDisplayName(comptime T: type) []const u8 {
    const info = @typeInfo(T);
    return switch (info) {
        .bool => "boolean",
        .int => "integer",
        .float => "number",
        .@"enum" => "enum",
        else => if (T == []const u8) "string" else @typeName(T),
    };
}

fn formatDefault(comptime T: type, comptime val: T) []const u8 {
    comptime {
        const info = @typeInfo(T);
        if (info == .bool) {
            return if (val) "true" else "false";
        }
        if (info == .int) {
            return std.fmt.comptimePrint("{d}", .{val});
        }
        if (info == .float) {
            return std.fmt.comptimePrint("{d}", .{val});
        }
        if (info == .@"enum") {
            return @tagName(val);
        }
        if (info == .optional) {
            return "null";
        }
        if (T == []const u8) {
            return "\"" ++ val ++ "\"";
        }
        return "?";
    }
}

pub fn introspect(comptime T: type) []const ArgInfo {
    comptime {
        const fields = @typeInfo(T).@"struct".fields;
        var args: [fields.len]ArgInfo = undefined;
        var used_shorts = [_]bool{false} ** 256;
        used_shorts['h'] = true;

        var short_names: [fields.len]?u8 = .{null} ** fields.len;
        for (fields, 0..) |field, i| {
            const first_char = field.name[0];
            if (!used_shorts[first_char]) {
                used_shorts[first_char] = true;
                short_names[i] = first_char;
            }
        }

        for (fields, 0..) |field, i| {
            const raw_type = field.type;
            const opt_info = unwrapOptional(raw_type);
            const is_optional = opt_info.is_optional;
            const inner_type = opt_info.child;

            const is_positional_wrap = isPositionalWrapper(inner_type);
            const core_type = if (is_positional_wrap) unwrapPositional(inner_type) else inner_type;

            const core_info = @typeInfo(core_type);
            const is_slice = core_info == .pointer and core_info.pointer.size == .slice and core_type != []const u8;
            const has_default = field.defaultValue() != null;

            var kind: ArgKind = undefined;
            var required: bool = undefined;
            var is_multi = false;

            if (is_positional_wrap or is_slice) {
                kind = .positional;
                is_multi = is_slice;
                required = if (is_slice) !has_default else !is_optional;
            } else if (core_type == bool) {
                kind = .flag;
                required = false;
            } else if (core_info == .int and has_default) {
                if (field.defaultValue().? == 0) {
                    kind = .counted_flag;
                    required = false;
                } else {
                    kind = .option;
                    required = false;
                }
            } else {
                kind = .option;
                required = !is_optional and !has_default;
            }

            const default_text: ?[]const u8 = if (field.defaultValue()) |val|
                formatDefault(raw_type, val)
            else
                null;

            const enum_values: ?[]const []const u8 = if (@typeInfo(core_type) == .@"enum") blk: {
                const enum_fields = @typeInfo(core_type).@"enum".fields;
                var names: [enum_fields.len][]const u8 = undefined;
                for (enum_fields, 0..) |ef, ei| {
                    names[ei] = ef.name;
                }
                const final = names;
                break :blk &final;
            } else null;

            args[i] = .{
                .field_name = field.name,
                .long_name = snakeToKebab(field.name),
                .short_name = short_names[i],
                .kind = kind,
                .required = required,
                .type_name = typeDisplayName(core_type),
                .default_text = default_text,
                .is_multi = is_multi,
                .enum_values = enum_values,
            };
        }

        const final = args;
        return &final;
    }
}

// --- Tests ---

const testing = std.testing;

test "bool flag" {
    const Cmd = struct { verbose: bool = false };
    const args = comptime introspect(Cmd);
    try testing.expectEqual(1, args.len);
    try testing.expectEqualStrings("verbose", args[0].field_name);
    try testing.expectEqualStrings("verbose", args[0].long_name);
    try testing.expectEqual(ArgKind.flag, args[0].kind);
    try testing.expect(!args[0].required);
    try testing.expectEqual(@as(?u8, 'v'), args[0].short_name);
}

test "counted flag" {
    const Cmd = struct { count: u8 = 0 };
    const args = comptime introspect(Cmd);
    try testing.expectEqual(ArgKind.counted_flag, args[0].kind);
    try testing.expect(!args[0].required);
}

test "required string option" {
    const Cmd = struct { output: []const u8 };
    const args = comptime introspect(Cmd);
    try testing.expectEqual(ArgKind.option, args[0].kind);
    try testing.expect(args[0].required);
    try testing.expectEqualStrings("string", args[0].type_name);
}

test "optional string option" {
    const Cmd = struct { output: ?[]const u8 = null };
    const args = comptime introspect(Cmd);
    try testing.expectEqual(ArgKind.option, args[0].kind);
    try testing.expect(!args[0].required);
}

test "integer option with non-zero default" {
    const Cmd = struct { port: u16 = 8080 };
    const args = comptime introspect(Cmd);
    try testing.expectEqual(ArgKind.option, args[0].kind);
    try testing.expect(!args[0].required);
    try testing.expectEqualStrings("8080", args[0].default_text.?);
}

test "required integer option" {
    const Cmd = struct { port: u16 };
    const args = comptime introspect(Cmd);
    try testing.expectEqual(ArgKind.option, args[0].kind);
    try testing.expect(args[0].required);
}

test "slice positional" {
    const Cmd = struct { values: []const i64 };
    const args = comptime introspect(Cmd);
    try testing.expectEqual(ArgKind.positional, args[0].kind);
    try testing.expect(args[0].required);
    try testing.expect(args[0].is_multi);
}

test "enum option" {
    const Mode = enum { fast, slow };
    const Cmd = struct { mode: Mode = .fast };
    const args = comptime introspect(Cmd);
    try testing.expectEqual(ArgKind.option, args[0].kind);
    try testing.expect(!args[0].required);
    try testing.expectEqualStrings("fast", args[0].default_text.?);
    try testing.expectEqual(@as(usize, 2), args[0].enum_values.?.len);
    try testing.expectEqualStrings("fast", args[0].enum_values.?[0]);
    try testing.expectEqualStrings("slow", args[0].enum_values.?[1]);
}

test "non-enum field has null enum_values" {
    const Cmd = struct { verbose: bool = false };
    const args = comptime introspect(Cmd);
    try testing.expectEqual(@as(?[]const []const u8, null), args[0].enum_values);
}

test "optional enum field populates enum_values" {
    const Color = enum { red, green, blue };
    const Cmd = struct { color: ?Color = null };
    const args = comptime introspect(Cmd);
    try testing.expectEqual(@as(usize, 3), args[0].enum_values.?.len);
    try testing.expectEqualStrings("red", args[0].enum_values.?[0]);
    try testing.expectEqualStrings("green", args[0].enum_values.?[1]);
    try testing.expectEqualStrings("blue", args[0].enum_values.?[2]);
}

test "snake_case to kebab-case" {
    const Cmd = struct { hex_output: bool = false };
    const args = comptime introspect(Cmd);
    try testing.expectEqualStrings("hex-output", args[0].long_name);
}

test "short name collision" {
    const Cmd = struct { verbose: bool = false, version: bool = false };
    const args = comptime introspect(Cmd);
    try testing.expectEqual(@as(?u8, 'v'), args[0].short_name);
    try testing.expectEqual(@as(?u8, null), args[1].short_name);
}
