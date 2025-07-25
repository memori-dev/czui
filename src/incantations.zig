const std = @import("std");
const stdout = std.io.getStdOut().writer();
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectErr = std.testing.expectError;

const ESC: u8 = 27;
const CSI: [2]u8 = .{ESC, '['};
const ASCIIIntOffset: u8 = 48;
const u64MaxStrLen: usize = 20;
const u16MaxStrLen: usize = 5;

fn allCharsAreNumeric(bytes: []const u8) bool {
	for (0..bytes.len) |i| if (bytes[i] < ASCIIIntOffset or bytes[i] > ASCIIIntOffset + 9) return false;
	return true;
}

// these hold true for enums (one parameter) and structs (variadic parameter)
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

// TODO merge parseFirstIterator
//// fn to init, parse first int, and validate every int
const IntParserIterator = struct {
	const Self = @This();

	it: std.mem.SplitIterator(u8, .sequence),

	fn next(self: *Self, comptime T: type) error{InvalidCharacter}!?T {
		while (self.it.next()) |str| {
			if (str.len == 0) continue;

			return std.fmt.parseInt(T, str, 10) catch |err| {
				// only invalid ints will cause an error
				if (err == error.InvalidCharacter) return error.InvalidCharacter
				else continue;
			};
		}
		
		return null;
	}

	fn init(bytes: []const u8) !Self {
		if (bytes.len == 0) return error.NoArguments;
		return .{.it = std.mem.splitSequence(u8, bytes, ";")};
	}
};

const ParseErr = error {
	InsufficientLen,
	IncorrectFormat,
	NoDefault,
	InvalidInt,
};

fn parseEnum(comptime Enum: type, bytes: []const u8) ParseErr!Enum {
	if (bytes.len < Enum.minLen) return error.InsufficientLen;
	if (!std.mem.eql(u8, &CSI, bytes[0..2])) return error.IncorrectFormat;
	if (!std.mem.eql(u8, &Enum.fnName, bytes[bytes.len-Enum.fnName.len..])) return error.IncorrectFormat;

	// empty, default should never be null as the minLen check would fail otherwise
	if (bytes.len-Enum.fnName.len-2 == 0) return Enum.default orelse unreachable;

	if (parseFirstInteger(u3, bytes[2..bytes.len-Enum.fnName.len])) |val| {
		if (std.meta.intToEnum(Enum, val)) |out| return out
		else |_| {}
	}

	return error.InvalidInt;
}

fn print(comptime Enum: type, val: Enum) [3 + Enum.fnName.len]u8 {
	return CSI ++ .{@intFromEnum(val) + ASCIIIntOffset} ++ Enum.fnName;
}

pub const CursorStyle = enum(u3) {
	const Self = @This();

	// the space is required
	pub const fnName: [2]u8  = .{' ', 'q'};
	const default:    ?Self  = .blinkingBlockDefault;
	const defaultStr: ?[4]u8 = CSI ++ Self.fnName;
	const minLen:     usize  = Self.defaultStr.?.len;

	blinkingBlock        = 0,
	blinkingBlockDefault = 1,
	steadyBlock          = 2,
	blinkingUnderline    = 3,
	steadyUnderline      = 4,
	blinkingBar          = 5,
	steadyBar            = 6,
};

pub const EraseDisplay = enum(u2) {
	const Self = @This();

	pub const fnName: [1]u8  = .{'J'};
	const default:    ?Self  = Self.cursorToEnd;
	const defaultStr: ?[3]u8 = CSI ++ Self.fnName;
	const minLen:     usize  = Self.defaultStr.?.len;

	// end of screen
	cursorToEnd  = 0,
	// beginning of screen
	cursorToHome = 1,
	all          = 2,
	// scrollback
	savedLines   = 3,
};

pub const EraseLine = enum(u2) {
	const Self = @This();

	pub const fnName: [1]u8  = .{'K'};
	const default:    ?Self  = Self.cursorToEnd;
	const defaultStr: ?[3]u8 = CSI ++ Self.fnName;
	const minLen:     usize  = Self.defaultStr.?.len;

	cursorToEnd   = 0,
	cursorToStart = 1,
	entire        = 2,
	// scrollback
	saved         = 3,
};

pub const DeviceStatusReport = enum(u3) {
	const Self = @This();

	pub const fnName: [1]u8  = .{'K'};
	const default:    ?Self  = null;
	const defaultStr: ?[0]u8 = null;
	const minLen:     usize  = CSI.len + 1 + Self.fnName.len;

	statusReport   = 5,
	cursorPosition = 6,
};

const SetResetMode = @import("_genIncantations.zig").SetResetMode;

const PrivateMode = @import("_genIncantations.zig").PrivateMode;

// all unsigned ints have a default value of 1
pub const EscSeq = union(enum) {
	// @(?x) - insert x (default 1) blank chars
	insertBlankChars: u16,
	// L(?x) - insert x (default 1) blank lines above
	insertBlankLines: u16,


	// A(?x) - move cursor up x (default 1) rows
	moveCursorUp: u16,
	// TODO: CSI Ps e, is apparently the same fn but didnt work
	// B(?x) - move cursor down x (default 1) rows
	moveCursorDown: u16,
	// C(?x) - move cursor right x (default 1) cols
	moveCursorRight: u16,
	// D(?x) - move cursor left x (default 1) cols
	moveCursorLeft: u16,


	// E(?x) - move cursor to start of next line, x (default 1) lines down
	moveCursorToStartOfNextLine: u16,
	// F(?x) - moves cursor to start of prev line, x (default 1) lines up
	// TODO this and the 'end' key have a collision, but don't do the same thing
	// TODO im also seeing 'end' being SS3 instead of CSI, but isn't the case when testing
	moveCursorToStartOfPrevLine: u16,


	// G(?x) - moves cursor to column x (default 1)
	moveCursorAbsCol: u16,
	// d(?x) - moves cursor to row x (default 1)
	moveCursorAbsRow: u16,


	// H(?y, ?x) - move cursor to y (default 1), x (default 1)
	// f(?y, ?x) - move cursor to y (default 1), x (default 1)
	moveCursorAbs: struct{u16, u16},


	// I(?x) - Cursor Forward Tabulation x (default 1) tab stops
	cursorForwardTabulation: u16,
	// Z(?x) - cursor backward tabulation x (default 1) tab stops
	cursorBackwardTabulation: u16,


	// TODO vt220 "ESC[?xJ" variant?
	// J(?x)
	eraseDisplay: EraseDisplay,
	// TODO vt220 "ESC[?xK" variant?
	// K(?x)
	eraseLine: EraseLine,


	// X(?x) -> erase x (default 1) chars on current line
	eraseChars: u16,


	// M(?x) -> delete x (default 1) lines
	deleteLines: u16,
	// P(?x) -> delete x (default 1) chars on current line
	deleteChars: u16,


	// S(?x) -> scroll up x (default 1) lines
	scrollUp: u16,
	// T(?x) -> scroll down x (default 1) lines
	scrollDown: u16,


	// b(?x) -> repeat preceeding char x (default 1) times
	repeatPreceedingChar: u16,


	// "{h/l}(...x)"
	setResetMode: SetResetMode,
	// "{h/l}(?, ...x)"
	privateMode: PrivateMode,
	// TODO i dont see any results from this and there were no changes when trying reported x values
	//// "\x1b[={x}{h/l}" -> (un)set screen mode
	//screenMode: ScreenMode,


	// m(...x) -> sets graphics dependant upon x (default 0)
	//graphics: Graphics,


	// n(x)
	deviceStatusReport: DeviceStatusReport,


	// " q"(?x)
	setCursorStyle: CursorStyle,


	// s() -> save cursor position
	saveCursorPosition: void,
	// u() -> restores the cursor to the last saved position
	restoreCursorPosition: void,
};

fn testHighLowSwapArgOrder(comptime Spec: type, comptime Struct: type, comptime sizeOf: usize, in: [sizeOf]u8, len: usize) ![sizeOf]u8 {
	const specTagType = @typeInfo(Spec).@"enum".tag_type;
	var out = in;
	const start = if (Struct.postCSIChar != null) 3 else 2;
	var it = IntParserIterator.init(in[start..len-1]) catch unreachable;
	const first = (try it.next(specTagType)).?;
	const second = (try it.next(specTagType)).?;

	var index: usize = start;
	index += (try std.fmt.bufPrint(out[index..], "{d}", .{second})).len;
	out[index] = ';';
	index += 1;
	index += (try std.fmt.bufPrint(out[index..], "{d}", .{first})).len;

	try expect((try it.next(specTagType)) == null);

	return out;
}

// struct (src) -> print (bytes) -> parse (out) -> print (outBytes)
// ensures there is no data loss between conversions for all valid values
fn testHighLowParsePrint(comptime Struct: type, src: Struct) !void {
	const bytes, const len = src.print();
				
	const out = try Struct.parse(bytes[0..len]);
	const outBytes, const outLen = out.print();

	try expect(src == out);
	try expect(len == outLen);
	try expect(std.mem.eql(u8, &bytes, &outBytes));
}

// TODO have this take in isHigh as an arg to easily test both without needing to implement it in each sub-test
fn testHighLow(comptime Spec: type, comptime Struct: type) !void {
	const specBackingType = @typeInfo(Spec).@"enum".tag_type;

	// every field parses and prints
	inline for (std.meta.fields(Spec)) |field| {
		for ([2]bool{true, false}) |isHigh| {
			var src: Struct = .{.isHigh = isHigh};
			@field(src, field.name) = true;

			try testHighLowParsePrint(Struct, src);
		}
	}

	// multiple:
	//// tests that two arguments are valid
	//// tests that order does not affect the output (also makes the last test combinations instead of permutations)
	//// tests all combinations for:
	////// an increase in value when setting additional properties to true
	////// uniqueness
	////// testHighLowParsePrint
	{
		const backingType = @typeInfo(Struct).@"struct".backing_integer.?;
		// two are valid
		const one = std.meta.fields(Spec)[0];
		const two = std.meta.fields(Spec)[1];

		var srcOne: Struct = .{.isHigh = false};
		@field(srcOne, one.name) = true;
		
		var srcTwo: Struct = .{.isHigh = false};
		@field(srcTwo, two.name) = true;

		var srcBoth: Struct = .{.isHigh = false};
		@field(srcBoth, one.name) = true;
		@field(srcBoth, two.name) = true;

		const oneBits: backingType = @bitCast(srcOne);
		const twoBits: backingType = @bitCast(srcTwo);
		const bothBits: backingType = @bitCast(srcBoth);

		try expect(oneBits != twoBits and oneBits != bothBits and twoBits != bothBits);
		try expect(bothBits > oneBits and bothBits > twoBits);
		try expect(bothBits == oneBits | twoBits and bothBits ^ oneBits ^ twoBits == 0);

		try testHighLowParsePrint(Struct, srcBoth);

		// order doesn't matter
		const outBytes, const outLen = srcBoth.print();
		const swap = try testHighLowSwapArgOrder(Spec, Struct, @sizeOf(@TypeOf(outBytes)), outBytes, outLen);
		try expect(!std.mem.eql(u8, &outBytes, &swap));

		try testHighLowParsePrint(Struct, try Struct.parse(swap[0..outLen]));

		// test combinations by iterating and making each true one at a time
		const totalCombinations = (std.meta.fields(Spec).len + 1) * @round(@as(f32, @floatFromInt(std.meta.fields(Spec).len)) / 2);
		var combinationBits: [totalCombinations]backingType = @splat(0);
		var index: usize = 0;
		@setEvalBranchQuota(5000);
		inline for (std.meta.fields(Spec), 1..) |start, i| {
			var multiple: Struct = .{.isHigh = false};
			@field(multiple, start.name) = true;

			inline for (std.meta.fields(Spec)[i..]) |proceeding| {
				const lastBits: backingType = @bitCast(multiple);
				@field(multiple, proceeding.name) = true;

				const currBits: backingType = @bitCast(multiple);

				try expect(lastBits != currBits);
				try expect(currBits > lastBits);
				try expect(std.mem.indexOfScalar(backingType, &combinationBits, currBits) == null);
				try testHighLowParsePrint(Struct, multiple);

				combinationBits[index] = currBits;
				index += 1;
			}
		}
	}

	// InsufficientLen
	// checks all lens less than min len and returns InsufficientLen
	{
		var buf: [Struct.minLen]u8 = undefined;
		for (0..Struct.minLen) |i| try expectErr(error.InsufficientLen, Struct.parse(buf[0..i]));
	}

	// IncorrectFormat
	// checks that it will return IncorrectFormat if any format char is incorrect
	{
		const emptyStruct, const emptyLen = Struct.print(Struct{.isHigh = true});
		for (0..emptyLen) |i| {
			var copy = emptyStruct;
			copy[i] = copy[i] +% 1;
			try expectErr(error.IncorrectFormat, Struct.parse(&copy));
		}
	}

	// InvalidInt
	//// unknown ints are ignored
	//// numbers out of range are ignored
	//// empty are valid and ignored
	//// non-numeric chars cause an error
	// TODO tests these ints before, inbetween, and after valid ints
	{
		// if this expect fails then the buffer likely will not be large enough
		try expect(std.math.maxInt(specBackingType) <= std.math.maxInt(u16));
		var buf: [u16MaxStrLen + Struct.minLen]u8 = undefined;
		const fmt = CSI ++ (if (Struct.postCSIChar) |val| [1]u8{val} else [0]u8{}) ++ "{d}h";
		
		// unknown ints are ignored
		for (0..std.math.maxInt(specBackingType)+1) |i| {
			// number must not be a valid Spec enum val
			if (std.meta.intToEnum(Spec, i) != std.meta.IntToEnumError.InvalidEnumTag) continue;

			const str = std.fmt.bufPrint(&buf, fmt, .{i}) catch unreachable;
			try expectErr(error.NoValidArguments, Struct.parse(str));
		}

		// numbers out of range are ignored
		for (std.math.maxInt(specBackingType)+1..std.math.maxInt(u16)+1) |i| {
			// number must not be a valid Spec enum val
			try expect(std.meta.intToEnum(Spec, i) == std.meta.IntToEnumError.InvalidEnumTag);

			const str = std.fmt.bufPrint(&buf, fmt, .{i}) catch unreachable;
			try expectErr(error.NoValidArguments, Struct.parse(str));
		}

		// empty are valid and ignored
		try expectErr(error.NoValidArguments, Struct.parse(CSI ++ (if (Struct.postCSIChar) |val| [1]u8{val} else [0]u8{}) ++ ";;h"));

		// non-numeric chars cause an error
		const charFmt = CSI ++ (if (Struct.postCSIChar) |val| [1]u8{val} else [0]u8{}) ++ "{c}h";
		for (0..std.math.maxInt(u8)+1) |i| {
			// ignore 0-9
			if (i >= 48 and i <= 57) continue;
			// ignore ;
			if (i == ';') continue;

			const str = std.fmt.bufPrint(&buf, charFmt, .{@as(u8, @truncate(i))}) catch unreachable;
			try expectErr(error.InvalidCharacter, Struct.parse(str));
		}
	}

	// TODO No valid arguments
	//// empty, unknown, and out of range ints in any combination should return this error

}

fn testEnum(comptime Enum: type) !void {
	// default
	{
		if (Enum.default) |default| {
			try expect(Enum.defaultStr != null);
			try expect(try parseEnum(Enum, &Enum.defaultStr.?) == default);
		}
		else try expect(Enum.defaultStr == null);
	}

	// every field parses and prints
	// enum (src) -> print (bytes) -> parse (out) -> print (outBytes)
	// ensures there is no data loss between conversions for all valid values
	inline for (std.meta.fields(Enum)) |f| {
		const src: Enum = @enumFromInt(f.value);
		const bytes = print(Enum, src);
		
		const out = try parseEnum(Enum, &bytes);
		const outBytes = print(Enum, out);
		
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

		var inputStrsBackingBuf: [maxInputs][u64MaxStrLen]u8 = undefined;
		var inputStrs: [maxInputs][]const u8 = undefined;
		for (0..maxInputs) |i| inputStrs[i] = std.fmt.bufPrint(&inputStrsBackingBuf[i], "{d}", .{inputs[i]}) catch unreachable;

		// max length of each u64 str + n (for each ';')
		var maxInputBuf: [(u64MaxStrLen * maxInputs) + maxInputs]u8 = undefined;
		var index: usize = 0;

		var maxFormatBuf: [maxInputBuf.len + Enum.minLen]u8 = undefined;
		for (0..maxInputs) |i| {
			std.mem.copyForwards(u8, maxInputBuf[index..], inputStrs[i]);
			index += inputStrs[i].len;

			const str = std.fmt.bufPrint(&maxFormatBuf, CSI ++ "{s}" ++ Enum.fnName, .{maxInputBuf[0..index]}) catch unreachable;
			try expect(try parseEnum(Enum, str) == firstEnum);

			maxInputBuf[index] = ';';
			index += 1;
		}
	}

	// InsufficientLen
	// checks all lens less than min len and returns InsufficientLen
	{
		var buf: [Enum.minLen]u8 = undefined;
		for (0..Enum.minLen) |i| try expectErr(ParseErr.InsufficientLen, parseEnum(Enum, buf[0..i]));
	}

	// IncorrectFormat
	// checks that it will return IncorrectFormat if any format char is incorrect
	{
		const firstEnumVal = print(Enum, @enumFromInt(std.meta.fields(Enum)[0].value));
		for (0..firstEnumVal.len) |i| {
			// ignore arguments
			if (i >= CSI.len and i < firstEnumVal.len-Enum.fnName.len) continue;

			var copy = firstEnumVal;
			copy[i] = copy[i] +% 1;
			try expectErr(ParseErr.IncorrectFormat, parseEnum(Enum, &copy));
		}
	}

	// InvalidInt
	// checks that it will return InvalidInt for all numbers that are not valid values of the enum
	{
		var buf: [u16MaxStrLen + Enum.minLen]u8 = undefined;

		for (0..std.math.maxInt(u16)+1) |i| {
			// number must not be a valid enum val
			if (std.meta.intToEnum(Enum, i) != std.meta.IntToEnumError.InvalidEnumTag) continue;

			const str = std.fmt.bufPrint(&buf, CSI ++ "{d}" ++ Enum.fnName, .{i}) catch unreachable;
			try expectErr(ParseErr.InvalidInt, parseEnum(Enum, str));
		}
	}
}

test "HighLow" {
	const incantationSpec = @import("incantationSpec.zig");
	const SetResetModeSpec = incantationSpec.SetResetMode;
	const PrivateModeSpec = incantationSpec.PrivateMode;

	try testHighLow(SetResetModeSpec, SetResetMode);
	try testHighLow(PrivateModeSpec, PrivateMode);
}

test "Enums" {
	try testEnum(EraseDisplay);
	try testEnum(EraseLine);
	try testEnum(CursorStyle);
	try testEnum(DeviceStatusReport);
}