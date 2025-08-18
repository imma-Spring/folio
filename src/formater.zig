const std = @import("std");

const LexerToken = @import("lexer.zig").Token;
const LexerTokenType = @import("lexer.zig").TokenType;
const LexerTokenizer = @import("lexer.zig").Tokenizer;

pub const FormaterElementTag = enum {
    text,
    header_start,
    header_end,
    bold_start,
    bold_end,
    italics_start,
    italics_end,
    code_start,
    code_end,
    code_block_start,
    code_block_end,
};

pub const FormaterElement = union(FormaterElementTag) {
    text: []const u8,
    header_start: HeaderLevel,
    header_end: void,
    bold_start: void,
    bold_end: void,
    italics_start: void,
    italics_end: void,
    code_start: void,
    code_end: void,
    code_block_start: []const u8,
    code_block_end: void,
};

pub const HeaderLevel = enum {
    header_1,
    header_2,
    header_3,
    header_4,
    header_5,
    header_6,
};

pub const TokenFormater = struct {
    tokens: std.ArrayList(LexerToken),
    //mode: std.DoublyLinkedList(Mode) = undefined,

    pub fn format(this: *TokenFormater, tokenizer: LexerTokenizer, allocator: std.mem.Allocator) std.DoublyLinkedList(FormaterElement) {
        this.tokens = tokenizer.getTokens(allocator);
        const format_tokens: std.DoublyLinkedList(FormaterElement) = std.DoublyLinkedList(FormaterElement);

        return format_tokens;
    }
};
