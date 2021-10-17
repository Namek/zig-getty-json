const getty = @import("getty");
const std = @import("std");

const free = @import("lib.zig").free;

const eql = std.mem.eql;
const testing = std.testing;

const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualSlices = testing.expectEqualSlices;
const expectError = testing.expectError;

pub const Deserializer = @import("de/deserializer.zig").Deserializer;

pub fn fromDeserializer(comptime T: type, d: *Deserializer) !T {
    const value = try getty.deserialize(d.allocator, T, d.deserializer());
    errdefer if (d.allocator) |alloc| free(alloc, value);
    try d.end();

    return value;
}

pub fn fromDeserializerWith(comptime T: type, d: *Deserializer, de: anytype) !T {
    const value = try getty.deserializeWith(d.allocator, T, d.deserializer(), de);
    errdefer if (d.allocator) |alloc| free(alloc, value);
    try d.end();

    return value;
}

pub fn fromReader(allocator: *std.mem.Allocator, comptime T: type, reader: anytype) !T {
    var d = Deserializer.fromReader(allocator, reader);
    defer d.deinit();

    return fromDeserializer(T, &d);
}

pub fn fromReaderWith(allocator: *std.mem.Allocator, comptime T: type, reader: anytype, de: anytype) !T {
    var d = Deserializer.fromReader(allocator, reader);
    defer d.deinit();

    return fromDeserializerWith(T, &d, de);
}

pub fn fromSlice(allocator: ?*std.mem.Allocator, comptime T: type, slice: []const u8) !T {
    var d = if (allocator) |alloc| Deserializer.withAllocator(alloc, slice) else Deserializer.init(slice);
    defer d.deinit();

    return fromDeserializer(T, &d);
}

pub fn fromSliceWith(allocator: ?*std.mem.Allocator, comptime T: type, slice: []const u8, de: anytype) !T {
    var d = if (allocator) |alloc| Deserializer.withAllocator(alloc, slice) else Deserializer.init(slice);
    defer d.deinit();

    return fromDeserializerWith(T, &d, de);
}

test "array" {
    try expectEqual([0]bool{}, try fromSlice(null, [0]bool, "[]"));
    try expectEqual([1]bool{true}, try fromSlice(null, [1]bool, "[true]"));
    try expectEqual([2]bool{ true, false }, try fromSlice(null, [2]bool, "[true,false]"));
    try expectEqual([5]i32{ 1, 2, 3, 4, 5 }, try fromSlice(null, [5]i32, "[1,2,3,4,5]"));
    try expectEqual([2][1]i32{ .{1}, .{2} }, try fromSlice(null, [2][1]i32, "[[1],[2]]"));
    try expectEqual([2][1][3]i32{ .{.{ 1, 2, 3 }}, .{.{ 4, 5, 6 }} }, try fromSlice(null, [2][1][3]i32, "[[[1,2,3]],[[4,5,6]]]"));
}

test "array list" {
    // scalar child
    {
        const got = try fromSlice(testing.allocator, std.ArrayList(u8), "[1,2,3,4,5]");
        defer got.deinit();

        try expectEqual(std.ArrayList(u8), @TypeOf(got));
        try expect(eql(u8, &[_]u8{ 1, 2, 3, 4, 5 }, got.items));
    }

    // array list child
    {
        const got = try fromSlice(testing.allocator, std.ArrayList(std.ArrayList(u8)), "[[1, 2],[3,4]]");
        defer free(testing.allocator, got);

        try expectEqual(std.ArrayList(std.ArrayList(u8)), @TypeOf(got));
        try expectEqual(std.ArrayList(u8), @TypeOf(got.items[0]));
        try expectEqual(std.ArrayList(u8), @TypeOf(got.items[1]));
        try expect(eql(u8, &[_]u8{ 1, 2 }, got.items[0].items));
        try expect(eql(u8, &[_]u8{ 3, 4 }, got.items[1].items));
    }
}

test "bool" {
    try expectEqual(true, try fromSlice(null, bool, "true"));
    try expectEqual(false, try fromSlice(null, bool, "false"));
}

test "enum" {
    const Enum = enum { foo, bar };

    try expectEqual(Enum.foo, try fromSlice(null, Enum, "0"));
    try expectEqual(Enum.bar, try fromSlice(null, Enum, "1"));
    try expectEqual(Enum.foo, try fromSlice(null, Enum, "\"foo\""));
    try expectEqual(Enum.bar, try fromSlice(null, Enum, "\"bar\""));
}

test "float" {
    try expectEqual(@as(f32, std.math.f32_min), try fromSlice(null, f32, "1.17549435082228750797e-38"));
    try expectEqual(@as(f32, std.math.f32_max), try fromSlice(null, f32, "3.40282346638528859812e+38"));
    try expectEqual(@as(f64, std.math.f64_min), try fromSlice(null, f64, "2.2250738585072014e-308"));
    try expectEqual(@as(f64, std.math.f64_max), try fromSlice(null, f64, "1.79769313486231570815e+308"));
    try expectEqual(@as(f32, 1.0), try fromSlice(null, f32, "1"));
    try expectEqual(@as(f64, 2.0), try fromSlice(null, f64, "2"));
}

test "int" {
    try expectEqual(@as(u8, std.math.maxInt(u8)), try fromSlice(null, u8, "255"));
    try expectEqual(@as(u32, std.math.maxInt(u32)), try fromSlice(null, u32, "4294967295"));
    try expectEqual(@as(u64, std.math.maxInt(u64)), try fromSlice(null, u64, "18446744073709551615"));
    try expectEqual(@as(i8, std.math.maxInt(i8)), try fromSlice(null, i8, "127"));
    try expectEqual(@as(i32, std.math.maxInt(i32)), try fromSlice(null, i32, "2147483647"));
    try expectEqual(@as(i64, std.math.maxInt(i64)), try fromSlice(null, i64, "9223372036854775807"));
    try expectEqual(@as(i8, std.math.minInt(i8)), try fromSlice(null, i8, "-128"));
    try expectEqual(@as(i32, std.math.minInt(i32)), try fromSlice(null, i32, "-2147483648"));
    try expectEqual(@as(i64, std.math.minInt(i64)), try fromSlice(null, i64, "-9223372036854775808"));

    // TODO: higher-bit conversions from float don't seem to work.
}

test "optional" {
    try expectEqual(@as(?bool, null), try fromSlice(null, ?bool, "null"));
    try expectEqual(@as(?bool, true), try fromSlice(null, ?bool, "true"));
}

test "pointer" {
    // one level of indirection
    {
        const value = try fromSlice(testing.allocator, *bool, "true");
        defer free(testing.allocator, value);

        try expectEqual(true, value.*);
    }

    // two levels of indirection
    {
        const value = try fromSlice(testing.allocator, **[]const u8, "\"Hello, World!\"");
        defer free(testing.allocator, value);

        try expectEqualSlices(u8, "Hello, World!", value.*.*);
    }

    // enum
    {
        const T = enum { foo, bar };

        // Tag value
        {
            const value = try fromSlice(testing.allocator, *T, "0");
            defer free(testing.allocator, value);

            try expectEqual(T.foo, value.*);
        }

        // Tag name
        {
            const value = try fromSlice(testing.allocator, *T, "\"bar\"");
            defer free(testing.allocator, value);

            try expectEqual(T.bar, value.*);
        }
    }

    // optional
    {
        // some
        {
            const value = try fromSlice(testing.allocator, *?bool, "true");
            defer free(testing.allocator, value);

            try expectEqual(true, value.*.?);
        }

        // none
        {
            const value = try fromSlice(testing.allocator, *?bool, "null");
            defer free(testing.allocator, value);

            try expectEqual(false, value.* orelse false);
        }
    }

    // sequence
    {
        const value = try fromSlice(testing.allocator, *[3]i8, "[1,2,3]");
        defer free(testing.allocator, value);

        try expectEqual([_]i8{ 1, 2, 3 }, value.*);
    }

    // struct
    {
        const T = struct { x: i32, y: []const u8, z: *[]const u8 };
        const value = try fromSlice(testing.allocator, *T,
            \\{"x":1,"y":"hello","z":"world"}
        );
        defer free(testing.allocator, value);

        try expectEqual(@as(i32, 1), value.*.x);
        try expectEqualSlices(u8, "hello", value.*.y);
        try expectEqualSlices(u8, "world", value.*.z.*);
    }

    // void
    {
        const value = try fromSlice(testing.allocator, *void, "null");
        defer free(testing.allocator, value);

        try expectEqual({}, value.*);
    }
}

test "slice (string)" {
    // Zig string
    const got = try fromSlice(testing.allocator, []const u8, "\"Hello, World!\"");
    defer free(testing.allocator, got);
    try expect(eql(u8, "Hello, World!", got));

    // Non-zig string
    try expectError(error.Input, fromSlice(testing.allocator, []i8, "\"Hello, World!\""));
}

test "slice (non-string)" {
    // scalar child
    {
        const got = try fromSlice(testing.allocator, []i32, "[1,2,3,4,5]");
        defer free(testing.allocator, got);

        try expectEqual([]i32, @TypeOf(got));
        try expect(eql(i32, &[_]i32{ 1, 2, 3, 4, 5 }, got));
    }

    // array child
    {
        const wants = .{
            [3]u32{ 1, 2, 3 },
            [3]u32{ 4, 5, 6 },
            [3]u32{ 7, 8, 9 },
        };
        const got = try fromSlice(testing.allocator, [][3]u32,
            \\[[1,2,3],[4,5,6],[7,8,9]]
        );
        defer free(testing.allocator, got);

        try expectEqual([][3]u32, @TypeOf(got));
        inline for (wants) |want, i| try expect(eql(u32, &want, &got[i]));
    }

    // slice child
    {
        const wants = .{
            [_]u8{ 1, 2, 3 },
            [_]u8{ 4, 5 },
            [_]u8{6},
            [_]u8{ 7, 8, 9, 10 },
        };
        const got = try fromSlice(testing.allocator, [][]u8,
            \\[[1,2,3],[4,5],[6],[7,8,9,10]]
        );
        defer free(testing.allocator, got);

        try expectEqual([][]u8, @TypeOf(got));
        inline for (wants) |want, i| try expect(eql(u8, &want, got[i]));
    }

    // string child
    {
        const wants = .{
            "Foo",
            "Bar",
            "Foobar",
        };
        const got = try fromSlice(testing.allocator, [][]const u8,
            \\["Foo","Bar","Foobar"]
        );
        defer free(testing.allocator, got);

        try expectEqual([][]const u8, @TypeOf(got));
        inline for (wants) |want, i| {
            try expect(eql(u8, want, got[i]));
        }
    }
}

test "struct" {
    // no allocation
    {
        const got = try fromSlice(null, struct { x: i32, y: i32 },
            \\{"x":1,"y":2}
        );

        try expectEqual(@as(i32, 1), got.x);
        try expectEqual(@as(i32, 2), got.y);
    }

    // allocation
    {
        const got = try fromSlice(testing.allocator, struct { x: []const u8 },
            \\{"x":"Hello"}
        );
        defer free(testing.allocator, got);

        try expect(eql(u8, "Hello", got.x));
    }
}

test "void" {
    try expectEqual({}, try fromSlice(null, void, "null"));
    try testing.expectError(error.Input, fromSlice(null, void, "true"));
    try testing.expectError(error.Input, fromSlice(null, void, "1"));
}

test {
    testing.refAllDecls(@This());
}
