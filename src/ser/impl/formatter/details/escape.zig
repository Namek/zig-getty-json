//! JSON escaping-related code.
//!
//! The escaping rules used in this module originate from Fastly:
//! https://developer.fastly.com/reference/vcl/functions/strings/json-escape/.
//!
//! The rules are as follows (in priority order):
//!
//!   1. If the code point is the double quote (0x22), it is escaped as \".
//!
//!   2. If the code point is the backslash (0x5C), it is escaped as \\.
//!
//!   3. If the code point is listed below, they are escaped accordingly:
//!
//!       * 0x08 (backspace)        ->  \b
//!       * 0x09 (horizontal tab)   ->  \t
//!       * 0x0A (newline)          ->  \n
//!       * 0x0C (form feed)        ->  \f
//!       * 0x0D (carriage return)  ->  \r
//!
//!   4. If the code point is less than or equal to 0x1F, or is equal to
//!   0x7F, 0x2028, or 0x2029, then it is a control character that wasn't
//!   listed above, and is escaped as \uHHHH where 'HHHH' is the hexadecimal
//!   value of the code point.
//!
//!   5. If the code point is greater than 0xFFFF (i.e., it is beyond the Basic
//!   Multilingual Plane of Unicode), the code point is converted into a UTF-16
//!   surrogate pair with the \\u notation (e.g., U+1F601, or '😁', would be
//!   escaped as \uD83D\uDE01).
//!
//!   6. If none of the preceding rules match and there is a sequence of
//!   valid UTF-8 bytes, the bytes are passed through as-is (e.g., the code
//!   point U+0061 would be passed through as 'a').
//!
//!   7. If there is a byte sequence of invalid UTF-8, the conversion fails.
const std = @import("std");

const DOUBLE_QUOTE = '\"';
const BACKSLASH = '\\';
const BACKSPACE = 0x08;
const TAB = '\t';
const NEWLINE = '\n';
const FORM_FEED = 0x0C;
const CARRIAGE_RETURN = '\r';

const HEX_DIGITS = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };

/// Escapes a UTF-8 encoded code point using JSON escape sequences.
pub fn escapeChar(codepoint: u21, writer: anytype) !void {
    switch (codepoint) {
        DOUBLE_QUOTE => try writer.writeAll("\\\""),
        BACKSLASH => try writer.writeAll("\\\\"),
        BACKSPACE => try writer.writeAll("\\b"),
        TAB => try writer.writeAll("\\t"),
        NEWLINE => try writer.writeAll("\\n"),
        FORM_FEED => try writer.writeAll("\\f"),
        CARRIAGE_RETURN => try writer.writeAll("\\r"),
        else => switch (codepoint) {
            0x00...0x1F, 0x7F, 0x2028, 0x2029 => {
                try writer.writeAll(&[_]u8{
                    '\\',
                    'u',
                    HEX_DIGITS[codepoint >> 12 & 0xF],
                    HEX_DIGITS[codepoint >> 8 & 0xF],
                    HEX_DIGITS[codepoint >> 4 & 0xF],
                    HEX_DIGITS[codepoint & 0xF],
                });
            },
            else => if (codepoint > 0xFFFF) {
                std.debug.assert(codepoint <= 0x10FFFF);

                const high = @intCast(u16, (codepoint - 0x10000) >> 10) + 0xD800;
                const low = @intCast(u16, codepoint & 0x3FF) + 0xDC00;

                try writer.writeAll(&[_]u8{
                    '\\',
                    'u',
                    HEX_DIGITS[high >> 12 & 0xF],
                    HEX_DIGITS[high >> 8 & 0xF],
                    HEX_DIGITS[high >> 4 & 0xF],
                    HEX_DIGITS[high & 0xF],
                    '\\',
                    'u',
                    HEX_DIGITS[low >> 12 & 0xF],
                    HEX_DIGITS[low >> 8 & 0xF],
                    HEX_DIGITS[low >> 4 & 0xF],
                    HEX_DIGITS[low & 0xF],
                });
            } else {
                @panic("Received code point that does not require escaping.");
            },
        },
    }
}

/// Escapes characters of a UTF-8 encoded string using JSON escape sequences.
pub fn escape(input: []const u8, writer: anytype, formatter: anytype) !void {
    var bytes = std.mem.sliceTo(input, 0);
    var i: usize = 0;
    var start: usize = 0;

    while (i < bytes.len) : (i += 1) {
        const length = std.unicode.utf8ByteSequenceLength(bytes[i]) catch unreachable;

        // Skip ASCII characters that don't require escaping.
        switch (bytes[i]) {
            0x00...0x1F, DOUBLE_QUOTE, BACKSLASH, 0x7F => {},
            else => if (length == 1) continue,
        }

        const codepoint = std.unicode.utf8Decode(bytes[i .. i + length]) catch unreachable;

        // Skip all other code points that don't require escaping.
        switch (codepoint) {
            0x00...0x1F, DOUBLE_QUOTE, BACKSLASH, 0x7F, 0x2028, 0x2029 => {},
            else => if (codepoint <= 0xFFFF) {
                i += length - 1;
                continue;
            },
        }

        // Write out any buffered non-escaped code points.
        if (start < i) {
            try formatter.writeRawFragment(writer, bytes[start..i]);
        }

        // Escape and write out the current code point.
        try formatter.writeCharEscape(writer, codepoint);

        i += length - 1;
        start = i + 1;
    }

    // If the input string is suffixed by code points that do not require
    // escaping, then they've been buffered, but not written. So, we must write
    // them out.
    if (start != bytes.len) {
        try formatter.writeRawFragment(writer, bytes[start..]);
    }
}
