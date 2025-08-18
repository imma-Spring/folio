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
        defer this.tokens.deinit();

        const format_tokens = std.DoublyLinkedList(FormaterElement);

        var i: usize = 0;
        while (i < this.tokens.items.len) : (i += 1) {
            const token = this.tokens.items[i];
            var format_node: FormaterElement = undefined;
            switch (token.type) {
                .text => {
                    const text: []const u8 = parseText(token, allocator);
                    format_node.text = text;
                },
                .hashtag => {
                    if (this.isHeader(i)) {
                        const header_level = this.getHeaderLevel(i);
                        format_node.header_start = header_level;
                        i += header_level - 1;
                    } else {
                        const text: []const u8 = parseText(token, allocator);
                        format_node.text = text;
                    }
                },
                else => {},
            }

            format_tokens.append(format_node);
        }

        return format_tokens;
    }

    fn isHeader(this: *TokenFormater, start_index: usize) bool {
        const is_first = start_index == 0;
        const follows_newline = if (start_index > 0) this.tokens.items[start_index - 1].type == .newline else false;

        if (!(is_first or follows_newline)) return false;

        const num_hashes = this.getHeaderLevel(start_index);
        if (num_hashes == 0 or num_hashes > 6) return false;

        const end_index = start_index + (num_hashes - 1);

        const is_last = end_index >= this.tokens.items.len;
        if (is_last) return true;

        const precedes_space = this.tokens.items[end_index].type == .space;
        return precedes_space;
    }

    fn getHeaderLevel(this: *TokenFormater, start_index: usize) usize {
        var index: usize = start_index;
        var num_hashes: usize = 0;

        while (index < this.tokens.items.len and this.tokens.items[index].type == .hashtag) : (index += 1) {
            num_hashes += 1;
        }

        return num_hashes;
    }
};

fn parseText(token: LexerToken, allocator: std.mem.Allocator) []const u8 {
    const text_length: usize = @intFromPtr(token.end) - @intFromPtr(token.start);
    var buffer = allocator.alloc(u8, text_length);
    fillBuffer(&buffer, token.start, text_length);
    return buffer;
}

fn fillBuffer(buffer: *[]u8, start: *u8, length: usize) void {
    for (0..length) |i| {
        const index = @intFromPtr(start) + i;
        buffer.*[i] = @as(*u8, @ptrFromInt(index)).*;
    }
}
