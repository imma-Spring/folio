const std = @import("std");

const LexerToken = @import("lexer.zig").Token;
const LexerTokenType = @import("lexer.zig").TokenType;
const LexerTokenizer = @import("lexer.zig").Tokenizer;

pub const TextType = enum {
    header_1,
    header_2,
    header_3,
    header_4,
    header_5,
    header_6,
    text,
};

pub const MarkdownElementTag = enum {
    text,
    ordered_list,
    unordered_list,
    code_block,
    link,
};

pub const MarkdownElement = union(MarkdownElementTag) {
    text: Text,
    ordered_list: OrderedListElement,
    unordered_list: UnorderedListElement,
    code_block: CodeBlock,
    link: Link,
};

pub const MarkdownElementNode = struct {
    element: MarkdownElement,
    next_node: ?*MarkdownElementNode = null,
    prev_node: ?*MarkdownElementNode = null,
};

pub const Text = struct {
    type: TextType,
    content: []const u8,
    bold: bool,
    italics: bool,
    code: bool,
};

pub const OrderedListElement = struct {
    item_number: usize = 1,
    content_start: ?*MarkdownElementNode = null,
    constent_end: ?*MarkdownElementNode = null,
};

pub const UnorderedListElement = struct {
    content_start: ?*MarkdownElementNode = null,
    content_end: ?*MarkdownElementNode = null,
};

pub const Link = struct {
    image: bool = false,
    tag: []const u8,
    link_start: ?*MarkdownElementNode = null,
    link_end: ?*MarkdownElementNode = null,
};

pub const CodeBlock = struct {
    type: []const u8 = undefined,
    content_start: ?*MarkdownElementNode = null,
    content_end: ?*MarkdownElementNode = null,
};

pub const Mode = enum {
    italic,
    bold,
    code,
    list,
};

pub const TokenFormater = struct {
    prev_token: LexerToken = .{.type = .eof, .start = 0, .end = 0},
    current_token: LexerToken = undefined,
    mode: std.ArrayList(Mode) = undefined,

    pub fn format(this: *TokenFormater, tokenizer: LexerTokenizer, allocator: std.mem.Allocator) *MarkdownElementNode {
        this.mode = std.ArrayList(Mode).init(allocator);
        this.current_token = tokenizer.nextToken();
        while (this.current_token.type != .eof) {
            switch () {}
        }
    }
};
