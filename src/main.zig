const std = @import("std");
const http_client = @import("http_client.zig");
const file_client = @import("file_client.zig");
const json_parser = @import("json_parser.zig");
const blog_parser = @import("blog_parser.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var client = try http_client.HttpClient.init(allocator);
    defer client.deinit();

    const uri = "https://www.goodreads.com/blog/show/3049-swoony-stories-144-romance-recommendations-for-valentine-s-reading";
    const html = try client.fetch(uri);
    defer allocator.free(html);

    std.debug.print("Fetched {} bytes\n", .{html.len});

    var file = file_client.FileClient.init(allocator);

    try file.save("output.html", html);
    std.debug.print("Saved to output.html\n", .{});

    var blog = try blog_parser.parseBlogHtml(html, uri, allocator);
    if (blog) |*b| {
        std.debug.print("Title: {s}\n", .{b.title});
        std.debug.print("Books found: {d}\n\n", .{b.mentionedBooks.len});
        
        printBlogBooks(b);

        blog_parser.freeBlog(b, allocator);
    }
}

fn printBlogBooks(blog: *const blog_parser.Blog) void {
    std.debug.print("--- Mentioned Books ---\n", .{});
    for (blog.mentionedBooks, 0..) |bws, i| {
        const book = bws.book;
        std.debug.print("[{d}] {s}\n", .{ i + 1, book.title });
        if (book.webUrl) |url| {
            std.debug.print("    URL: {s}\n", .{url});
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("-----------------------\n", .{});
}
