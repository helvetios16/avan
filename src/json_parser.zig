const std = @import("std");

pub const JsonParser = struct {
    pub fn extractNextData(html: []const u8) ?[]const u8 {
        const prefix = "<script id=\"__NEXT_DATA__\"";
        const suffix = "</script>";

        const start = std.mem.indexOf(u8, html, prefix) orelse return null;

        const tag_end = std.mem.indexOf(u8, html[start + prefix.len ..], ">") orelse return null;
        const content_start = start + prefix.len + tag_end + 1;

        const end = std.mem.indexOf(u8, html[content_start..], suffix) orelse return null;

        return html[content_start .. content_start + end];
    }
};
