pub const CommandMeta = struct {
    description: []const u8 = "",
    subcommands: []const type = &.{},
    hidden_fields: []const []const u8 = &.{},
    hidden_subcommands: []const []const u8 = &.{},
};

pub fn Positional(comptime T: type) type {
    return struct {
        pub const __zap_positional_marker = {};
        pub const Inner = T;
        value: T,
    };
}

pub const ParseError = error{
    MissingRequiredOption,
    MissingRequiredArgument,
    UnknownOption,
    InvalidValue,
    UnexpectedPositional,
    MissingOptionValue,
    HelpRequested,
};
