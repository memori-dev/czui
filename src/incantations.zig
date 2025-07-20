const std = @import("std");
const stdout = std.io.getStdOut().writer();
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectErr = std.testing.expectError;

const ESC: u8 = 27;
const ASCIIIntOffset: u8 = 48;
const u64MaxStrLen: usize = 20;
const u16MaxStrLen: usize = 5;

fn allCharsAreNumeric(bytes: []const u8) bool {
	for (0..bytes.len) |i| if (bytes[i] < ASCIIIntOffset or bytes[i] > ASCIIIntOffset + 9) return false;
	return true;
}

// additional empty ints, represented as "1;;3", will not invalidate the EscSeq
// very large numbers are valid, eg. 999... repeating for 128 characters
// if there is a space in an additional int, eg. "1;234 567;89", it will become invalid
// if there is a non-numeric character in an addition int, eg. '.' or '_', it will become invalid
fn parseFirstInteger(comptime T: type, bytes: []const u8) ?T {
	var it = std.mem.splitSequence(u8, bytes, ";");
	if (std.fmt.parseInt(T, it.first(), 10)) |first| {
		while (it.next()) |v| {
			// empty is valid
			if (v.len == 0) continue;
			if (!allCharsAreNumeric(v)) return null;
		}

		return first;
	}
	else |_| return null;
}

test "parseFirstInteger" {
	// only up to u16 is necessary for incantations
	const UInt1To16 = [16]type{u1,u2,u3,u4,u5,u6,u7,u8,u9,u10,u11,u12,u13,u14,u15,u16};

	// empty returns null
	inline for (UInt1To16) |t| try expect(parseFirstInteger(t, "") == null);

	// one integer valid
	{
		var buf: [u16MaxStrLen]u8 = undefined;
		inline for (UInt1To16) |t| {
			for (0..std.math.maxInt(t)+1) |i| {
				const str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable;
				try expect(parseFirstInteger(t, str).? == i);
			}
		}
	}

	// integer larger than maxInt returns null
	{
		var buf: [u16MaxStrLen]u8 = undefined;
		inline for (UInt1To16) |t| {
			const i: u32 = @intCast(std.math.maxInt(t)+1);
			const str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable;
			try expect(parseFirstInteger(t, str) == null);
		}
	}

	// one integer invalid (covers a chunk of the invalid space, would have to test every valid u8 outside of numeric ascii range which is 246^5 just for u16)
	{
		var buf: [u16MaxStrLen]u8 = undefined;
		inline for (UInt1To16) |t| {
			for (0..std.math.maxInt(t)+1) |i| {
				const str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable;
				for (0..str.len) |j| {
					var copy = str;
					// push each index out of the numeric range
					copy[j] = str[j] +% 10;
					try expect(parseFirstInteger(t, copy) == null);
				}
			}
		}
	}

	// multiple with invalid inputs (assumes that if the second fails any proceeding will cause a failure)
	{
		const val: u16 = 1;

		inline for (UInt1To16) |t| {
			var buf: [u16MaxStrLen+2]u8 = undefined;
			buf[0] = val + ASCIIIntOffset;
			buf[1] = ';';

			for (0..std.math.maxInt(t)+1) |i| {
				const str = std.fmt.bufPrint(buf[2..], "{d}", .{i}) catch unreachable;
				for (0..str.len) |j| {
					var copy = str;
					// push each index out of the numeric range
					copy[j] = str[j] +% 10;
					try expect(parseFirstInteger(t, copy) == null);
				}
			}
		}
	}

	// multiple with valid inputs (assumes that if the second passes any additional will pass)
	{
		const val: u16 = 1;
		var buf: [u16MaxStrLen + 2]u8 = undefined;
		buf[0] = val + ASCIIIntOffset;
		buf[1] = ';';

		inline for (UInt1To16) |t| {
			for (0..std.math.maxInt(t)+1) |v| {
				const len = (std.fmt.bufPrint(buf[2..], "{d}", .{v}) catch unreachable).len + 2;
				try expect(parseFirstInteger(t, buf[0..len]).? == val);
			}
		}
	}

	// multiple with empty (assumes that if the second passes any additional will pass)
	{
		const val: u16 = 1;
		var buf: [u16MaxStrLen + 3]u8 = undefined;
		buf[0] = val + ASCIIIntOffset;
		buf[1] = ';';
		buf[2] = ';';

		inline for (UInt1To16) |t| {
			for (0..std.math.maxInt(t)+1) |v| {
				const len = (std.fmt.bufPrint(buf[3..], "{d}", .{v}) catch unreachable).len + 3;
				try expect(parseFirstInteger(t, buf[0..len]).? == val);
			}
		}
	}
}

// ESC[{u3} q
// the space is required
pub const CursorStyle = enum(u3) {
	const Self = @This();

	pub const fnChar: u8 = 'q';
	const minLen: usize = 4;
	const default: Self = .blinkingBlockDefault;
	const defaultStr: [4]u8 = .{ESC, '[', ' ', 'q'};
	const formatInt: []const u8 = "\x1b[{d} q";
	const formatStr: []const u8 = "\x1b[{s} q";

	blinkingBlock        = 0,
	blinkingBlockDefault = 1,
	steadyBlock          = 2,
	blinkingUnderline    = 3,
	steadyUnderline      = 4,
	blinkingBar          = 5,
	steadyBar            = 6,

	const ParseErr = error {
		InsufficientLen,
		IncorrectFormat,
		InvalidInt,
	};

	fn parse(bytes: []const u8) Self.ParseErr!Self {
		const len = bytes.len;
		if (len < minLen) return error.InsufficientLen;
		if (bytes[0] != ESC or bytes[1] != '[' or bytes[len-2] != ' ' or bytes[len-1] != Self.fnChar) return error.IncorrectFormat;

		// empty
		if (std.mem.eql(u8, &Self.defaultStr, bytes)) return Self.default;

		if (parseFirstInteger(u3, bytes[2..len-2])) |val| {
			if (std.meta.intToEnum(Self, val)) |out| return out
			else |_| {}
		}

		return error.InvalidInt;
	}

	fn print(self: Self) [5]u8 {
		return .{ESC, '[', @intFromEnum(self) + ASCIIIntOffset, ' ', 'q'};
	}
};

fn testEnum(comptime Enum: type) !void {
	// default
	try expect(try Enum.parse(&Enum.defaultStr) == Enum.default);

	// every field parses and prints
	// enum (src) -> print (bytes) -> parse (out) -> print (outBytes)
	// ensures there is no data loss between conversions for all valid values
	inline for (std.meta.fields(Enum)) |f| {
		const src: Enum = @enumFromInt(f.value);
		const bytes = src.print();
		
		const out = try Enum.parse(&bytes);
		const outBytes = out.print();
		
		try expect(src == out);
		try expect(std.mem.eql(u8, &bytes, &outBytes));
	}

	// multiple: just the first int is parsed
	{
		const maxInputs: usize = 16;
		
		// first input is the default so that we can easily expect the default to be returned
		// every other input is i^i
		var inputs: [maxInputs]u64 = undefined;
		inputs[0] = @intFromEnum(Enum.default);
		for (1..maxInputs) |i| inputs[i] = std.math.pow(u64, i, i);

		var inputStrsBackingBuf: [maxInputs][u64MaxStrLen]u8 = undefined;
		var inputStrs: [maxInputs][]const u8 = undefined;
		for (0..maxInputs) |i| inputStrs[i] = std.fmt.bufPrint(&inputStrsBackingBuf[i], "{d}", .{inputs[i]}) catch unreachable;

		// max length of each u64 str + n (for each ';')
		var maxInputBuf: [(u64MaxStrLen * maxInputs) + maxInputs]u8 = undefined;
		var index: usize = 0;

		var maxFormatBuf: [maxInputBuf.len + Enum.defaultStr.len]u8 = undefined;
		for (0..maxInputs) |i| {
			std.mem.copyForwards(u8, maxInputBuf[index..], inputStrs[i]);
			index += inputStrs[i].len;

			const str = std.fmt.bufPrint(&maxFormatBuf, Enum.formatStr, .{maxInputBuf[0..index]}) catch unreachable;
			try expect(try Enum.parse(str) == Enum.default);

			maxInputBuf[index] = ';';
			index += 1;
		}
	}

	// InsufficientLen
	// checks all lens less than minLen return InsufficientLen
	{
		var buf: [Enum.minLen]u8 = undefined;
		for (0..Enum.minLen) |i| try expectErr(Enum.ParseErr.InsufficientLen, Enum.parse(buf[0..i]));
	}

	// IncorrectFormat
	// checks that it will return IncorrectFormat if any format char is incorrect
	{
		for (0..Enum.defaultStr.len) |i| {
			var defaultCopy = Enum.defaultStr;
			defaultCopy[i] = defaultCopy[i] +% 1;
			try expectErr(Enum.ParseErr.IncorrectFormat, Enum.parse(&defaultCopy));
		}
	}

	// InvalidInt
	// checks that it will return InvalidInt for all numbers that are not valid values of the enum
	{
		var buf: [u16MaxStrLen + Enum.defaultStr.len]u8 = undefined;

		for (0..std.math.maxInt(u16)+1) |i| {
			// number must not be a valid enum val
			if (std.meta.intToEnum(Enum, i) != std.meta.IntToEnumError.InvalidEnumTag) continue;

			const str = std.fmt.bufPrint(&buf, Enum.formatInt, .{i}) catch unreachable;
			try expectErr(Enum.ParseErr.InvalidInt, Enum.parse(str));
		}
	}
}

test "EscSeq" {
	try testEnum(CursorStyle);
}