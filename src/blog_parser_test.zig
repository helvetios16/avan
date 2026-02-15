const std = @import("std");
const blog_parser = @import("blog_parser.zig");

test "extract metadata and mentioned books from a specific blog post" {
    const allocator = std.testing.allocator;
    var client = try @import("http_client.zig").HttpClient.init(allocator);
    defer client.deinit();

    const url = "https://www.goodreads.com/blog/show/3059-10-new-books-recommended-by-readers-this-week";
    const html = try client.fetch(url);
    defer allocator.free(html);

    var blog = (try blog_parser.parseBlogHtml(html, url, allocator)).?;
    defer blog_parser.freeBlog(&blog, allocator);

    try std.testing.expectEqualStrings("3059-10-new-books-recommended-by-readers-this-week", blog.id);
    try std.testing.expectEqualStrings("10 New Books Recommended by Readers This Week", blog.title);
    try std.testing.expect(blog.description != null);
    try std.testing.expect(std.mem.startsWith(u8, blog.description.?, "Need another excuse"));
    try std.testing.expectEqualStrings("https://images.gr-assets.com/blogs/1769023660p8/3059.jpg", blog.imageUrl.?);
    try std.testing.expectEqualStrings(url, blog.webUrl.?);

    try std.testing.expectEqual(@as(usize, 10), blog.mentionedBooks.len);

    try std.testing.expectEqualStrings("It's Not Her", blog.mentionedBooks[0].book.title);
    try std.testing.expect(std.mem.containsAtLeast(u8, blog.mentionedBooks[0].book.webUrl.?, 1, "230443142-it-s-not-her"));

    try std.testing.expect(std.mem.startsWith(u8, blog.mentionedBooks[9].book.title, "Queen of Faces"));
    try std.testing.expect(std.mem.containsAtLeast(u8, blog.mentionedBooks[9].book.webUrl.?, 1, "228692419-queen-of-faces"));
}

test "extract metadata and mentioned books from a long blog post (144 books)" {
    const allocator = std.testing.allocator;
    var client = try @import("http_client.zig").HttpClient.init(allocator);
    defer client.deinit();

    const url = "https://www.goodreads.com/blog/show/3049-swoony-stories-144-romance-recommendations-for-valentine-s-reading";
    const html = try client.fetch(url);
    defer allocator.free(html);

    var blog = (try blog_parser.parseBlogHtml(html, url, allocator)).?;
    defer blog_parser.freeBlog(&blog, allocator);

    try std.testing.expectEqualStrings("3049-swoony-stories-144-romance-recommendations-for-valentine-s-reading", blog.id);
    try std.testing.expectEqualStrings("Swoony Stories: 144 Romance Recommendations for Valentine's Reading", blog.title);
    try std.testing.expect(blog.description != null);
    try std.testing.expect(std.mem.startsWith(u8, blog.description.?, "Love stories are the best kind of stories."));

    try std.testing.expectEqual(@as(usize, 144), blog.mentionedBooks.len);

    std.debug.print("\n=== Primeros 3 libros ===\n", .{});
    for (blog.mentionedBooks[0..3], 0..) |bws, i| {
        std.debug.print("{d}: {s} - {s}\n", .{ i + 1, bws.book.title, bws.book.webUrl.? });
    }

    std.debug.print("\n=== Ultimos 3 libros ===\n", .{});
    for (blog.mentionedBooks[blog.mentionedBooks.len - 3 ..], 0..) |bws, i| {
        std.debug.print("{d}: {s} - {s}\n", .{ blog.mentionedBooks.len - 2 + i, bws.book.title, bws.book.webUrl.? });
    }

    const expected_first_ids = [_][]const u8{ "220966494-heated-rivalry", "236669889-please-don-t-go", "53050272-ghosting" };
    const expected_last_ids = [_][]const u8{ "216970870-serial-killer-games", "212806630-the-matchmaker", "218461924-alice-chen-s-reality-check" };

    var found_first = [_]bool{false} ** 3;
    var found_last = [_]bool{false} ** 3;

    for (blog.mentionedBooks) |bws| {
        const book_url = bws.book.webUrl.?;
        for (expected_first_ids, 0..) |expected_id, i| {
            if (!found_first[i] and std.mem.containsAtLeast(u8, book_url, 1, expected_id)) {
                found_first[i] = true;
            }
        }
        for (expected_last_ids, 0..) |expected_id, i| {
            if (!found_last[i] and std.mem.containsAtLeast(u8, book_url, 1, expected_id)) {
                found_last[i] = true;
            }
        }
    }

    for (found_first) |found| {
        try std.testing.expect(found);
    }
    for (found_last) |found| {
        try std.testing.expect(found);
    }
}
