const std = @import("std");

pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator) !HttpClient {
        return HttpClient{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.client.deinit();
    }

    pub fn fetch(self: *HttpClient, url: []const u8) ![]const u8 {
        const uri = try std.Uri.parse(url);

        var buffer_header: [8192]u8 = undefined;

        var request = try self.client.open(.GET, uri, .{
            .server_header_buffer = &buffer_header,
            .extra_headers = &.{
                .{ .name = "user-agent", .value = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" },
            },
        });
        defer request.deinit();

        try request.send();
        try request.wait();

        var body = std.ArrayList(u8).init(self.allocator);
        errdefer body.deinit();
        try request.reader().readAllArrayList(&body, std.math.maxInt(usize));

        return try body.toOwnedSlice();
    }
};
