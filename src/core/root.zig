const types = @import("types.zig");
const text = @import("text.zig");
const introspect_mod = @import("introspect.zig");

pub const CommandMeta = types.CommandMeta;
pub const Positional = types.Positional;
pub const ParseError = types.ParseError;

pub const camelToKebab = text.camelToKebab;
pub const snakeToKebab = text.snakeToKebab;
pub const subcommandName = text.subcommandName;

pub const ArgInfo = introspect_mod.ArgInfo;
pub const ArgKind = introspect_mod.ArgKind;
pub const introspect = introspect_mod.introspect;

test {
    _ = types;
    _ = text;
    _ = introspect_mod;
}
