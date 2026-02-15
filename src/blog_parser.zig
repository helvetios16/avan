const std = @import("std");
const Book = @import("book_parser.zig").Book;

pub const Blog = struct {
    id: []const u8 = "unknown",
    title: []const u8 = "Untitled Blog",
    webUrl: ?[]const u8 = null,
    description: ?[]const u8 = null,
    imageUrl: ?[]const u8 = null,
    content: ?[]const u8 = null,
    mentionedBooks: []BookWithSection = &.{},
};

pub const BookWithSection = struct {
    book: Book,
    section: ?[]const u8 = null,
};

fn extractAttribute(html: []const u8, attr: []const u8) ?[]const u8 {
    var buf: [128]u8 = undefined;

    // Try double quotes: attr="value"
    const double_pattern = std.fmt.bufPrint(&buf, "{s}=\"", .{attr}) catch return null;
    if (std.mem.indexOf(u8, html, double_pattern)) |start_idx| {
        const content_start = start_idx + double_pattern.len;
        const end_idx = std.mem.indexOf(u8, html[content_start..], "\"") orelse return null;
        return html[content_start .. content_start + end_idx];
    }

    // Try single quotes: attr='value'
    const single_pattern = std.fmt.bufPrint(&buf, "{s}='", .{attr}) catch return null;
    if (std.mem.indexOf(u8, html, single_pattern)) |start_idx| {
        const content_start = start_idx + single_pattern.len;
        const end_idx = std.mem.indexOf(u8, html[content_start..], "'") orelse return null;
        return html[content_start .. content_start + end_idx];
    }

    return null;
}

fn extractMetaContent(html: []const u8, property: []const u8) ?[]const u8 {
    var cursor: usize = 0;
    while (std.mem.indexOf(u8, html[cursor..], "<meta")) |idx| {
        const start = cursor + idx;
        const tag_end_idx = std.mem.indexOf(u8, html[start..], ">") orelse {
            cursor = start + 5;
            continue;
        };
        const tag = html[start .. start + tag_end_idx + 1];
        cursor = start + tag_end_idx + 1;

        const has_prop = std.mem.indexOf(u8, tag, property) != null;
        const alt_property = if (std.mem.startsWith(u8, property, "og:")) property[3..] else property;
        const has_name = std.mem.indexOf(u8, tag, alt_property) != null;

        if (has_prop or has_name) {
            if (extractAttribute(tag, "content")) |content| {
                return content;
            }
        }
    }
    return null;
}

fn extractBlogId(url: ?[]const u8) []const u8 {
    if (url) |u| {
        const pattern = "/blog/show/";
        if (std.mem.indexOf(u8, u, pattern)) |idx| {
            const id_start = u[idx + pattern.len ..];
            const id_end = std.mem.indexOfAny(u8, id_start, "?#") orelse id_start.len;
            if (id_end > 0) {
                return id_start[0..id_end];
            }
        }
    }
    return "unknown";
}

fn decodeHtmlEntities(allocator: std.mem.Allocator, html: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < html.len) {
        if (html[i] == '&') {
            if (std.mem.indexOf(u8, html[i..], ";")) |end_rel| {
                const entity = html[i .. i + end_rel + 1];
                if (std.mem.eql(u8, entity, "&#39;") or std.mem.eql(u8, entity, "&apos;")) {
                    try result.append('\'');
                    i += end_rel + 1;
                    continue;
                } else if (std.mem.eql(u8, entity, "&quot;")) {
                    try result.append('"');
                    i += end_rel + 1;
                    continue;
                } else if (std.mem.eql(u8, entity, "&amp;")) {
                    try result.append('&');
                    i += end_rel + 1;
                    continue;
                } else if (std.mem.eql(u8, entity, "&lt;")) {
                    try result.append('<');
                    i += end_rel + 1;
                    continue;
                } else if (std.mem.eql(u8, entity, "&gt;")) {
                    try result.append('>');
                    i += end_rel + 1;
                    continue;
                } else if (std.mem.eql(u8, entity, "&nbsp;")) {
                    try result.append(' ');
                    i += end_rel + 1;
                    continue;
                }
            }
        }
        try result.append(html[i]);
        i += 1;
    }
    return try result.toOwnedSlice();
}

pub fn parseBlogHtml(html: []const u8, url: ?[]const u8, allocator: std.mem.Allocator) !?Blog {
    const title_raw = extractMetaContent(html, "og:title") orelse "Untitled Blog";
    const title_decoded = try decodeHtmlEntities(allocator, std.mem.trim(u8, title_raw, " \n\r\t"));
    errdefer allocator.free(title_decoded);

    const description_raw = extractMetaContent(html, "og:description");
    const description = if (description_raw) |d| try decodeHtmlEntities(allocator, d) else null;
    errdefer if (description) |d| allocator.free(d);

    const imageUrl_raw = extractMetaContent(html, "og:image");
    const imageUrl = if (imageUrl_raw) |img| try allocator.dupe(u8, img) else null;
    errdefer if (imageUrl) |img| allocator.free(img);

    const webUrl_raw = url orelse extractMetaContent(html, "og:url");
    const webUrl = if (webUrl_raw) |u| try allocator.dupe(u8, u) else null;
    errdefer if (webUrl) |u| allocator.free(u);

    const blog_id_raw = extractBlogId(webUrl_raw);
    const blog_id = try allocator.dupe(u8, blog_id_raw);
    errdefer allocator.free(blog_id);

    var books = std.ArrayList(BookWithSection).init(allocator);
    errdefer {
        for (books.items) |bws| {
            allocator.free(bws.book.title);
            if (bws.book.webUrl) |wu| allocator.free(wu);
        }
        books.deinit();
    }

    var unique_ids = std.StringHashMap(void).init(allocator);
    defer unique_ids.deinit();

    const tooltip_pattern = "js-tooltipTrigger";
    const tooltip_pattern_len = tooltip_pattern.len;
    var tooltip_start: usize = 0;
    while (std.mem.indexOf(u8, html[tooltip_start..], tooltip_pattern)) |idx| {
        const full_start = tooltip_start + idx;

        const search_start = if (full_start > 5000) full_start - 5000 else 0;

        const target_patterns = &[_][]const u8{
            "<div class='js-tooltipTrigger",
            "<div class=\"js-tooltipTrigger",
        };

        var div_start: ?usize = null;

        for (target_patterns) |pat| {
            const search_in = html[search_start .. full_start + 50];
            if (std.mem.indexOf(u8, search_in, pat)) |pos| {
                div_start = search_start + pos;
                break;
            }
        }

        if (div_start == null) {
            for (target_patterns) |pat| {
                const search_in = html[search_start..full_start];
                if (std.mem.lastIndexOf(u8, search_in, pat)) |pos| {
                    div_start = search_start + pos;
                    break;
                }
            }
        }

        if (div_start == null) {
            tooltip_start = full_start + tooltip_pattern_len;
            continue;
        }

        const class_search = html[div_start.? .. full_start + 50];
        if (!std.mem.containsAtLeast(u8, class_search, 1, "book") and !std.mem.containsAtLeast(u8, class_search, 1, "js-tooltipTrigger")) {
            tooltip_start = full_start + tooltip_pattern_len;
            continue;
        }

        var href: ?[]const u8 = null;

        if (std.mem.indexOf(u8, html[full_start..], "<a href=\"")) |a_idx| {
            const href_start = full_start + a_idx + "<a href=\"".len;
            const href_end = std.mem.indexOf(u8, html[href_start..], "\"") orelse {
                tooltip_start = full_start + tooltip_pattern_len;
                continue;
            };
            href = html[href_start .. href_start + href_end];
        } else if (std.mem.indexOf(u8, html[full_start..], "<a href='")) |a_idx| {
            const href_start = full_start + a_idx + "<a href='".len;
            const href_end = std.mem.indexOf(u8, html[href_start..], "'") orelse {
                tooltip_start = full_start + tooltip_pattern_len;
                continue;
            };
            href = html[href_start .. href_start + href_end];
        } else {
            tooltip_start = full_start + tooltip_pattern_len;
            continue;
        }

        const href_val = href.?;

        if (!std.mem.containsAtLeast(u8, href_val, 1, "/book/show/")) {
            tooltip_start = full_start + tooltip_pattern_len;
            continue;
        }

        const id_match = std.mem.indexOf(u8, href_val, "/book/show/");
        if (id_match) |m| {
            const id_start = href_val[m + "/book/show/".len ..];
            const id_end = std.mem.indexOfAny(u8, id_start, "?#") orelse id_start.len;
            const full_id = id_start[0..id_end];

            var numeric_id = full_id;
            if (std.mem.indexOf(u8, full_id, "-")) |dash| {
                numeric_id = full_id[0..dash];
            }

            if (unique_ids.contains(numeric_id)) {
                tooltip_start = full_start + tooltip_pattern_len;
                continue;
            }
            try unique_ids.put(numeric_id, {});

            var book_title_raw: []const u8 = "";
            if (std.mem.indexOf(u8, html[full_start..], "<img alt=\"")) |img_alt_start| {
                const val_start = full_start + img_alt_start + "<img alt=\"".len;
                const val_end = std.mem.indexOf(u8, html[val_start..], "\"") orelse {
                    tooltip_start = full_start + tooltip_pattern_len;
                    continue;
                };
                book_title_raw = html[val_start .. val_start + val_end];
            }
            const book_title = try decodeHtmlEntities(allocator, book_title_raw);
            errdefer allocator.free(book_title);

            const final_url = if (std.mem.startsWith(u8, href_val, "http")) try allocator.dupe(u8, href_val) else blk: {
                const prefix = "https://www.goodreads.com";
                const result = try allocator.alloc(u8, prefix.len + href_val.len);
                @memcpy(result[0..prefix.len], prefix);
                @memcpy(result[prefix.len..], href_val);
                break :blk result;
            };
            errdefer allocator.free(final_url);

            try books.append(.{
                .book = .{
                    .id = 0,
                    .title = book_title,
                    .author = null,
                    .webUrl = final_url,
                },
                .section = null,
            });
        }

        tooltip_start = full_start + tooltip_pattern_len;
    }

    return Blog{
        .id = blog_id,
        .title = title_decoded,
        .webUrl = webUrl,
        .description = description,
        .imageUrl = imageUrl,
        .content = null,
        .mentionedBooks = try books.toOwnedSlice(),
    };
}

pub fn freeBlog(blog: *Blog, allocator: std.mem.Allocator) void {
    allocator.free(blog.id);
    allocator.free(blog.title);
    if (blog.webUrl) |u| allocator.free(u);
    if (blog.description) |d| allocator.free(d);
    if (blog.imageUrl) |img| allocator.free(img);
    if (blog.content) |c| allocator.free(c);

    for (blog.mentionedBooks) |bws| {
        allocator.free(bws.book.title);
        if (bws.book.author) |a| allocator.free(a);
        if (bws.book.webUrl) |wu| allocator.free(wu);
    }
    allocator.free(blog.mentionedBooks);
}
