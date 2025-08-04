const std = @import("std");
const consts = @import("consts.zig");
const expect = std.testing.expect;

const SingularArg = struct {
	const Self = @This();

	fn allCharsAreNumeric(bytes: []const u8) bool {
		for (0..bytes.len) |i| if (bytes[i] < consts.ASCIIIntOffset or bytes[i] > consts.ASCIIIntOffset + 9) return false;
		return true;
	}

	// additional empty ints, represented as "1;;3", will not invalidate the EscSeq
	// very large numbers are valid, eg. 999... repeating for 128 characters
	// if there is a non-numeric character in an addition int it will become invalid
	//// eg. "1;234 567;89", "1;234.567;89", "1;234_567;89"
	fn remainingAreValid(it: *std.mem.SplitIterator(u8, .scalar)) error{RemainingHasInvalidChar}!void {
		while (it.next()) |str| {
			// empty is valid
			if (str.len == 0) continue;
			if (!Self.allCharsAreNumeric(str)) return error.RemainingHasInvalidChar;
		}
	}

	pub const Err = error {
		FirstIntIsEmpty,
		FirstIntOverflows,
		FirstIntHasInvalidChar,
		RemainingHasInvalidChar,
	};

	// all ints must be valid
	pub fn parse(comptime T: type, bytes: []const u8) Self.Err!T {
		var it = std.mem.splitScalar(u8, bytes, consts.separator);
		
		const firstStr = it.first();
		if (firstStr.len == 0) return error.FirstIntIsEmpty;
		const first = std.fmt.parseInt(T, firstStr, 10) catch |err| {
			switch (err) {
				error.InvalidCharacter => return error.FirstIntHasInvalidChar,
				error.Overflow => return error.FirstIntOverflows,
			}
		};
		
		try Self.remainingAreValid(&it);
		
		return first;
	}
};

fn testSingularArgParse(comptime T: type) !void {
	const Self = SingularArg.Self;

	// FirstIntIsEmpty
	try expect(Self.parse(T, "") == Self.Err.FirstIntIsEmpty);

	// FirstIntOverflows
	{
		var buf: [consts.u16MaxStrLen]u8 = undefined;
		const overflow: u32 = @intCast(std.math.maxInt(T)+1);
		const str = std.fmt.bufPrint(&buf, "{d}", .{overflow}) catch unreachable;
		try expect(Self.parse(T, str) == Self.Err.FirstIntOverflows);
	}

	// FirstIntHasInvalidChar
	{
		var buf: [consts.u16MaxStrLen]u8 = undefined;

		for (0..std.math.maxInt(T)+1) |v| {
			const strLen = (std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable).len;
			for (0..strLen) |j| {
				const str = std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable;
				// push each index out of the numeric range while avoiding ';'
				str[j] += 12;
				try expect(Self.parse(T, str) == error.FirstIntHasInvalidChar);
			}
		}
	}

	// RemainingHasInvalidChar
	// two ints; first valid, second has InvalidChar (assumes that if the second fails any proceeding will cause a failure)
	{
		var buf: [consts.u16MaxStrLen+2]u8 = undefined;
		buf[0] = consts.ASCIIIntOffset;
		buf[1] = consts.separator;

		for (0..std.math.maxInt(T)+1) |v| {
			const strLen = (std.fmt.bufPrint(buf[2..], "{d}", .{v}) catch unreachable).len;
			for (0..strLen) |i| {
				const str = std.fmt.bufPrint(buf[2..], "{d}", .{v}) catch unreachable;
				// push each index out of the numeric range
				str[i] += 12;
				try expect(Self.parse(T, buf[0..str.len+2]) == error.RemainingHasInvalidChar);
			}
		}
	}

	// one valid int
	{
		var buf: [consts.u16MaxStrLen]u8 = undefined;
		for (0..std.math.maxInt(T)+1) |v| {
			const str = std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable;
			try expect(try Self.parse(T, str) == v);
		}
	}

	// two valid ints (assumes that if the second passes any additional will pass)
	{
		const val: u16 = 1;
		var buf: [consts.u16MaxStrLen + 2]u8 = undefined;
		buf[0] = val + consts.ASCIIIntOffset;
		buf[1] = consts.separator;

		for (0..std.math.maxInt(T)+1) |v| {
			const len = (std.fmt.bufPrint(buf[2..], "{d}", .{v}) catch unreachable).len + 2;
			try expect(try Self.parse(T, buf[0..len]) == val);
		}
	}

	// multiple with empty (assumes that if the second passes any additional will pass)
	{
		const val: u16 = 1;
		var buf: [consts.u16MaxStrLen + 3]u8 = undefined;
		buf[0] = val + consts.ASCIIIntOffset;
		buf[1] = consts.separator;
		buf[2] = consts.separator;

		for (0..std.math.maxInt(T)+1) |v| {
			const len = (std.fmt.bufPrint(buf[3..], "{d}", .{v}) catch unreachable).len + 3;
			try expect(try Self.parse(T, buf[0..len]) == val);
		}
	}
}

test SingularArg {
	inline for (consts.UInt1To16) |T| try testSingularArgParse(T);
}

pub const ParseErr = error {
	InsufficientLen,
	IncorrectFormat,
	UnknownInt,
} || SingularArg.Err;

fn parseGen(comptime Enum: type, bytes: []const u8) ParseErr!Enum {
	const enumTagType = @typeInfo(Enum).@"enum".tag_type;

	if (bytes.len < Enum.minLen) return error.InsufficientLen;
	if (!std.mem.eql(u8, &consts.CSI, bytes[0..2])) return error.IncorrectFormat;
	if (!std.mem.eql(u8, &Enum.fnName, bytes[bytes.len-Enum.fnName.len..])) return error.IncorrectFormat;

	// empty, default should never be null as the minLen check would fail otherwise
	if (bytes.len-Enum.fnName.len-2 == 0) return Enum.default orelse unreachable;

	const first = try SingularArg.parse(enumTagType, bytes[2..bytes.len-Enum.fnName.len]);
	return if (std.meta.intToEnum(Enum, first)) |out| out
	else |_| error.UnknownInt;
}

fn printGen(comptime Enum: type, val: Enum) [3 + Enum.fnName.len]u8 {
	return consts.CSI ++ .{@intFromEnum(val) + consts.ASCIIIntOffset} ++ Enum.fnName;
}

pub const NavKey = enum(u4) {
	const Self = @This();

	pub const fnName: [1]u8  = .{'~'};
	const default:    ?Self  = null;
	const defaultStr: ?[0]u8 = null;
	const minLen:     usize  = consts.CSI.len + 1 + Self.fnName.len;

	insert   = 2,
	delete   = 3,
	pageUp   = 5,
	pageDown = 6,

	pub fn parse(bytes: []const u8) ParseErr!Self {
		return parseGen(Self, bytes);
	}

	pub fn print(self: Self) [3 + Self.fnName.len]u8 {
		return printGen(Self, self);
	}
};

pub const CursorStyle = enum(u3) {
	const Self = @This();

	// the space is required
	pub const fnName: [2]u8  = .{' ', 'q'};
	const default:    ?Self  = .blinkingBlockDefault;
	const defaultStr: ?[4]u8 = consts.CSI ++ Self.fnName;
	const minLen:     usize  = Self.defaultStr.?.len;

	blinkingBlock        = 0,
	blinkingBlockDefault = 1,
	steadyBlock          = 2,
	blinkingUnderline    = 3,
	steadyUnderline      = 4,
	blinkingBar          = 5,
	steadyBar            = 6,

	pub fn parse(bytes: []const u8) ParseErr!Self {
		return parseGen(Self, bytes);
	}

	pub fn print(self: Self) [3 + Self.fnName.len]u8 {
		return printGen(Self, self);
	}
};

pub const EraseDisplay = enum(u2) {
	const Self = @This();

	pub const fnName: [1]u8  = .{'J'};
	const default:    ?Self  = Self.cursorToEnd;
	const defaultStr: ?[3]u8 = consts.CSI ++ Self.fnName;
	const minLen:     usize  = Self.defaultStr.?.len;

	// end of screen
	cursorToEnd  = 0,
	// beginning of screen
	cursorToHome = 1,
	all          = 2,
	// scrollback
	savedLines   = 3,

	pub fn parse(bytes: []const u8) ParseErr!Self {
		return parseGen(Self, bytes);
	}

	pub fn print(self: Self) [3 + Self.fnName.len]u8 {
		return printGen(Self, self);
	}
};

pub const EraseLine = enum(u2) {
	const Self = @This();

	pub const fnName: [1]u8  = .{'K'};
	const default:    ?Self  = Self.cursorToEnd;
	const defaultStr: ?[3]u8 = consts.CSI ++ Self.fnName;
	const minLen:     usize  = Self.defaultStr.?.len;

	cursorToEnd   = 0,
	cursorToStart = 1,
	entire        = 2,
	// scrollback
	saved         = 3,

	pub fn parse(bytes: []const u8) ParseErr!Self {
		return parseGen(Self, bytes);
	}

	pub fn print(self: Self) [3 + Self.fnName.len]u8 {
		return printGen(Self, self);
	}
};

pub const DeviceStatusReport = enum(u3) {
	const Self = @This();

	pub const fnName: [1]u8  = .{'K'};
	const default:    ?Self  = null;
	const defaultStr: ?[0]u8 = null;
	const minLen:     usize  = consts.CSI.len + 1 + Self.fnName.len;

	statusReport   = 5,
	cursorPosition = 6,

	pub fn parse(bytes: []const u8) ParseErr!Self {
		return parseGen(Self, bytes);
	}

	pub fn print(self: Self) [3 + Self.fnName.len]u8 {
		return printGen(Self, self);
	}
};

fn testSingularArg(comptime Enum: type) !void {
	const enumTagType = @typeInfo(Enum).@"enum".tag_type;
	
	// default
	{
		if (Enum.default) |default| {
			try expect(Enum.defaultStr != null);
			try expect(try Enum.parse(&Enum.defaultStr.?) == default);
		}
		else try expect(Enum.defaultStr == null);
	}

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
		
		// first input is the first enum field so that it can be easily expected against
		// every other input is i^i
		var inputs: [maxInputs]u64 = undefined;
		const firstEnumValue = std.meta.fields(Enum)[0].value;
		const firstEnum: Enum = @enumFromInt(firstEnumValue);
		inputs[0] = firstEnumValue;
		for (1..maxInputs) |i| inputs[i] = std.math.pow(u64, i, i);

		var inputStrsBackingBuf: [maxInputs][consts.u64MaxStrLen]u8 = undefined;
		var inputStrs: [maxInputs][]const u8 = undefined;
		for (0..maxInputs) |i| inputStrs[i] = std.fmt.bufPrint(&inputStrsBackingBuf[i], "{d}", .{inputs[i]}) catch unreachable;

		// max length of each u64 str + n (for each ';')
		var maxInputBuf: [(consts.u64MaxStrLen * maxInputs) + maxInputs]u8 = undefined;
		var index: usize = 0;

		var maxFormatBuf: [maxInputBuf.len + Enum.minLen]u8 = undefined;
		for (0..maxInputs) |i| {
			std.mem.copyForwards(u8, maxInputBuf[index..], inputStrs[i]);
			index += inputStrs[i].len;

			const str = std.fmt.bufPrint(&maxFormatBuf, consts.CSI ++ "{s}" ++ Enum.fnName, .{maxInputBuf[0..index]}) catch unreachable;
			try expect(try Enum.parse(str) == firstEnum);

			maxInputBuf[index] = ';';
			index += 1;
		}
	}

	// InsufficientLen
	// checks all lens less than min len and returns InsufficientLen
	{
		var buf: [Enum.minLen]u8 = undefined;
		for (0..Enum.minLen) |i| try expect(Enum.parse(buf[0..i]) == ParseErr.InsufficientLen);
	}

	// IncorrectFormat
	// checks that it will return IncorrectFormat if any format char is incorrect
	{
		const firstEnum: Enum = @enumFromInt(std.meta.fields(Enum)[0].value);
		const firstEnumStr = firstEnum.print();
		for (0..firstEnumStr.len) |i| {
			// ignore arguments
			if (i >= consts.CSI.len and i < firstEnumStr.len-Enum.fnName.len) continue;

			var copy = firstEnumStr;
			copy[i] = copy[i] +% 1;
			try expect(Enum.parse(&copy) == ParseErr.IncorrectFormat);
		}
	}

	// UnknownInt
	// checks that it will return UnknownInt for all numbers that are not valid values of the enum
	{
		var buf: [consts.u16MaxStrLen + Enum.minLen]u8 = undefined;

		for (0..std.math.maxInt(u16)+1) |i| {
			// number must not be a valid enum val
			if (std.meta.intToEnum(Enum, i) != std.meta.IntToEnumError.InvalidEnumTag) continue;

			const expectedErr = if (i <= std.math.maxInt(enumTagType)) ParseErr.UnknownInt else ParseErr.FirstIntOverflows;

			const str = std.fmt.bufPrint(&buf, consts.CSI ++ "{d}" ++ Enum.fnName, .{i}) catch unreachable;
			try expect(Enum.parse(str) == expectedErr);
		}
	}
}

test "SingularArg Enum" {
	try testSingularArg(NavKey);
	try testSingularArg(EraseDisplay);
	try testSingularArg(EraseLine);
	try testSingularArg(CursorStyle);
	try testSingularArg(DeviceStatusReport);
}
