const std = @import("std");
const rl = @import("raylib");

const lexer = @import("lexer.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const screen_width = 800;
    const screen_height = 600;

    rl.initWindow(screen_width, screen_height, "Folio");
    rl.maximizeWindow();

    const file = try getProject();
    const file_contents = try readFile(file, allocator);
    defer allocator.free(file_contents);

    const formated_contents: [:0]u8 = try std.fmt.allocPrintZ(allocator, "{s}", .{file_contents});
    defer allocator.free(formated_contents);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.gray);
        rl.drawText(formated_contents, 10, 10, 10, .white);
    }
}

fn getProject() !std.fs.File {
    const file = try std.fs.cwd().openFile("test.md", .{});
    return file;
}

fn readFile(file: std.fs.File, allocator: std.mem.Allocator) ![]const u8 {
    const file_reader = file.reader();
    const contents = try file_reader.readUntilDelimiterOrEofAlloc(allocator, 0, 47000) orelse "";
    return contents;
}
