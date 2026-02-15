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

fn extractMetaContent(html: []const u8, property: []const u8) ?[]const u8 {
    const prefix = "<meta property=\"";
    const suffix = "\" content=\"";

    const prop_start = std.mem.indexOf(u8, html, prefix) orelse return null;
    const after_prefix = prop_start + prefix.len;

    const prop_end = std.mem.indexOf(u8, html[after_prefix..], "\"") orelse return null;
    const found_prop = html[after_prefix .. after_prefix + prop_end];

    if (!std.mem.eql(u8, found_prop, property)) return null;

    const content_start = after_prefix + prop_end + suffix.len;
    const content_end = std.mem.indexOf(u8, html[content_start..], "\"") orelse return null;

    return html[content_start .. content_start + content_end];
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

pub fn parseBlogHtml(html: []const u8, url: ?[]const u8, allocator: std.mem.Allocator) !?Blog {
    const title_raw = extractMetaContent(html, "og:title") orelse "Untitled Blog";
    const title = try allocator.dupe(u8, std.mem.trim(u8, title_raw, " \n\r\t"));
    errdefer allocator.free(title);

    const description_raw = extractMetaContent(html, "og:description");
    const description = if (description_raw) |d| try allocator.dupe(u8, d) else null;
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
            const book_title = try allocator.dupe(u8, book_title_raw);
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
        .title = title,
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
