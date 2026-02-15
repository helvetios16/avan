const std = @import("std");

pub const Book = struct {
    id: u64 = 0,
    legacyId: ?u32 = null,
    averageRating: ?f64 = null,
    title: []const u8 = "",
    titleComplete: []const u8 = "",
    author: ?[]const u8 = null,
    description: ?[]const u8 = null,
    pageCount: ?u32 = null,
    language: ?[]const u8 = null,
    format: ?[]const u8 = null,
    coverImage: ?[]const u8 = null,
    webUrl: ?[]const u8 = null,
};

fn isValidNextData(data: std.json.Value) bool {
    if (data != .object) return false;
    const obj = data.object;

    const props_val = obj.get("props") orelse return false;
    if (props_val != .object) return false;
    const props_obj = props_val.object;

    const pageProps_val = props_obj.get("pageProps") orelse return false;
    if (pageProps_val != .object) return false;
    const pageProps_obj = pageProps_val.object;

    const apolloState_val = pageProps_obj.get("apolloState") orelse return false;

    return apolloState_val == .object;
}

fn resolveRef(state: std.json.Value, ref: ?[]const u8) ?std.json.Value {
    const ref_str = ref orelse return null;
    if (state != .object) return null;
    const state_obj = state.object;
    return state_obj.get(ref_str) orelse return null;
}

fn getString(val: std.json.Value) ?[]const u8 {
    return val.string;
}

fn getNumber(val: std.json.Value) ?f64 {
    return val.number;
}

fn getObject(obj: anytype, key: []const u8) ?std.json.Value {
    return obj.get(key);
}

fn parseBookData(jsonData: std.json.Value, allocator: std.mem.Allocator) !?Book {
    if (!isValidNextData(jsonData)) return null;

    if (jsonData != .object) return null;
    const root = jsonData.object;
    const props_obj = getObject(root, "props") orelse return null;
    if (props_obj != .object) return null;
    const pageProps_obj = getObject(props_obj.object, "pageProps") orelse return null;
    if (pageProps_obj != .object) return null;
    const state = getObject(pageProps_obj.object, "apolloState") orelse return null;
    if (state != .object) return null;
    const state_map = state.object;
    const state_val = state;

    var bookData: ?std.json.Value = null;

    var iterator = state_map.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const val = entry.value_ptr.*;
        if (std.mem.startsWith(u8, key, "Book:")) {
            if (val == .object) {
                const obj = val.object;
                const has_title = obj.contains("title");
                const has_titleComplete = obj.contains("titleComplete");
                if (has_title and has_titleComplete) {
                    bookData = val;
                    break;
                }
            }
        }
    }

    if (bookData == null) return null;

    if (bookData.? != .object) return null;
    const data = bookData.?.object;

    var authorRef: ?[]const u8 = null;
    if (data.get("primaryContributorEdge")) |edge| {
        if (edge == .object) {
            const obj = edge.object;
            if (obj.get("node")) |node| {
                if (node == .object) {
                    const nobj = node.object;
                    if (nobj.get("__ref")) |ref| {
                        authorRef = ref.string;
                    }
                }
            }
        }
    }

    const authorData = resolveRef(state_val, authorRef);
    var authorName: ?[]const u8 = null;
    if (authorData) |a| {
        if (a == .object) {
            const obj = a.object;
            if (obj.get("name")) |name| {
                if (name == .string) authorName = name.string;
            }
        }
    }

    var workRef: ?[]const u8 = null;
    if (data.get("work")) |work| {
        if (work == .object) {
            const obj = work.object;
            if (obj.get("__ref")) |ref| {
                if (ref == .string) workRef = ref.string;
            }
        }
    }

    const workData = resolveRef(state_val, workRef);
    var legacyId: ?u32 = null;
    var avgRating: ?f64 = null;
    if (workData) |w| {
        if (w == .object) {
            const obj = w.object;
            if (obj.get("legacyId")) |id| {
                legacyId = switch (id) {
                    .integer => |i| @intCast(i),
                    .float => |f| @intFromFloat(f),
                    .string => |s| std.fmt.parseInt(u32, s, 10) catch null,
                    else => null,
                };
            }
            if (obj.get("stats")) |stats| {
                if (stats == .object) {
                    const sobj = stats.object;
                    if (sobj.get("averageRating")) |r| {
                        avgRating = switch (r) {
                            .float => |f| f,
                            .integer => |i| @floatFromInt(i),
                            else => null,
                        };
                    }
                }
            }
        }
    }

    var description: ?[]const u8 = null;
    if (data.get("description")) |desc| {
        if (desc == .string) {
            const raw = desc.string;
            var cleaned = std.ArrayList(u8).init(allocator);
            errdefer cleaned.deinit();

            var i: usize = 0;
            while (i < raw.len) {
                if (i + 3 < raw.len and raw[i] == '<' and raw[i + 1] == 'b' and raw[i + 2] == 'r') {
                    if (raw[i + 3] == ' ' or raw[i + 3] == '/' or raw[i + 3] == '>') {
                        try cleaned.append('\n');
                        i += 3;
                        while (i < raw.len and raw[i] != '>') i += 1;
                        if (i < raw.len) i += 1;
                        continue;
                    }
                }
                if (raw[i] == '<') {
                    while (i < raw.len and raw[i] != '>') i += 1;
                    if (i < raw.len) i += 1;
                } else {
                    try cleaned.append(raw[i]);
                    i += 1;
                }
            }

            description = try cleaned.toOwnedSlice();
        }
    }

    var pageCount: ?u32 = null;
    var language: ?[]const u8 = null;
    var format: ?[]const u8 = null;

    if (data.get("details")) |details| {
        if (details == .object) {
            const obj = details.object;
            if (obj.get("numPages")) |p| {
                pageCount = switch (p) {
                    .float => |f| @intFromFloat(f),
                    .integer => |i| @intCast(i),
                    else => null,
                };
            }
            if (obj.get("format")) |f| {
                if (f == .string) format = f.string;
            }
            if (obj.get("language")) |lang| {
                if (lang == .object) {
                    const lobj = lang.object;
                    if (lobj.get("name")) |n| {
                        if (n == .string) language = n.string;
                    }
                }
            }
        }
    }

    var book_id: u64 = 0;
    if (data.get("legacyId")) |lid| {
        book_id = switch (lid) {
            .integer => |i| @intCast(i),
            .float => |f| @intFromFloat(f),
            .string => std.fmt.parseInt(u64, lid.string, 10) catch 0,
            else => 0,
        };
    }

    const title_val = data.get("title").?;
    const title_str = if (title_val == .string) title_val.string else "";
    const titleComplete_val = data.get("titleComplete").?;

    var coverImage: ?[]const u8 = null;
    if (data.get("imageUrl")) |img| {
        if (img == .string) coverImage = img.string;
    }
    var webUrl: ?[]const u8 = null;
    if (data.get("webUrl")) |url| {
        if (url == .string) webUrl = url.string;
    }

    return Book{
        .id = book_id,
        .legacyId = legacyId,
        .averageRating = avgRating,
        .title = title_str[0..@min(title_str.len, 500)],
        .titleComplete = if (titleComplete_val == .string) titleComplete_val.string else "",
        .author = authorName,
        .description = description,
        .pageCount = pageCount,
        .language = language,
        .format = format,
        .coverImage = coverImage,
        .webUrl = webUrl,
    };
}

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

    const book = try parseBookData(parsed.value, allocator);
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
