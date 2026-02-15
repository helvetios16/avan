const std = @import("std");
const book_parser = @import("book_parser.zig");

test "extract full book metadata from Goodreads Apollo state" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try @import("http_client.zig").HttpClient.init(allocator);
    defer client.deinit();

    const html = try client.fetch("https://www.goodreads.com/book/show/58613345-harry-potter-and-the-half-blood-prince");
    defer allocator.free(html);

    const next_data = @import("json_parser.zig").JsonParser.extractNextData(html);
    try std.testing.expect(next_data != null);

    const json_str = next_data.?;

    const output_file = try std.fs.cwd().createFile("output.test.json", .{});
    defer output_file.close();
    try output_file.writeAll(json_str);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const book = try book_parser.parseBookData(parsed.value, allocator);
    try std.testing.expect(book != null);

    const b = book.?;

    try std.testing.expectEqual(@as(u64, 58613345), b.id);
    try std.testing.expectEqual(@as(?u32, 41335427), b.legacyId);
    try std.testing.expectEqual(@as(?f64, 4.58), b.averageRating);
    try std.testing.expectEqualStrings("Harry Potter and the Half-Blood Prince", b.title);
    try std.testing.expectEqualStrings("Harry Potter and the Half-Blood Prince (Harry Potter, #6)", b.titleComplete);
    try std.testing.expectEqualStrings("J.K. Rowling", b.author.?);
    try std.testing.expect(b.description != null);
    const expected_desc = "The war against Voldemort is not going well: even Muggle governments are noticing. Ron scans the obituary pages of The Daily Prophet looking for familiar names. Dumbledore is absent from Hogwarts for long stretches of time, and the Order of the Phoenix has already suffered losses. And yet...\n\nAs in all wars, life goes on. Sixth-year students learn to Apparate, and lose a few eyebrows in the process. The Weasley twins expand their business. Teenagers flirt and fight and fall in love. Classes are never straightforward, though Harry receives some extraordinary help from the mysterious Half-Blood Prince.\n\nSo it's the home front that takes center stage in the multilayered sixth installment of the story of Harry Potter. Harry struggles to uncover the identity of the Half-Blood Prince, the past owner of a potions textbook he now possesses that is filled with ingenious, potentially deadly, spells. But Harry's life is suddenly changed forever when someone close to him is heinously murdered right before his eyes.\n\nWith Dumbledore's guidance, he seeks out the full, complex story of the boy who became Lord Voldemort, and thereby attempts to find what may be his only vulnerability.";
    try std.testing.expectEqualStrings(expected_desc, b.description.?);
    try std.testing.expectEqual(@as(?u32, 672), b.pageCount);
    try std.testing.expectEqualStrings("English", b.language.?);
    try std.testing.expectEqualStrings("Hardcover", b.format.?);
    try std.testing.expectEqualStrings("https://m.media-amazon.com/images/S/compressed.photo.goodreads.com/books/1627043894i/58613345.jpg", b.coverImage.?);
    try std.testing.expectEqualStrings("https://www.goodreads.com/book/show/58613345-harry-potter-and-the-half-blood-prince", b.webUrl.?);

    if (b.description) |desc| {
        allocator.free(desc);
    }
}
