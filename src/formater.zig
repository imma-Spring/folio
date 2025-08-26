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
                    format_node = .{ .text = text };
                },
                .hashtag => {
                    if (this.isHeader(i)) {
                        const header_level = this.getHeaderLevel(i);
                        format_node = .{ .header_start = header_level };
                        i += header_level - 1;
                    } else {
                        const text: []const u8 = parseText(token, allocator);
                        format_node = .{ .text = text };
                    }
                },
                .bask_slash => {
                    if ((this.getNumberOfBackslashes(i) & 1) == 1) {
                        const text: []const u8 = parseText(token, allocator);
                        format_node = .{ .text = text };
                    }
                },
                .underscore => {
                    if (takeByIndex(this.tag, i)) |entry| {
                        switch (entry.type) {
                            .bold => {
                                i += 1;
                            },
                            else => {},
                        }
                    } else {
                        const empasis_type = this.getEmphasis(i, .underscore);
                        if (empasis_type) |tag| {
                            this.tag.append(tag);
                            format_node = .{ .bold_start = {} };
                        } else {
                            const text: []const u8 = parseText(token, allocator);
                            format_node = .{ .text = text };
                        }
                    }
                },
                .asterisk => {
                    if (this.isListMarker(i, .unordered)) {
                        const indent_level = this.getIndentation(i);
                        const end_index = this.findListItemEnd(i, indent_level);

                        if (!this.hasIndent() or indent_level > this.peekIndent()) {
                            this.pushIndent(allocator, indent_level);
                            const list_end_index = this.findListEnd(i, indent_level);
                            this.tag.append(.{ .type = .unordered, .idx = list_end_index });
                            format_tokens.append(.{ .unordered_list_start = {} });
                        }

                        this.tag.append(.{ .type = .unordered_item, .idx = end_index });
                        format_node = .{ .unordered_list_item_start = {} };
                        i += 1;
                    } else if (takeByIndex(this.tag, i)) |entry| {
                        switch (entry.type) {
                            .bold => {
                                i += 1;
                            },
                            else => {},
                        }
                    } else {
                        const empasis_type = this.getEmphasis(i, .asterisk);
                        if (empasis_type) |tag| {
                            this.tag.append(tag);
                            format_node = .{ .bold_start = {} };
                        } else {
                            const text: []const u8 = parseText(token, allocator);
                            format_node = .{ .text = text };
                        }
                    }
                },
                .plus, .dash => {
                    if (this.isListMarker(i, .unordered)) {
                        const indent_level = this.getIndentation(i);
                        const end_index = this.findListItemEnd(i, indent_level);

                        if (!this.hasIndent() or indent_level > this.peekIndent()) {
                            this.pushIndent(allocator, indent_level);
                            const list_end_index = this.findListEnd(i, indent_level);
                            this.tag.append(.{ .type = .unordered, .idx = list_end_index });
                            format_tokens.append(.{ .unordered_list_start = {} });
                        }

                        this.tag.append(.{ .type = .unordered_item, .idx = end_index });
                        format_node = .{ .unordered_list_item_start = {} };
                        i += 1;
                    } else {
                        const text: []const u8 = parseText(token, allocator);
                        format_node = .{ .text = text };
                    }
                },
                .number => {
                    if (this.isListMarker(i, .ordered)) {
                        const indent_level = this.getIndentation(i);
                        const end_index = this.findListItemEnd(i, indent_level);

                        if (!this.hasIndent() or indent_level > this.peekIndent()) {
                            this.pushIndent(allocator, indent_level);
                            const list_end_index = this.findListEnd(i, indent_level);
                            this.tag.append(.{ .type = .ordered, .idx = list_end_index });
                            format_tokens.append(.{ .unordered_list_start = {} });
                        }

                        this.tag.append(.{ .type = .ordered_item, .idx = end_index });
                        format_node = .{ .unordered_list_item_start = {} };
                        i += 2;
                    } else {
                        const text: []const u8 = parseText(token, allocator);
                        format_node = .{ .text = text };
                    }
                },
                else => {},
            }

            format_tokens.append(format_node);
        }

        return format_tokens;
    }

    fn getIndentation(this: *This, index: usize) usize {
        var indent: usize = 0;
        var j: usize = index;
        while (j > 0 and this.tokens.items[j - 1].type == .tab) : (j -= 1) {
            indent += 1;
        }
        return indent;
    }

    fn isListMarker(this: *This, index: usize, kind: ListType) bool {
        var j: usize = index;
        const tokens = this.tokens.items;
        while (j > 0 and tokens[j - 1].type == .tab) {
            j -= 1;
        }

        const at_line_start = (j == 0) or (tokens[j - 1].type == .newline);

        if (!at_line_start) return false;

        switch (kind) {
            .unordered => {
                const has_space_after = (index + 1 < tokens.len and tokens[index + 1].type == .space);
                return has_space_after;
            },
            .ordered => {
                return (index + 2 < tokens.len and tokens[index + 1].type == .period and tokens[index + 2].type == .space);
            },
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

    fn getNumberOfBackslashes(this: *This, start_index: usize) usize {
        var index: usize = start_index - 1;
        var num_backslashes = 0;
        while (index >= 0 and this.tokens.items[index].type == .back_slash) : (index -= 1) {
            num_backslashes += 1;
        }
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
                if (seen == count) return .{ .type = emphasis_type, .end = j };
            } else {
                seen = 0;
            }
        }

        return null;
    }

    fn findListItemEnd(this: *This, start_index: usize, indent: usize) usize {
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

            if (depth == indent and (this.isListMarker(k, .ordered) or this.isListMarker(k, .unordered))) {
                return k - 1;
            }

            j = k + 1;
        }

        return tokens.len - 1;
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

    fn pushIndent(this: *TokenFormater, allocator: std.mem.Allocator, indent: usize) void {
        const node = allocator.create(IndentNode) catch unreachable;
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
