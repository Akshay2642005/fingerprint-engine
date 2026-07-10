const std = @import("std");
const testing = std.testing;

// Verifies that the fingerprint JSON fixture files are well-formed
// and parse correctly.
test "fingerprint fixture files exist and parse" {
    // These files are embedded at compile time using @embedFile
    // to ensure they stay in sync with the code.
    const chrome = @embedFile("chrome_win10.json");
    const firefox = @embedFile("firefox_macos.json");
    const minimal = @embedFile("minimal.json");

    try testing.expect(chrome.len > 100);
    try testing.expect(firefox.len > 100);
    try testing.expect(minimal.len > 100);

    // Verify they parse as valid JSON
    var parsed_chrome = try std.json.parseFromSlice(
        std.json.Value,
        testing.allocator,
        chrome,
        .{},
    );
    defer parsed_chrome.deinit();

    var parsed_firefox = try std.json.parseFromSlice(
        std.json.Value,
        testing.allocator,
        firefox,
        .{},
    );
    defer parsed_firefox.deinit();

    var parsed_minimal = try std.json.parseFromSlice(
        std.json.Value,
        testing.allocator,
        minimal,
        .{},
    );
    defer parsed_minimal.deinit();

    // Verify expected top-level keys
    try checkField(&parsed_chrome.value, "label");
    try checkField(&parsed_chrome.value, "description");
    try checkField(&parsed_chrome.value, "metadata");
    try checkField(&parsed_chrome.value, "features");

    try checkField(&parsed_firefox.value, "features");
    try checkField(&parsed_minimal.value, "features");

    // Verify features array has expected count
    const chrome_features = parsed_chrome.value.object.get("features").?.array;
    const firefox_features = parsed_firefox.value.object.get("features").?.array;
    const minimal_features = parsed_minimal.value.object.get("features").?.array;

    try testing.expect(chrome_features.items.len > 20);
    try testing.expect(firefox_features.items.len > 20);
    try testing.expect(minimal_features.items.len >= 24);
}

fn checkField(value: *const std.json.Value, name: []const u8) !void {
    const obj = value.object;
    try testing.expect(obj.contains(name));
}

test "similarity dataset fixture exists" {
    const data = @embedFile("../../fixtures/datasets/similarity_suite.json");
    try testing.expect(data.len > 100);

    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        testing.allocator,
        data,
        .{},
    );
    defer parsed.deinit();

    try testing.expect(parsed.value.object.contains("label"));
    try testing.expect(parsed.value.object.contains("pairs"));

    const pairs = parsed.value.object.get("pairs").?.array;
    try testing.expect(pairs.items.len == 3);
}

test "browser signals reference doc exists" {
    const data = @embedFile("../browser/signals.md");
    try testing.expect(data.len > 200);
    try testing.expect(std.mem.indexOf(u8, data, "Chrome 120") != null);
    try testing.expect(std.mem.indexOf(u8, data, "Firefox 121") != null);
    try testing.expect(std.mem.indexOf(u8, data, "Safari 17") != null);
}
