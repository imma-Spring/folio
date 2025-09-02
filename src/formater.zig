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
    inline_code,
    code_block,
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
    in_list: bool = false, // might use this later, keeping this in so i dont forget about and easy way to hadle things with lists
    // ill probably still do something brain dead and this will just be a relic of what could have been if
    // i wast so fucking stupid
    in_code: bool = false,
    line: usize = 0,
    line_indents: std.ArrayList(usize),
    line_indent: []usize,
    list_indent_stack: ?*IndentNode = null,

    pub fn format(this: *TokenFormater, tokenizer: LexerTokenizer, allocator: std.mem.Allocator) !std.DoublyLinkedList(FormaterElement) {
        this.tokens = tokenizer.getTokens(allocator);
        defer this.tokens.deinit();

        const line_n = this.countLines();
        this.line_indents = try std.ArrayList(usize).initCapacity(allocator, line_n);
        defer this.line_indents.deinit();

        try this.computeLineIndents();

        this.line_indent = this.line_indents.items;
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
            .plus => this.handlePlus(i, format_tokens, allocator, token),
            .dash => this.handleDash(i, format_tokens, allocator, token),
            .back_tick => this.handleBackTick(i, format_tokens, allocator, token),
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
        if (!this.in_code and this.isHeader(i.*)) {
            const header_level = this.getHeaderLevel(i.*);
            i.* += header_level - 1;
            return .{ .header_start = header_level };
        }
        return try this.handleText(this.tokens.items[i.*], allocator);
    }

    fn handleBackslash(this: *This, i: usize, token: LexerToken, allocator: std.mem.Allocator) !?FormaterElement {
        if (!this.in_code and (this.getNumberOfBackslashes(i) & 1) == 1) {
            return try this.handleText(token, allocator);
        }
        return null;
    }

    fn handleUnderscore(this: *This, i: *usize, token: LexerToken, allocator: std.mem.Allocator) !?FormaterElement {
        if (takeByIndex(this.tag, i.*)) |entry| {
            switch (entry.type) {
                .bold => {
                    i.* += 1;
                    return .{ .bold_end = {} };
                },
                .italics => {
                    return .{ .italics_end = {} };
                },
                else => return null,
            }
            if (entry.type == .bold) i.* += 1;
            return null;
        }
        if (!this.in_code and this.getEmphasis(i.*, .underscore)) |tag| {
            this.tag.append(tag);
            return switch (tag.type) {
                .bold => {
                    i.* += 1;
                    .{ .bold_start = {} };
                },
                .italics => .{ .italics_start = {} },
                else => null,
            };
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
            switch (entry.type) {
                .bold => {
                    i.* += 1;
                    return .{ .bold_end = {} };
                },
                .italics => {
                    return .{ .italics_end = {} };
                },
                else => return null,
            }
            if (entry.type == .bold) i.* += 1;
            return null;
        }
        if (!this.in_code and this.getEmphasis(i.*, .asterisk)) |tag| {
            this.tag.append(tag);
            return switch (tag.type) {
                .bold => {
                    i.* += 1;
                    .{ .bold_start = {} };
                },
                .italics => .{ .italics_start = {} },
                else => null,
            };
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
        if (!this.in_code and this.isListMarker(i.*, .unordered)) {
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
        if (!this.in_code and this.isListMarker(i.*, .unordered)) {
            return try this.handleList(i, format_tokens, allocator, .unordered);
        }
        return try this.handleText(token, allocator);
    }

    fn handleBackTick(
        this: *This,
        i: *usize,
        allocator: std.mem.Allocator,
        token: LexerToken,
    ) !?FormaterElement {
        if (takeByIndex(this.tag, i.*)) |tag| {
            this.in_code = false;
            switch (tag.type) {
                .inline_code => {
                    i.* = this.skipTokens(i.*, .back_tick) - 1;
                    return .{ .code_end = {} };
                },
                .code_block => {
                    i.* = this.skipTokens(i.*, .back_tick) - 1;
                    return .{ .code_block_end = {} };
                },
                else => return null,
            }
        }
        if (this.getCodeType(i.*)) |tag| {
            this.tag.append(tag);
            this.in_code = true;
            return switch (tag.type) {
                .inline_code => {
                    i.* = this.skipTokens(i.*, .back_tick) - 1;
                    .{ .code_start = {} };
                },
                .code_block => {
                    i.* = this.skipTokens(i.*, .back_tick) - 1;
                    .{ .code_block_start = {} };
                },
                else => null,
            };
        }
        return try this.handleText(token, allocator);
    }

    fn skipTokens(this: *This, idx: usize, token: LexerTokenType) usize {
        var skip: usize = 0;
        var i = idx;
        while (this.tokens.items[i].type == token) : (i += 1) {
            skip += 1;
        }

        return skip;
    }

    fn handleNumber(
        this: *This,
        i: *usize,
        format_tokens: *std.DoublyLinkedList(FormaterElement),
        allocator: std.mem.Allocator,
        token: LexerToken,
    ) !FormaterElement {
        if (!this.in_code and this.isListMarker(i.*, .ordered)) {
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
        const end_index = this.findListItemEnd(i.*, this.line_indent[this.line]);
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
        const indent_level = this.line_indent[this.line];
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
        var line = this.line;

        while (j < tokens.len) {
            const token = tokens[j];

            if (token.type == .newline) {
                newline_count += 1;
                line += 1;

                if (newline_count == 2) {
                    return j - 1;
                }

                j += 1;
                continue;
            } else {
                newline_count = 0;
            }

            const depth = this.line_indent[line];

            if (depth < indent) return j - 1;

            j += 1;
        }

        return tokens.len - 1;
    }

    fn findListItemEnd(this: *This, start_index: usize, indent: usize) usize {
        const tokens = this.tokens.items;
        var j = start_index + 1;
        var newline_count: usize = 0;
        var line = this.line;

        while (j < tokens.len) {
            const token = tokens[j];

            if (token.type == .newline) {
                newline_count += 1;
                line += 1;

                if (newline_count == 2) return j - 1;

                j += 1;
                continue;
            } else {
                newline_count = 0;
            }

            const depth = this.line_indent[line];

            if (depth == indent and this.isListMarker(j)) {
                return j - 1;
            }
            if (depth < indent) {
                return j - 1;
            }

            j += 1;
        }

        return tokens.len - 1;
    }

    fn isListMarker(this: *This, idx: usize) bool {
        const tokens = this.tokens.items;
        if (idx >= tokens.len) return false;
        if (!this.isAtLineStart(idx)) return false;

        switch (tokens[idx].type) {
            .asterisk, .plus, .dash => {
                if (tokens.len < idx + 1 and tokens[idx + 1].type == .space) return true;
                return false;
            },
            .number => {
                if (tokens.len < idx + 2 and
                    tokens[idx + 1].type == .dot and tokens[idx + 2].type == .space) return true;
                return false;
            },
            else => return false,
        }
    }

    fn isAtLineStart(this: *This, idx: usize) bool {
        const tokens = this.tokens.items;
        idx -= 1;
        while (idx >= 0) : (idx -= 1) {
            if (tokens[idx].type == .newline) return true;
            if (tokens[idx].type != .tab) return false;
        }
        return true;
    }

    fn getEmphasis(this: *This, start_index: usize, symbol: LexerTokenType) ?struct { type: Tag, end: usize } {
        const tokens = this.tokens.items;
        var count: usize = 0;
        var i: usize = start_index;
        if (this.getNumberOfBackslashes(i) & 1 == 1) return null;
        while (i < tokens.len and tokens[i].type == symbol) : (i += 1) {
            count += 1;
            if (count == 2) break;
        }
        if (count == 0) return null;
        const emphasis_type = if (count == 2) .bold else .italics;
        var j: usize = i;
        var seen: usize = 0;
        while (j < tokens.len and tokens[j].type != .newline) : (j += 1) {
            if (tokens[j].type == symbol) {
                if (this.getNumberOfBackslashes(j) & 1 == 1) {
                    seen = 0;
                    continue;
                }
                seen += 1;
                if (seen == count) return .{ .type = emphasis_type, .end = j - count + 1 };
            } else {
                seen = 0;
            }
        }
        return null;
    }

    fn getCodeType(this: *This, start_index: usize) ?struct { type: Tag, end: usize } {
        if (this.in_code) return null;
        const tokens = this.tokens.items;
        var count: usize = 0;
        var i: usize = start_index;
        if (this.getNumberOfBackslashes(i) & 1 == 1) return null;
        while (i < tokens.len and tokens[i].type == .back_tick) : (i += 1) {
            count += 1;
        }

        if (count == 3 and this.isAtLineStart(start_index)) {
            var j: usize = i;
            var seen: usize = 0;
            var line = this.line;
            var start_of_line = false;
            while (j < tokens.len) : (j += 1) {
                if (tokens[j].type == .newline) line += 1;
                if (tokens[j].type == .back_tick) {
                    if (this.getNumberOfBackslashes(j) & 1 == 1) {
                        seen = 0;
                        start_of_line = false;
                        continue;
                    }
                    if (seen == 0 and this.isAtLineStart(j)) {
                        start_of_line = true;
                    }
                    if (start_of_line) {
                        seen += 1;
                    } else {
                        seen = 0;
                    }
                    if (seen == count) return .{ .type = .code_block, .end = j - count + 1 };
                } else {
                    seen = 0;
                    start_of_line = false;
                }
            }
            return null;
        }
        var j: usize = i;
        var seen: usize = 0;
        while (j < tokens.len and tokens[j].type != .newline) : (j += 1) {
            if (tokens[j].type == .back_tick) {
                if (this.getNumberOfBackslashes(j) & 1 == 1) {
                    seen = 0;
                    continue;
                }
                seen += 1;
                if (seen == count) return .{ .type = .inline_code, .end = j - count + 1 };
            } else {
                seen = 0;
            }
        }
        return null;
    }

    fn getNumberOfBackslashes(this: *This, start_index: usize) usize {
        var index: usize = start_index - 1;
        var num_backslashes = 0;
        while (index >= 0 and this.tokens.items[index].type == .back_slash) : (index -= 1) {
            num_backslashes += 1;
        }
    }

    fn isHeader(this: *This, start_index: usize) bool {
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

    fn getHeaderLevel(this: *This, start_index: usize) usize {
        var index: usize = start_index;
        var num_hashes: usize = 0;
        while (index < this.tokens.items.len and this.tokens.items[index].type == .hashtag) : (index += 1) {
            num_hashes += 1;
        }
        return num_hashes;
    }

    fn countLines(this: *This) usize {
        var lines: usize = 1;
        for (this.tokens.items) |token| {
            if (token.type == .newline) lines += 1;
        }

        return lines;
    }

    fn computeLineIndents(this: *This) !void {
        var current_indent: f32 = 0;
        var at_line_start: bool = true;

        for (this.tokens.items) |token| {
            if (at_line_start) {
                switch (token.type) {
                    .tab => current_indent += 1.0,
                    //.space => current_indent += 0.5, //might impliment later, just to lazy
                    else => {
                        try this.line_indents.append(@as(usize, @intFromFloat(@floor(current_indent))));
                        current_indent = 0;
                        at_line_start = false;
                    },
                }
            }

            if (token.type == .newline) {
                at_line_start = true;
                current_indent = 0;
            }
        }
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
