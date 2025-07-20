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

const ParseErr = error {
	InsufficientLen,
	IncorrectFormat,
	NoDefault,
	InvalidInt,
};

fn parse(comptime Enum: type, bytes: []const u8) ParseErr!Enum {
	if (bytes.len < Enum.defaultStr.len) return error.InsufficientLen;
	if (!std.mem.eql(u8, &CSI, bytes[0..2])) return error.IncorrectFormat;
	if (!std.mem.eql(u8, &Enum.fnName, bytes[bytes.len-Enum.fnName.len..])) return error.IncorrectFormat;

	// empty
	if (bytes.len-Enum.fnName.len-2 == 0) {
		if (Enum.default) |val| return val
		else return error.NoDefault;
	}

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
	pub const fnName: [2]u8 = .{' ', 'q'};
	const default:    ?Self = .blinkingBlockDefault;
	const defaultStr: [4]u8 = CSI ++ Self.fnName;

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

	pub const fnName: [1]u8 = .{'J'};
	const default:    ?Self = Self.cursorToEnd;
	const defaultStr: [3]u8 = CSI ++ Self.fnName;

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

	pub const fnName: [1]u8 = .{'K'};
	const default:    ?Self = Self.cursorToEnd;
	const defaultStr: [3]u8 = CSI ++ Self.fnName;

	cursorToEnd   = 0,
	cursorToStart = 1,
	entire        = 2,
	// scrollback
	saved         = 3,
};

pub const DeviceStatusReport = enum(u3) {
	const Self = @This();

	pub const fnName: [1]u8 = .{'K'};
	const default:    ?Self = null;
	const defaultStr: [3]u8 = CSI ++ Self.fnName;

	statusReport   = 5,
	cursorPosition = 6,
};

// TODO pull uXs into their own type for testing (consider making a fn to return this type)
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


	// h(x) -> high (set)
	// l(x) -> low  (unset)
	//// "\x1b[{x}{h/l}" -> (re)set mode
	//resetMode: ResetMode,
	// TODO i dont see any results from this and there were no changes when trying reported x values
	//// "\x1b[={x}{h/l}" -> (un)set screen mode
	//screenMode: ScreenMode,
	//// "\x1b[?{x}{h/l}" -> (un)set private modes
	//privateMode: PrivateMode,


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

fn testEnum(comptime Enum: type) !void {
	// default
	{
		const res = parse(Enum, &Enum.defaultStr);
		if (Enum.default) |val| try expect(val == Enum.default)
		else try expect(res == ParseErr.NoDefault);
	}

	// every field parses and prints
	// enum (src) -> print (bytes) -> parse (out) -> print (outBytes)
	// ensures there is no data loss between conversions for all valid values
	inline for (std.meta.fields(Enum)) |f| {
		const src: Enum = @enumFromInt(f.value);
		const bytes = print(Enum, src);
		
		const out = try parse(Enum, &bytes);
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

		var maxFormatBuf: [maxInputBuf.len + Enum.defaultStr.len]u8 = undefined;
		for (0..maxInputs) |i| {
			std.mem.copyForwards(u8, maxInputBuf[index..], inputStrs[i]);
			index += inputStrs[i].len;

			const str = std.fmt.bufPrint(&maxFormatBuf, CSI ++ "{s}" ++ Enum.fnName, .{maxInputBuf[0..index]}) catch unreachable;
			try expect(try parse(Enum, str) == firstEnum);

			maxInputBuf[index] = ';';
			index += 1;
		}
	}

	// InsufficientLen
	// checks all lens less than min len and returns InsufficientLen
	{
		var buf: [Enum.defaultStr.len]u8 = undefined;
		for (0..Enum.defaultStr.len) |i| try expectErr(ParseErr.InsufficientLen, parse(Enum, buf[0..i]));
	}

	// IncorrectFormat
	// checks that it will return IncorrectFormat if any format char is incorrect
	{
		for (0..Enum.defaultStr.len) |i| {
			var defaultCopy = Enum.defaultStr;
			defaultCopy[i] = defaultCopy[i] +% 1;
			try expectErr(ParseErr.IncorrectFormat, parse(Enum, &defaultCopy));
		}
	}

	// InvalidInt
	// checks that it will return InvalidInt for all numbers that are not valid values of the enum
	{
		var buf: [u16MaxStrLen + Enum.defaultStr.len]u8 = undefined;

		for (0..std.math.maxInt(u16)+1) |i| {
			// number must not be a valid enum val
			if (std.meta.intToEnum(Enum, i) != std.meta.IntToEnumError.InvalidEnumTag) continue;

			const str = std.fmt.bufPrint(&buf, CSI ++ "{d}" ++ Enum.fnName, .{i}) catch unreachable;
			try expectErr(ParseErr.InvalidInt, parse(Enum, str));
		}
	}
}

test "EscSeq" {
	try testEnum(EraseDisplay);
	try testEnum(EraseLine);
	try testEnum(CursorStyle);
	try testEnum(DeviceStatusReport);
}