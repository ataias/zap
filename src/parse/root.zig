const parser = @import("parser.zig");
const tokenizer = @import("tokenizer.zig");
const errors = @import("errors.zig");

pub const parseArgs = parser.parseArgs;

pub const Tokenizer = tokenizer.Tokenizer;
pub const Token = tokenizer.Token;

pub const printError = errors.printError;
pub const suggestClosest = errors.suggestClosest;
pub const levenshteinDistance = errors.levenshteinDistance;

test {
    _ = parser;
    _ = tokenizer;
    _ = errors;
}
