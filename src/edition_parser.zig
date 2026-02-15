const std = @import("std");

pub const Edition = struct {
    title: []const u8,
    link: []const u8,
    coverImage: ?[]const u8 = null,
};

pub const FilterOption = struct {
    value: []const u8,
    label: []const u8,
    selected: bool,
};

pub const EditionsFilters = struct {
    sort: []FilterOption,
    format: []FilterOption,
    language: []FilterOption,
};

pub const PaginationInfo = struct {
    hasNextPage: bool,
    totalPages: u32,
};

fn extractBetween(html: []const u8, start_tag: []const u8, end_tag: []const u8) ?[]const u8 {
    const start_idx = std.mem.indexOf(u8, html, start_tag) orelse return null;
    const content_start = start_idx + start_tag.len;
    const end_idx = std.mem.indexOf(u8, html[content_start..], end_tag) orelse return null;
    return html[content_start .. content_start + end_idx];
}

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

// Simple tag stripper
fn stripTags(html: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    
    var in_tag = false;
    for (html) |char| {
        if (char == '<') {
            in_tag = true;
        } else if (char == '>') {
            in_tag = false;
        } else if (!in_tag) {
            try result.append(char);
        }
    }
    return try result.toOwnedSlice();
}

pub fn parseEditionsList(html: []const u8, allocator: std.mem.Allocator) ![]Edition {
    var editions = std.ArrayList(Edition).init(allocator);
    errdefer {
        for (editions.items) |e| {
            allocator.free(e.title);
            allocator.free(e.link);
            if (e.coverImage) |c| allocator.free(c);
        }
        editions.deinit();
    }

    var cursor: usize = 0;
    const element_pattern = "elementList";

    while (std.mem.indexOf(u8, html[cursor..], element_pattern)) |idx| {
        const pattern_pos = cursor + idx;
        
        // Find the start of the div containing this class
        var div_start: usize = pattern_pos;
        while (div_start > 0 and html[div_start] != '<') : (div_start -= 1) {}
        
        const next_element_idx = std.mem.indexOf(u8, html[pattern_pos + element_pattern.len ..], element_pattern);
        const element_end = if (next_element_idx) |ne| blk: {
            var end = pattern_pos + element_pattern.len + ne;
            while (end > div_start and html[end] != '<') : (end -= 1) {}
            break :blk end;
        } else html.len;
        
        const element_html = html[div_start..element_end];
        cursor = element_end;

        // 1. Title and Link
        const title_link_start_tag = "class=\"bookTitle\"";
        if (std.mem.indexOf(u8, element_html, title_link_start_tag)) |t_idx| {
            const tag_html = element_html[t_idx..];
            const link_attr = extractAttribute(tag_html, "href") orelse "";
            const link = try allocator.dupe(u8, link_attr);
            errdefer allocator.free(link);

            const content_start = (std.mem.indexOf(u8, tag_html, ">") orelse 0) + 1;
            const content_end = std.mem.indexOf(u8, tag_html[content_start..], "</a>") orelse tag_html.len;
            const raw_title = try stripTags(tag_html[content_start .. content_start + content_end], allocator);
            defer allocator.free(raw_title);
            const title = try allocator.dupe(u8, std.mem.trim(u8, raw_title, " \n\r\t"));
            errdefer allocator.free(title);

            // 2. Cover Image
            var coverImage: ?[]const u8 = null;
            if (extractBetween(element_html, "class=\"leftAlignedImage\"", "</div>")) |img_div| {
                if (extractAttribute(img_div, "src")) |src| {
                    coverImage = try allocator.dupe(u8, src);
                }
            }
            errdefer if (coverImage) |c| allocator.free(c);

            try editions.append(.{
                .title = title,
                .link = link,
                .coverImage = coverImage,
            });
        }
    }

    return try editions.toOwnedSlice();
}

pub fn parseEditionsFilters(html: []const u8, allocator: std.mem.Allocator) !EditionsFilters {
    return EditionsFilters{
        .sort = try extractOptions(html, "sort", allocator),
        .format = try extractOptions(html, "filter_by_format", allocator),
        .language = try extractOptions(html, "filter_by_language", allocator),
    };
}

fn extractOptions(html: []const u8, select_name: []const u8, allocator: std.mem.Allocator) ![]FilterOption {
    var options = std.ArrayList(FilterOption).init(allocator);
    errdefer {
        for (options.items) |o| {
            allocator.free(o.value);
            allocator.free(o.label);
        }
        options.deinit();
    }

    var buf: [128]u8 = undefined;
    const select_pattern = std.fmt.bufPrint(&buf, "name=\"{s}\"", .{select_name}) catch return try options.toOwnedSlice();

    if (std.mem.indexOf(u8, html, select_pattern)) |sidx| {
        const select_start = sidx;
        const select_end = std.mem.indexOf(u8, html[select_start..], "</select>") orelse html.len;
        const select_html = html[select_start .. select_start + select_end];

        var cursor: usize = 0;
        const option_pattern = "<option";
        while (std.mem.indexOf(u8, select_html[cursor..], option_pattern)) |oidx| {
            const opt_start = cursor + oidx;
            const opt_end = std.mem.indexOf(u8, select_html[opt_start..], "</option>") orelse select_html.len;
            const opt_html = select_html[opt_start .. opt_start + opt_end];
            cursor = opt_start + opt_end;

            const val_attr = extractAttribute(opt_html, "value") orelse "";
            const value = try allocator.dupe(u8, val_attr);
            errdefer allocator.free(value);
            
            if (value.len == 0) {
                allocator.free(value);
                continue;
            }

            const label_raw = try stripTags(opt_html, allocator);
            defer allocator.free(label_raw);
            const label = try allocator.dupe(u8, std.mem.trim(u8, label_raw, " \n\r\t"));
            errdefer allocator.free(label);

            const selected = std.mem.containsAtLeast(u8, opt_html, 1, "selected");

            try options.append(.{
                .value = value,
                .label = label,
                .selected = selected,
            });
        }
    }

    return try options.toOwnedSlice();
}

pub fn extractPaginationInfo(html: []const u8) PaginationInfo {
    var totalPages: u32 = 1;
    var hasNextPage = false;

    if (std.mem.indexOf(u8, html, "Showing")) |idx| {
        const start_idx = idx;
        const end_idx = std.mem.indexOf(u8, html[start_idx..], "</div>") orelse html.len;
        const info_html = html[start_idx .. start_idx + end_idx];
        
        if (std.mem.indexOf(u8, info_html, "of")) |of_idx| {
            const after_of = info_html[of_idx + 2 ..];
            var start: ?usize = null;
            var end: ?usize = null;
            for (after_of, 0..) |c, i| {
                if (start == null) {
                    if (std.ascii.isDigit(c)) start = i;
                } else if (end == null) {
                    if (!std.ascii.isDigit(c) and c != ',') {
                        end = i;
                        break;
                    }
                }
            }
            const final_end = end orelse after_of.len;
            if (start) |s| {
                const num_str = after_of[s..final_end];
                var clean_num: [32]u8 = undefined;
                var ci: usize = 0;
                for (num_str) |c| {
                    if (std.ascii.isDigit(c) and ci < 32) {
                        clean_num[ci] = c;
                        ci += 1;
                    }
                }
                const totalItems = std.fmt.parseInt(u32, clean_num[0..ci], 10) catch 0;
                if (totalItems > 0) {
                    totalPages = (totalItems + 9) / 10;
                }
            }
        }
    }

    if (std.mem.indexOf(u8, html, "class=\"pagination\"")) |pidx| {
        const p_end = std.mem.indexOf(u8, html[pidx..], "</div>") orelse html.len;
        const p_html = html[pidx .. pidx + p_end];
        
        var cursor: usize = 0;
        while (std.mem.indexOf(u8, p_html[cursor..], ">")) |midx| {
            const tag_end = cursor + midx + 1;
            const content_end = std.mem.indexOf(u8, p_html[tag_end..], "<") orelse p_html.len;
            const text = std.mem.trim(u8, p_html[tag_end .. tag_end + content_end], " \n\r\t");
            cursor = tag_end + content_end;
            
            if (text.len > 0) {
                const page_num = std.fmt.parseInt(u32, text, 10) catch 0;
                if (page_num > totalPages) totalPages = page_num;
            }
        }
    }

    if (std.mem.indexOf(u8, html, "class=\"next_page\"")) |_| {
        hasNextPage = true;
    }

    return .{
        .hasNextPage = hasNextPage,
        .totalPages = totalPages,
    };
}

pub fn freeEditionsFilters(filters: EditionsFilters, allocator: std.mem.Allocator) void {
    for (filters.sort) |o| {
        allocator.free(o.value);
        allocator.free(o.label);
    }
    allocator.free(filters.sort);
    for (filters.format) |o| {
        allocator.free(o.value);
        allocator.free(o.label);
    }
    allocator.free(filters.format);
    for (filters.language) |o| {
        allocator.free(o.value);
        allocator.free(o.label);
    }
    allocator.free(filters.language);
}

pub fn freeEditionsList(editions: []Edition, allocator: std.mem.Allocator) void {
    for (editions) |e| {
        allocator.free(e.title);
        allocator.free(e.link);
        if (e.coverImage) |c| allocator.free(c);
    }
    allocator.free(editions);
}

test "extract filter options (sort, format, language) from editions page" {
    const allocator = std.testing.allocator;
    var client = try @import("http_client.zig").HttpClient.init(allocator);
    defer client.deinit();

    const html = try client.fetch("https://www.goodreads.com/work/editions/53043399");
    defer allocator.free(html);

    const filters = try parseEditionsFilters(html, allocator);
    defer freeEditionsFilters(filters, allocator);

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

    const editions = try parseEditionsList(html, allocator);
    defer freeEditionsList(editions, allocator);

    const pagination = extractPaginationInfo(html);

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

    const editions = try parseEditionsList(html, allocator);
    defer freeEditionsList(editions, allocator);

    const pagination = extractPaginationInfo(html);

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

    var all_editions = std.ArrayList(Edition).init(allocator);
    defer {
        for (all_editions.items) |e| {
            allocator.free(e.title);
            allocator.free(e.link);
            if (e.coverImage) |c| allocator.free(c);
        }
        all_editions.deinit();
    }

    const first_page = try parseEditionsList(html, allocator);
    try all_editions.appendSlice(first_page);
    allocator.free(first_page);

    const pagination = extractPaginationInfo(html);
    try std.testing.expectEqual(@as(u32, 2), pagination.totalPages);

    if (pagination.totalPages > 1) {
        var i: u32 = 2;
        while (i <= pagination.totalPages) : (i += 1) {
            const pageUrl = try std.fmt.allocPrint(allocator, "{s}&page={d}", .{ baseUrl, i });
            defer allocator.free(pageUrl);

            const pageHtml = try client.fetch(pageUrl);
            defer allocator.free(pageHtml);

            const page_editions = try parseEditionsList(pageHtml, allocator);
            try all_editions.appendSlice(page_editions);
            allocator.free(page_editions);
            
            std.time.sleep(100 * std.time.ns_per_ms); 
        }
    }

    try std.testing.expectEqual(@as(usize, 12), all_editions.items.len);
}
