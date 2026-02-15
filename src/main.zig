const std = @import("std");
const http_client = @import("http_client.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var client = try http_client.HttpClient.init(allocator);
    defer client.deinit();

    const html = try client.fetch("https://goodreads.com/book/show/1");
    defer allocator.free(html);

    std.debug.print("Fetched {} bytes\n", .{html.len});
}
