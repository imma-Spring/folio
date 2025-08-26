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
    unordered_list_start,
    unordered_list_end,
    unordered_list_item_start,
    unordered_list_item_end,
    ordered_list_start,
    ordered_list_end,
    ordered_list_item_start,
    ordered_list_item_end,
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
    unordered_list_start: void,
    unordered_list_end: void,
    unordered_list_item_start: void,
    unordered_list_item_end: void,
    ordered_list_start: void,
    ordered_list_end: void,
    ordered_list_item_start: void,
    ordered_list_item_end: void,
};

pub const HeaderLevel = enum {
    header_1,
    header_2,
    header_3,
    header_4,
    header_5,
    header_6,
};

pub const Tag = enum {
    bold,
    italics,
    unordered,
    unordered_item,
    ordered,
    ordered_item,
};

pub const Entry = struct {
    type: Tag,
    idx: usize,
};

const ListType = enum {
    ordered,
    unordered,
};

const IndentNode = struct {
    index: usize,
    next: ?*IndentNode = null,
};

pub const TokenFormater = struct {
    const This = @This();

    tokens: std.ArrayList(LexerToken),
    tag: std.DoublyLinkedList(Entry) = std.DoublyLinkedList(Entry),
    in_list: bool = false,
    list_indent_stack: ?*IndentNode = null,

    pub fn format(this: *TokenFormater, tokenizer: LexerTokenizer, allocator: std.mem.Allocator) !std.DoublyLinkedList(FormaterElement) {
        this.tokens = tokenizer.getTokens(allocator);
        defer this.tokens.deinit();

        const format_tokens = std.DoublyLinkedList(FormaterElement);

        var i: usize = 0;
        while (i < this.tokens.items.len) : (i += 1) {
            const token = this.tokens.items[i];
            if (try this.handleToken(token, &i, &format_tokens, allocator)) |format_node| {
                format_tokens.append(format_node);
            }
        }

        return format_tokens;
    }

    fn handleToken(
        this: *This,
        token: LexerToken,
        i: *usize,
        format_tokens: *std.DoublyLinkedList(FormaterElement),
        allocator: std.mem.Allocator,
    ) !?FormaterElement {
        return try switch (token.type) {
            .text => this.handleText(token, allocator),
            .hashtag => this.handleHashtag(i, allocator),
            .back_slash => this.handleBackslash(i.*, token, allocator),
            .underscore => this.handleUnderscore(i, token, allocator),
            .asterisk => this.handleAsterisk(i, format_tokens, allocator, token),
            .plus, .dash => this.handleDashPlus(i, format_tokens, allocator, token),
            .number => this.handleNumber(i, format_tokens, allocator, token),
            else => null,
        };
    }

    fn handleText(this: *This, token: LexerToken, allocator: std.mem.Allocator) !FormaterElement {
        _ = this;
        const text = try parseText(token, allocator);
        return .{ .text = text };
    }

    fn handleHashtag(this: *This, i: *usize, allocator: std.mem.Allocator) !FormaterElement {
        if (this.isHeader(i.*)) {
            const header_level = this.getHeaderLevel(i.*);
            i.* += header_level - 1;
            return .{ .header_start = header_level };
        }
        return try this.handleText(this.tokens.items[i.*], allocator);
    }

    fn handleBackslash(this: *This, i: usize, token: LexerToken, allocator: std.mem.Allocator) !?FormaterElement {
        if ((this.getNumberOfBackslashes(i) & 1) == 1) {
            return try this.handleText(token, allocator);
        }
        return null;
    }

    fn handleUnderscore(this: *This, i: *usize, token: LexerToken, allocator: std.mem.Allocator) !?FormaterElement {
        if (takeByIndex(this.tag, i.*)) |entry| {
            if (entry.type == .bold) i.* += 1;
            return null;
        }
        if (this.getEmphasis(i.*, .underscore)) |tag| {
            this.tag.append(tag);
            return .{ .bold_start = {} };
        }
        return try this.handleText(token, allocator);
    }

    fn handleAsterisk(
        this: *This,
        i: *usize,
        format_tokens: *std.DoublyLinkedList(FormaterElement),
        allocator: std.mem.Allocator,
        token: LexerToken,
    ) !?FormaterElement {
        if (this.isListMarker(i.*, .unordered)) {
            return try this.handleList(i, format_tokens, allocator, .unordered);
        }
        if (takeByIndex(this.tag, i.*)) |entry| {
            if (entry.type == .bold) i.* += 1;
            return null;
        }
        if (this.getEmphasis(i.*, .asterisk)) |tag| {
            this.tag.append(tag);
            return .{ .bold_start = {} };
        }
        return try this.handleText(token, allocator);
    }

    fn handleDash(
        this: *This,
        i: *usize,
        format_tokens: *std.DoublyLinkedList(FormaterElement),
        allocator: std.mem.Allocator,
        token: LexerToken,
    ) !FormaterElement {
        if (this.isListMarker(i.*, .unordered)) {
            return try this.handleList(i, format_tokens, allocator, .unordered);
        }
        return try this.handleText(token, allocator);
    }

    fn handlePlus(
        this: *This,
        i: *usize,
        format_tokens: *std.DoublyLinkedList(FormaterElement),
        allocator: std.mem.Allocator,
        token: LexerToken,
    ) !FormaterElement {
        if (this.isListMarker(i.*, .unordered)) {
            return try this.handleList(i, format_tokens, allocator, .unordered);
        }
        return try this.handleText(token, allocator);
    }

    fn handleNumber(
        this: *This,
        i: *usize,
        format_tokens: *std.DoublyLinkedList(FormaterElement),
        allocator: std.mem.Allocator,
        token: LexerToken,
    ) !FormaterElement {
        if (this.isListMarker(i.*, .ordered)) {
            return try this.handleList(i, format_tokens, allocator, .ordered);
        }
        return try this.handleText(token, allocator);
    }

    fn handleList(
        this: *This,
        i: *usize,
        format_tokens: *std.DoublyLinkedList(FormaterElement),
        allocator: std.mem.Allocator,
        kind: ListType,
    ) !FormaterElement {
        try this.openListIfNeeded(i.*, kind, allocator, format_tokens);
        const end_index = this.findListItemEnd(i.*, this.getIndentation(i.*));
        this.tag.append(.{ .type = (if (kind == .ordered) .ordered_item else .unordered_item), .idx = end_index });
        i.* += (if (kind == .ordered) 2 else 1);
        return switch (kind) {
            .ordered => {
                .{ .ordered_list_item_start = {} };
            },
            .unordered => {
                .{ .unordered_list_item_start = {} };
            },
        };
    }

    fn openListIfNeeded(
        this: *This,
        i: usize,
        kind: ListType,
        allocator: std.mem.Allocator,
        format_tokens: *std.DoublyLinkedList(FormaterElement),
    ) !void {
        const indent_level = this.getIndentation(i);
        if (!this.hasIndent() or indent_level > this.peekIndent()) {
            try this.pushIndent(allocator, indent_level);
            const list_end_index = this.findListEnd(i, indent_level);
            this.tag.append(.{ .type = kind, .idx = list_end_index });
            switch (kind) {
                .unordered => format_tokens.append(.{ .unordered_list_start = {} }),
                .ordered => format_tokens.append(.{ .ordered_list_start = {} }),
            }
        }
    }

    fn findListEnd(this: *This, start_index: usize, indent: usize) usize {
        const tokens = this.tokens.items;
        var j = start_index + 1;
        var newline_count: usize = 0;

        while (j < tokens.len) {
            const token = tokens[j];

            if (token.type == .newline) {
                newline_count += 1;

                if (newline_count == 2) {
                    return j - 1;
                }

                j += 1;
                continue;
            } else {
                newline_count = 0;
            }

            var k = j;
            var depth: usize = 0;
            while (k < tokens.len and tokens[k].type == .tab) : (k += 1) {
                depth += 1;
            }

            if (depth < indent) return j - 1;

            j = k + 1;
        }

        return tokens.len - 1;
    }

    fn pushIndent(this: *TokenFormater, allocator: std.mem.Allocator, indent: usize) !void {
        const node = try allocator.create(IndentNode) catch unreachable;
        node.* = IndentNode{ .indent = indent, .next = this.indent_stack };
        this.indent_stack = node;
    }

    fn popIndent(this: *TokenFormater, allocator: std.mem.Allocator) void {
        if (this.indent_stack) |node| {
            this.indent_stack = node.next;
            allocator.destroy(node);
        }
    }

    fn peekIndent(this: *TokenFormater) usize {
        return if (this.indent_stack) |node| node.indent else 0;
    }

    fn hasIndent(this: *TokenFormater) bool {
        return this.indent_stack != null;
    }
};

fn parseText(token: LexerToken, allocator: std.mem.Allocator) ![]const u8 {
    const text_length: usize = @intFromPtr(token.end) - @intFromPtr(token.start);
    var buffer = try allocator.alloc(u8, text_length);
    fillBuffer(&buffer, token.start, text_length);
    return buffer;
}

fn fillBuffer(buffer: *[]u8, start: *u8, length: usize) void {
    for (0..length) |i| {
        const index = @intFromPtr(start) + i;
        buffer.*[i] = @as(*u8, @ptrFromInt(index)).*;
    }
}

fn takeByIndex(list: *std.DoublyLinkedList(Entry), index: usize) ?Entry {
    var node = list.first;
    while (node) |n| {
        if (n.data.idx == index) {
            list.remove(n);
            return n;
        }
        node = n.next;
    }
    return null;
}
