const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse("https://goodreads.com/book/show/1");

    var buffer_header: [1024]u8 = undefined;

    var request = try client.open(.GET, uri, .{
        .server_header_buffer = &buffer_header,
        .extra_headers = &.{
            .{ .name = "user-agent", .value = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" },
        },
    });
    defer request.deinit();

    try request.send();
    try request.wait();

    var body = std.ArrayList(u8).init(allocator);
    defer body.deinit();

    try request.reader().readAllArrayList(&body, std.math.maxInt(usize));

    std.debug.print("Status: {}\n", .{request.response.status});
}
