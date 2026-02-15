const std = @import("std");
const edition_parser = @import("edition_parser.zig");

test "extract filter options (sort, format, language) from editions page" {
    const allocator = std.testing.allocator;
    var client = try @import("http_client.zig").HttpClient.init(allocator);
    defer client.deinit();

    const html = try client.fetch("https://www.goodreads.com/work/editions/53043399");
    defer allocator.free(html);

    const filters = try edition_parser.parseEditionsFilters(html, allocator);
    defer edition_parser.freeEditionsFilters(filters, allocator);

    try std.testing.expectEqual(@as(usize, 6), filters.sort.len);
    try std.testing.expectEqual(@as(usize, 18), filters.format.len);
    try std.testing.expectEqual(@as(usize, 38), filters.language.len);
}

test "parse editions list with Kindle and Spanish filters (expecting 3)" {
    const allocator = std.testing.allocator;
    var client = try @import("http_client.zig").HttpClient.init(allocator);
    defer client.deinit();

    const uri = "https://www.goodreads.com/work/editions/53043399?utf8=%E2%9C%93&sort=num_ratings&filter_by_format=Kindle+Edition&filter_by_language=spa";
    const html = try client.fetch(uri);
    defer allocator.free(html);

    const editions = try edition_parser.parseEditionsList(html, allocator);
    defer edition_parser.freeEditionsList(editions, allocator);

    const pagination = edition_parser.extractPaginationInfo(html);

    try std.testing.expectEqual(@as(u32, 1), pagination.totalPages);
    try std.testing.expectEqual(@as(usize, 3), editions.len);
}

test "parse editions list with ebook and Spanish filters (expecting 1)" {
    const allocator = std.testing.allocator;
    var client = try @import("http_client.zig").HttpClient.init(allocator);
    defer client.deinit();

    const uri = "https://www.goodreads.com/work/editions/53043399?utf8=%E2%9C%93&sort=num_ratings&filter_by_format=ebook&filter_by_language=spa";
    const html = try client.fetch(uri);
    defer allocator.free(html);

    const editions = try edition_parser.parseEditionsList(html, allocator);
    defer edition_parser.freeEditionsList(editions, allocator);

    const pagination = edition_parser.extractPaginationInfo(html);

    try std.testing.expectEqual(@as(u32, 1), pagination.totalPages);
    try std.testing.expectEqual(@as(usize, 1), editions.len);
}

test "parse editions across multiple pages using pagination (expecting 12)" {
    const allocator = std.testing.allocator;
    var client = try @import("http_client.zig").HttpClient.init(allocator);
    defer client.deinit();

    const baseUrl = "https://www.goodreads.com/work/editions/53043399-circe?filter_by_format=ebook&filter_by_language=eng&sort=num_ratings&utf8=%E2%9C%93";
    const html = try client.fetch(baseUrl);
    defer allocator.free(html);

    var all_editions = std.ArrayList(edition_parser.Edition).init(allocator);
    defer {
        for (all_editions.items) |e| {
            allocator.free(e.title);
            allocator.free(e.link);
            if (e.coverImage) |c| allocator.free(c);
        }
        all_editions.deinit();
    }

    const first_page = try edition_parser.parseEditionsList(html, allocator);
    try all_editions.appendSlice(first_page);
    allocator.free(first_page);

    const pagination = edition_parser.extractPaginationInfo(html);
    try std.testing.expectEqual(@as(u32, 2), pagination.totalPages);

    if (pagination.totalPages > 1) {
        var i: u32 = 2;
        while (i <= pagination.totalPages) : (i += 1) {
            const pageUrl = try std.fmt.allocPrint(allocator, "{s}&page={d}", .{ baseUrl, i });
            defer allocator.free(pageUrl);

            const pageHtml = try client.fetch(pageUrl);
            defer allocator.free(pageHtml);

            const page_editions = try edition_parser.parseEditionsList(pageHtml, allocator);
            try all_editions.appendSlice(page_editions);
            allocator.free(page_editions);

            std.time.sleep(100 * std.time.ns_per_ms);
        }
    }

    try std.testing.expectEqual(@as(usize, 12), all_editions.items.len);
}
