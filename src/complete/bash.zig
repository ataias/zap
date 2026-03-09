const std = @import("std");
const introspect_mod = @import("../introspect.zig");
const help_mod = @import("../help.zig");
const ArgInfo = introspect_mod.ArgInfo;
const ArgKind = introspect_mod.ArgKind;
const complete_mod = @import("../complete.zig");
const CompletionHint = complete_mod.CompletionHint;
const getCompletionHint = complete_mod.getCompletionHint;
const isHiddenComptime = complete_mod.isHiddenComptime;

pub fn generate(
    writer: *std.Io.Writer,
    comptime Command: type,
    comptime cmd_name: []const u8,
) !void {
    const func_name = comptime cmdToFuncName(cmd_name);

    const has_subcommands = @hasDecl(Command, "meta") and
        @hasField(@TypeOf(Command.meta), "subcommands") and
        Command.meta.subcommands.len > 0;

    try writer.print("_{s}() {{\n", .{func_name});
    try writer.writeAll("    local cur=\"${COMP_WORDS[COMP_CWORD]}\"\n");
    try writer.writeAll("    local prev=\"${COMP_WORDS[COMP_CWORD-1]}\"\n");

    if (has_subcommands) {
        try writeSubcommandBody(writer, Command);
    } else {
        try writeSimpleBody(writer, Command);
    }

    try writer.writeAll("}\n");
    try writer.print("complete -F _{s} {s}\n", .{ func_name, cmd_name });
}

fn writeSimpleBody(
    writer: *std.Io.Writer,
    comptime Command: type,
) !void {
    try writePrevCaseBlock(writer, Command);
    try writeAllOptsCompreply(writer, Command);
}

fn writePrevCaseBlock(
    writer: *std.Io.Writer,
    comptime Command: type,
) !void {
    const arg_infos = comptime introspect_mod.introspect(Command);
    const hidden_fields: []const []const u8 = comptime if (@hasDecl(Command, "meta") and
        @hasField(@TypeOf(Command.meta), "hidden_fields"))
        Command.meta.hidden_fields
    else
        &.{};

    var has_value_options = false;
    inline for (0..arg_infos.len) |i| {
        const ai = arg_infos[i];
        if (comptime isHiddenComptime(hidden_fields, ai.field_name)) continue;
        if (ai.kind == .option) {
            has_value_options = true;
        }
    }

    if (!has_value_options) return;

    try writer.writeAll("\n    case \"$prev\" in\n");

    inline for (0..arg_infos.len) |i| {
        const ai = arg_infos[i];
        if (comptime isHiddenComptime(hidden_fields, ai.field_name)) continue;
        if (ai.kind != .option) continue;

        const hint = comptime getCompletionHint(Command, ai.field_name);

        try writer.print("        --{s}", .{ai.long_name});
        if (ai.short_name) |s| {
            try writer.print("|-{c}", .{s});
        }
        try writer.writeAll(") ");

        if (comptime hint != .none) {
            try writeBashCompletionHint(writer, hint);
            try writer.writeAll("; return ;;\n");
        } else if (ai.enum_values) |vals| {
            try writer.writeAll("COMPREPLY=($(compgen -W \"");
            for (vals, 0..) |v, vi| {
                if (vi > 0) try writer.writeByte(' ');
                try writeBashEscaped(writer, v);
            }
            try writer.writeAll("\" -- \"$cur\")); return ;;\n");
        } else {
            try writer.writeAll("return ;;\n");
        }
    }

    try writer.writeAll("    esac\n");
}

fn writeAllOptsCompreply(
    writer: *std.Io.Writer,
    comptime Command: type,
) !void {
    const arg_infos = comptime introspect_mod.introspect(Command);
    const hidden_fields: []const []const u8 = comptime if (@hasDecl(Command, "meta") and
        @hasField(@TypeOf(Command.meta), "hidden_fields"))
        Command.meta.hidden_fields
    else
        &.{};

    const positional_enums = comptime blk: {
        var vals: []const []const u8 = &.{};
        for (0..arg_infos.len) |i| {
            const ai = arg_infos[i];
            if (isHiddenComptime(hidden_fields, ai.field_name)) continue;
            if (ai.kind == .positional) {
                if (ai.enum_values) |ev| {
                    for (ev) |v| {
                        vals = vals ++ .{v};
                    }
                }
            }
        }
        break :blk vals;
    };

    try writeFilteredCompreply(writer, arg_infos, hidden_fields, "    ", positional_enums);
}

/// Writes a COMPREPLY block that filters out non-repeatable flags already
/// present in COMP_WORDS. Counted flags (e.g. -v -v -v) and --help are always
/// offered. When there are no non-repeatable flags the for-loop is omitted and
/// a plain COMPREPLY assignment is emitted instead.
///
/// Used by both simple commands (writeAllOptsCompreply) and per-subcommand
/// bodies (writeSubcommandBody) to avoid duplicating the filtering logic.
fn writeFilteredCompreply(
    writer: *std.Io.Writer,
    comptime arg_infos: []const introspect_mod.ArgInfo,
    comptime hidden_fields: []const []const u8,
    comptime indent: []const u8,
    comptime positional_enum_values: []const []const u8,
) !void {
    const non_repeatable = comptime blk: {
        var names: []const []const u8 = &.{};
        for (0..arg_infos.len) |i| {
            const ai = arg_infos[i];
            if (isHiddenComptime(hidden_fields, ai.field_name)) continue;
            if (ai.kind == .positional) continue;
            if (ai.kind == .counted_flag) continue;
            names = names ++ .{ai.long_name};
        }
        break :blk names;
    };

    const repeatable = comptime blk: {
        var names: []const []const u8 = &.{};
        for (0..arg_infos.len) |i| {
            const ai = arg_infos[i];
            if (isHiddenComptime(hidden_fields, ai.field_name)) continue;
            if (ai.kind == .counted_flag) {
                names = names ++ .{ai.long_name};
            }
        }
        break :blk names;
    };

    if (non_repeatable.len == 0) {
        try writer.print("\n{s}COMPREPLY=($(compgen -W \"--help", .{indent});
        inline for (repeatable) |name| {
            try writer.print(" --{s}", .{name});
        }
        inline for (positional_enum_values) |v| {
            try writer.writeByte(' ');
            try writeBashEscaped(writer, v);
        }
        try writer.writeAll("\" -- \"$cur\"))\n");
        return;
    }

    try writer.print("\n{s}local _opts=\"\"\n", .{indent});
    try writer.print("{s}for _o in", .{indent});
    inline for (non_repeatable) |name| {
        try writer.print(" --{s}", .{name});
    }
    try writer.writeAll("; do\n");
    try writer.print("{s}    [[ \" ${{COMP_WORDS[*]}} \" == *\" $_o \"* ]] || _opts=\"$_opts $_o\"\n", .{indent});
    try writer.print("{s}done\n", .{indent});

    inline for (repeatable) |name| {
        try writer.print("{s}_opts=\"$_opts --{s}\"\n", .{ indent, name });
    }

    try writer.print("{s}_opts=\"$_opts --help\"\n", .{indent});

    inline for (positional_enum_values) |v| {
        try writer.print("{s}_opts=\"$_opts ", .{indent});
        try writeBashEscaped(writer, v);
        try writer.writeAll("\"\n");
    }

    try writer.print("{s}COMPREPLY=($(compgen -W \"$_opts\" -- \"$cur\"))\n", .{indent});
}

fn writeSubcommandBody(
    writer: *std.Io.Writer,
    comptime Command: type,
) !void {
    const hidden_subcommands: []const []const u8 = if (@hasDecl(Command, "meta") and
        @hasField(@TypeOf(Command.meta), "hidden_subcommands"))
        Command.meta.hidden_subcommands
    else
        &.{};

    try writer.writeAll("\n    if [[ $COMP_CWORD -eq 1 ]]; then\n");
    try writer.writeAll("        local commands=\"");

    var first = true;
    inline for (Command.meta.subcommands) |Sub| {
        const sub_name = comptime help_mod.subcommandName(Sub);
        if (comptime isHiddenComptime(hidden_subcommands, sub_name)) continue;
        if (!first) try writer.writeByte(' ');
        try writer.writeAll(sub_name);
        first = false;
    }
    try writer.writeAll(" --help\"\n");
    try writer.writeAll("        COMPREPLY=($(compgen -W \"$commands\" -- \"$cur\"))\n");
    try writer.writeAll("        return\n");
    try writer.writeAll("    fi\n");

    try writer.writeAll("\n    case \"${COMP_WORDS[1]}\" in\n");

    inline for (Command.meta.subcommands) |Sub| {
        const sub_name = comptime help_mod.subcommandName(Sub);
        if (comptime isHiddenComptime(hidden_subcommands, sub_name)) continue;

        try writer.print("        {s})\n", .{sub_name});

        const sub_arg_infos = comptime introspect_mod.introspect(Sub);
        const sub_hidden: []const []const u8 = comptime if (@hasDecl(Sub, "meta") and
            @hasField(@TypeOf(Sub.meta), "hidden_fields"))
            Sub.meta.hidden_fields
        else
            &.{};

        var has_value_options = false;
        inline for (0..sub_arg_infos.len) |j| {
            const sai = sub_arg_infos[j];
            if (comptime isHiddenComptime(sub_hidden, sai.field_name)) continue;
            if (sai.kind == .option) {
                has_value_options = true;
            }
        }

        if (has_value_options) {
            try writer.writeAll("            case \"$prev\" in\n");
            inline for (0..sub_arg_infos.len) |j| {
                const sai = sub_arg_infos[j];
                if (comptime isHiddenComptime(sub_hidden, sai.field_name)) continue;
                if (sai.kind != .option) continue;

                const hint = comptime getCompletionHint(Sub, sai.field_name);

                try writer.print("                --{s}", .{sai.long_name});
                if (sai.short_name) |s| {
                    try writer.print("|-{c}", .{s});
                }
                try writer.writeAll(") ");

                if (comptime hint != .none) {
                    try writeBashCompletionHint(writer, hint);
                    try writer.writeAll("; return ;;\n");
                } else if (sai.enum_values) |vals| {
                    try writer.writeAll("COMPREPLY=($(compgen -W \"");
                    for (vals, 0..) |v, vi| {
                        if (vi > 0) try writer.writeByte(' ');
                        try writeBashEscaped(writer, v);
                    }
                    try writer.writeAll("\" -- \"$cur\")); return ;;\n");
                } else {
                    try writer.writeAll("return ;;\n");
                }
            }
            try writer.writeAll("            esac\n");
        }

        try writeFilteredCompreply(writer, sub_arg_infos, sub_hidden, "            ", &.{});
        try writer.writeAll("            ;;\n");
    }

    try writer.writeAll("    esac\n");
}

fn writeBashCompletionHint(writer: *std.Io.Writer, hint: CompletionHint) !void {
    switch (hint) {
        .none => {},
        .file_path => try writer.writeAll("COMPREPLY=($(compgen -f -- \"$cur\"))"),
        .file_path_with_extensions => |exts| {
            try writer.writeAll("shopt -s extglob; COMPREPLY=($(compgen -f -X '!*.@(");
            for (exts, 0..) |ext, i| {
                if (i > 0) try writer.writeByte('|');
                try writeBashEscaped(writer, ext);
            }
            try writer.writeAll(")' -- \"$cur\")); COMPREPLY+=($(compgen -d -- \"$cur\"))");
        },
        .dir_path => try writer.writeAll("COMPREPLY=($(compgen -d -- \"$cur\"))"),
        .executable => try writer.writeAll("COMPREPLY=($(compgen -c -- \"$cur\"))"),
        .values => |vals| {
            try writer.writeAll("COMPREPLY=($(compgen -W \"");
            for (vals, 0..) |v, i| {
                if (i > 0) try writer.writeByte(' ');
                try writeBashEscaped(writer, v);
            }
            try writer.writeAll("\" -- \"$cur\"))");
        },
        .from_command => |cmd| {
            try writer.writeAll("COMPREPLY=($(compgen -W \"$(");
            try writeBashEscaped(writer, cmd);
            try writer.writeAll(")\" -- \"$cur\"))");
        },
    }
}

fn writeBashEscaped(writer: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '$' => try writer.writeAll("\\$"),
            '`' => try writer.writeAll("\\`"),
            else => try writer.writeByte(c),
        }
    }
}

fn cmdToFuncName(comptime name: []const u8) []const u8 {
    comptime {
        var result: [name.len]u8 = undefined;
        for (name, 0..) |c, i| {
            result[i] = if (c == '-') '_' else c;
        }
        const final = result;
        return &final;
    }
}

// --- Tests ---

const testing = std.testing;
const CommandMeta = @import("../zap.zig").CommandMeta;
const Positional = @import("../zap.zig").Positional;

test "bash: simple command with flags and options" {
    const Format = enum { json, yaml, text };
    const Cmd = struct {
        pub const meta = .{
            .description = "A test command",
            .field_descriptions = .{
                .output = "Output path",
                .verbose = "Enable verbose output",
            },
        };

        verbose: bool = false,
        output: []const u8,
        port: u16 = 8080,
        format: Format = .json,
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\_tool() {
        \\    local cur="${COMP_WORDS[COMP_CWORD]}"
        \\    local prev="${COMP_WORDS[COMP_CWORD-1]}"
        \\
        \\    case "$prev" in
        \\        --output|-o) return ;;
        \\        --port|-p) return ;;
        \\        --format|-f) COMPREPLY=($(compgen -W "json yaml text" -- "$cur")); return ;;
        \\    esac
        \\
        \\    local _opts=""
        \\    for _o in --verbose --output --port --format; do
        \\        [[ " ${COMP_WORDS[*]} " == *" $_o "* ]] || _opts="$_opts $_o"
        \\    done
        \\    _opts="$_opts --help"
        \\    COMPREPLY=($(compgen -W "$_opts" -- "$cur"))
        \\}
        \\complete -F _tool tool
        \\
    , writer.buffered());
}

test "bash: command with subcommands" {
    const Add = struct {
        pub const meta: CommandMeta = .{ .description = "Add items" };
        verbose: bool = false,
        pub fn run(_: @This(), _: std.process.Init) !void {}
    };
    const Multiply = struct {
        pub const meta: CommandMeta = .{ .description = "Multiply items" };
        pub fn run(_: @This(), _: std.process.Init) !void {}
    };
    const Cli = struct {
        pub const meta: CommandMeta = .{
            .description = "My CLI",
            .subcommands = &.{ Add, Multiply },
        };
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cli, "mycli");

    try testing.expectEqualStrings(
        \\_mycli() {
        \\    local cur="${COMP_WORDS[COMP_CWORD]}"
        \\    local prev="${COMP_WORDS[COMP_CWORD-1]}"
        \\
        \\    if [[ $COMP_CWORD -eq 1 ]]; then
        \\        local commands="add multiply --help"
        \\        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        \\        return
        \\    fi
        \\
        \\    case "${COMP_WORDS[1]}" in
        \\        add)
        \\
        \\            local _opts=""
        \\            for _o in --verbose; do
        \\                [[ " ${COMP_WORDS[*]} " == *" $_o "* ]] || _opts="$_opts $_o"
        \\            done
        \\            _opts="$_opts --help"
        \\            COMPREPLY=($(compgen -W "$_opts" -- "$cur"))
        \\            ;;
        \\        multiply)
        \\
        \\            COMPREPLY=($(compgen -W "--help" -- "$cur"))
        \\            ;;
        \\    esac
        \\}
        \\complete -F _mycli mycli
        \\
    , writer.buffered());
}

test "bash: enum options auto-complete variant names" {
    const Format = enum { json, yaml, text };
    const Cmd = struct {
        format: Format = .json,
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "compgen -W \"json yaml text\" -- \"$cur\"") != null);
}

test "bash: completion hint file_path" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .input = .file_path,
            },
        };
        input: []const u8,
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "compgen -f -- \"$cur\"") != null);
}

test "bash: completion hint dir_path" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .output = .dir_path,
            },
        };
        output: []const u8,
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "compgen -d -- \"$cur\"") != null);
}

test "bash: completion hint values" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .color = .{ .values = &.{ "red", "green", "blue" } },
            },
        };
        color: []const u8,
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "compgen -W \"red green blue\" -- \"$cur\"") != null);
}

test "bash: completion hint from_command" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .name = .{ .from_command = "docker ps --format '{{.Names}}'" },
            },
        };
        name: []const u8,
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "$(docker ps --format '{{.Names}}')") != null);
}

test "bash: completion hint executable" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .shell = .executable,
            },
        };
        shell: []const u8,
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "compgen -c -- \"$cur\"") != null);
}

test "bash: hidden fields excluded" {
    const Cmd = struct {
        pub const meta: CommandMeta = .{
            .description = "A tool",
            .hidden_fields = &.{"debug"},
        };
        verbose: bool = false,
        debug: bool = false,
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "--verbose") != null);
    try testing.expect(std.mem.indexOf(u8, output, "--debug") == null);
}

test "bash: hidden subcommands excluded" {
    const Visible = struct {
        pub const meta: CommandMeta = .{ .description = "Visible cmd" };
        pub fn run(_: @This(), _: std.process.Init) !void {}
    };
    const Hidden = struct {
        pub const meta: CommandMeta = .{ .description = "Hidden cmd" };
        pub fn run(_: @This(), _: std.process.Init) !void {}
    };
    const Cli = struct {
        pub const meta: CommandMeta = .{
            .description = "My CLI",
            .subcommands = &.{ Visible, Hidden },
            .hidden_subcommands = &.{"hidden"},
        };
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cli, "mycli");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "visible") != null);
    try testing.expect(std.mem.indexOf(u8, output, "hidden") == null);
}

test "bash: complete -F line present" {
    const Cmd = struct {
        verbose: bool = false,
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "my-app");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "complete -F _my_app my-app") != null);
    try testing.expect(std.mem.indexOf(u8, output, "_my_app()") != null);
}

test "bash: positional with enum type" {
    const Color = enum { red, green, blue };
    const Cmd = struct {
        color: Positional(Color),
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "red green blue") != null);
}

test "bash: completion hint file_path_with_extensions" {
    const Cmd = struct {
        pub const meta = .{
            .field_completions = .{
                .config = .{ .file_path_with_extensions = &.{ "json", "yaml" } },
            },
        };
        config: []const u8,
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    const output = writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "shopt -s extglob; COMPREPLY=($(compgen -f -X '!*.@(json|yaml)' -- \"$cur\")); COMPREPLY+=($(compgen -d -- \"$cur\"))") != null);
}

test "bash: counted flags can repeat" {
    const Cmd = struct {
        verbosity: u8 = 0,
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cmd, "tool");

    try testing.expectEqualStrings(
        \\_tool() {
        \\    local cur="${COMP_WORDS[COMP_CWORD]}"
        \\    local prev="${COMP_WORDS[COMP_CWORD-1]}"
        \\
        \\    COMPREPLY=($(compgen -W "--help --verbosity" -- "$cur"))
        \\}
        \\complete -F _tool tool
        \\
    , writer.buffered());
}

test "bash: subcommand with option completion hints" {
    const Format = enum { json, yaml };
    const Deploy = struct {
        pub const meta = .{
            .description = "Deploy service",
            .field_completions = .{
                .target = .{ .values = &.{ "prod", "staging" } },
            },
        };
        target: []const u8 = "staging",
        format: Format = .json,
        pub fn run(_: @This(), _: std.process.Init) !void {}
    };
    const Cli = struct {
        pub const meta: CommandMeta = .{
            .description = "My CLI",
            .subcommands = &.{Deploy},
        };
    };

    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try generate(&writer, Cli, "mycli");

    try testing.expectEqualStrings(
        \\_mycli() {
        \\    local cur="${COMP_WORDS[COMP_CWORD]}"
        \\    local prev="${COMP_WORDS[COMP_CWORD-1]}"
        \\
        \\    if [[ $COMP_CWORD -eq 1 ]]; then
        \\        local commands="deploy --help"
        \\        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        \\        return
        \\    fi
        \\
        \\    case "${COMP_WORDS[1]}" in
        \\        deploy)
        \\            case "$prev" in
        \\                --target|-t) COMPREPLY=($(compgen -W "prod staging" -- "$cur")); return ;;
        \\                --format|-f) COMPREPLY=($(compgen -W "json yaml" -- "$cur")); return ;;
        \\            esac
        \\
        \\            local _opts=""
        \\            for _o in --target --format; do
        \\                [[ " ${COMP_WORDS[*]} " == *" $_o "* ]] || _opts="$_opts $_o"
        \\            done
        \\            _opts="$_opts --help"
        \\            COMPREPLY=($(compgen -W "$_opts" -- "$cur"))
        \\            ;;
        \\    esac
        \\}
        \\complete -F _mycli mycli
        \\
    , writer.buffered());
}
