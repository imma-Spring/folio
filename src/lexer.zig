const std = @import("std");

pub const TokenType = enum {
    text,
    hashtag,
    asterisk,
    underscore,
    open_angle,
    close_angle,
    tab,
    back_tick,
    open_bracket,
    close_bracket,
    open_parenthesis,
    close_parenthesis,
    bang,
    escape,
    number,
    period,
    quote,
    dash,
    plus,
    space,
    eof,
};

pub const Token = struct {
    type: TokenType,
    start: *const u8,
    end: *const u8,

    pub fn newToken(token_type: TokenType, start_pointer: *const u8, len: usize) Token {
        return .{
            .type = token_type,
            .start = start_pointer,
            .end = start_pointer + len,
        };
    }
};

pub const Tokenizer = struct {
    current_pos: *const u8,

    pub fn init(string: [:0]const u8) Tokenizer {
        if (string.len == 0) unreachable;
        const start = &string[0];
        return .{ .current_pos = start };
    }

    pub fn nextToken(this: *Tokenizer) Token {
        if (this.current_pos.* == 0) {
            return .{
                .type = .eof,
                .start = this.current_pos,
                .end = this.current_pos,
            };
        }

        return switch (this.current_pos.*) {
            '*' => getNormalToken(&this.current_pos, .asterisk),
            '#' => getNormalToken(&this.current_pos, .hashtag),
            '_' => getNormalToken(&this.current_pos, .underscore),
            '<' => getNormalToken(&this.current_pos, .open_angle),
            '>' => getNormalToken(&this.current_pos, .close_angle),
            '\t' => getNormalToken(&this.current_pos, .tab),
            '-' => getNormalToken(&this.current_pos, .dash),
            '+' => getNormalToken(&this.current_pos, .plus),
            '`' => getNormalToken(&this.current_pos, .back_tick),
            '[' => getNormalToken(&this.current_pos, .open_bracket),
            ']' => getNormalToken(&this.current_pos, .close_bracket),
            '(' => getNormalToken(&this.current_pos, .open_parenthesis),
            ')' => getNormalToken(&this.current_pos, .close_parenthesis),
            '!' => getNormalToken(&this.current_pos, .bang),
            '\n' => getNormalToken(&this.current_pos, .escape),
            '.' => getNormalToken(&this.current_pos, .period),
            '"' => getNormalToken(&this.current_pos, .quote),
            ' ' => getNormalToken(&this.current_pos, .space),
            '0'...'9' => getNumberToken(&this.current_pos),
            'a'...'z', 'A'...'Z' => getTextToken(&this.current_pos),
            else => unreachable,
        };
    }
};

fn getNormalToken(start: **const u8, token_type: TokenType) Token {
    const token = Token.newToken(token_type, start.*, 1);
    start.* += 1;
    return token;
}

fn getNumberToken(current_pos: **const u8) Token {
    const start = current_pos.*;
    var len: usize = 0;
    while (std.ascii.isDigit(current_pos.*.*) and current_pos.*.* != 0) : (len += 1) {
        current_pos.* += 1;
    }
    return Token.newToken(.number, start.*, len);
}

fn getTextToken(current_pos: **const u8) Token {
    const start = current_pos.*;
    var len: usize = 0;
    while (std.ascii.isAlphabetic(current_pos.*.*) and current_pos.*.* != 0) : (len += 1) {
        current_pos.* += 1;
    }
    return Token.newToken(.text, start.*, len);
}
