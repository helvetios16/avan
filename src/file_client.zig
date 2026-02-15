const std = @import("std");

pub const FileClient = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FileClient {
        return FileClient{ .allocator = allocator };
    }

    pub fn read(self: FileClient, path: []const u8) ![]const u8 {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        return try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
    }

    pub fn save(_: FileClient, path: []const u8, data: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(data);
    }
};
