const getty = @import("getty");
const std = @import("std");

pub fn Deserializer(comptime Reader: type) type {
    return struct {
        reader: Reader,
        scratch: std.ArrayList(u8),
        //remaining_depth: u8 = 128,
        //single_precision: bool = false,
        //disable_recursion_limit: bool = false,

        const Self = @This();

        pub fn init(allocator: *std.mem.Allocator, reader: Reader) Self {
            var d = Self{
                .reader = reader,
                .scratch = std.ArrayList(u8).init(allocator),
            };
            d.reader.readAllArrayList(&d.scratch, 10 * 1024 * 1024) catch unreachable;
            return d;
        }

        pub fn deinit(self: *Self) void {
            self.scratch.deinit();
        }

        /// Implements `getty.de.Deserializer`.
        pub usingnamespace getty.de.Deserializer(
            *Self,
            _D.Error,
            _D.deserializeBool,
            undefined,
            //_D.deserializeEnum,
            _D.deserializeFloat,
            _D.deserializeInt,
            undefined,
            //_D.deserializeMap,
            _D.deserializeOptional,
            undefined,
            //_D.deserializeSequence,
            undefined,
            //_D.deserializeString,
            undefined,
            //_D.deserializeStruct,
            undefined,
            //_D.deserializeVoid,
        );

        const _D = struct {
            const Error = error{Input};

            fn deserializeBool(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
                var tokens = std.json.TokenStream.init(self.scratch.items);

                if (tokens.next() catch return Error.Input) |token| {
                    switch (token) {
                        .True => return try visitor.visitBool(Error, true),
                        .False => return try visitor.visitBool(Error, false),
                        else => {},
                    }
                }

                return Error.Input;
            }

            fn deserializeFloat(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
                var tokens = std.json.TokenStream.init(self.scratch.items);

                if (tokens.next() catch return Error.Input) |token| {
                    switch (token) {
                        .Number => |num| return try visitor.visitFloat(
                            Error,
                            std.fmt.parseFloat(@TypeOf(visitor).Value, num.slice(self.scratch.items, tokens.i - 1)) catch return Error.Input,
                        ),
                        else => {},
                    }
                }

                return Error.Input;
            }

            fn deserializeInt(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
                const Value = @TypeOf(visitor).Value;
                var tokens = std.json.TokenStream.init(self.scratch.items);

                if (tokens.next() catch return Error.Input) |token| {
                    switch (token) {
                        .Number => |num| switch (num.is_integer) {
                            true => return try visitor.visitInt(
                                Error,
                                std.fmt.parseInt(Value, num.slice(self.scratch.items, tokens.i - 1), 10) catch return Error.Input,
                            ),
                            false => return visitor.visitFloat(
                                Error,
                                std.fmt.parseFloat(f128, num.slice(self.scratch.items, tokens.i - 1)) catch return Error.Input,
                            ),
                        },
                        else => {},
                    }
                }

                return Error.Input;
            }

            fn deserializeOptional(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
                var tokens = std.json.TokenStream.init(self.scratch.items);

                if (tokens.next() catch return Error.Input) |token| {
                    return try switch (token) {
                        .Null => visitor.visitNull(Error),
                        else => visitor.visitSome(self.deserializer()),
                    };
                }

                return Error.Input;
            }
        };
    };
}

pub fn fromReader(allocator: *std.mem.Allocator, comptime T: type, reader: anytype) !T {
    var deserializer = Deserializer(@TypeOf(reader)).init(allocator, reader);
    defer deserializer.deinit();

    return try getty.deserialize(T, deserializer.deserializer());
}

pub fn fromString(allocator: *std.mem.Allocator, comptime T: type, string: []const u8) !T {
    var fbs = std.io.fixedBufferStream(string);
    return try fromReader(allocator, T, fbs.reader());
}

test "bool" {
    try std.testing.expectEqual(true, try fromString(std.testing.allocator, bool, "true"));
    try std.testing.expectEqual(false, try fromString(std.testing.allocator, bool, "false"));
}

test "int" {
    try std.testing.expectEqual(@as(u32, 1), try fromString(std.testing.allocator, u32, "1"));
    try std.testing.expectEqual(@as(i32, -1), try fromString(std.testing.allocator, i32, "-1"));
    try std.testing.expectEqual(@as(u32, 1), try fromString(std.testing.allocator, u32, "1.0"));
    try std.testing.expectEqual(@as(i32, -1), try fromString(std.testing.allocator, i32, "-1.0"));
}

test "float" {
    try std.testing.expectEqual(@as(f32, 3.14), try fromString(std.testing.allocator, f32, "3.14"));
    try std.testing.expectEqual(@as(f64, 3.14), try fromString(std.testing.allocator, f64, "3.14"));
    try std.testing.expectEqual(@as(f32, 3.0), try fromString(std.testing.allocator, f32, "3"));
    try std.testing.expectEqual(@as(f64, 3.0), try fromString(std.testing.allocator, f64, "3"));
}

test "optional" {
    try std.testing.expectEqual(@as(?i32, null), try fromString(std.testing.allocator, ?i32, "null"));
    try std.testing.expectEqual(@as(?i32, 42), try fromString(std.testing.allocator, ?i32, "42"));
}

test {
    std.testing.refAllDecls(@This());
}