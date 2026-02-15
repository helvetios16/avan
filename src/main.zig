const std = @import("std");
const http_client = @import("http_client.zig");
const file_client = @import("file_client.zig");
const json_parser = @import("json_parser.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var client = try http_client.HttpClient.init(allocator);
    defer client.deinit();

    const html = try client.fetch("https://goodreads.com/book/show/1");
    defer allocator.free(html);

    std.debug.print("Fetched {} bytes\n", .{html.len});

    var file = file_client.FileClient.init(allocator);

    if (json_parser.JsonParser.extractNextData(html)) |json| {
        try file.save("output.json", json);
        std.debug.print("Saved JSON to output.json ({} bytes)\n", .{json.len});
    } else {
        std.debug.print("No __NEXT_DATA__ found\n", .{});
    }

    try file.save("output.html", html);
    std.debug.print("Saved to output.html\n", .{});
}
