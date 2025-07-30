const std = @import("std");
const consts = @import("consts.zig");
const expect = std.testing.expect;
const VariadicArgs = @import("variadicArgs.zig");
const stdout = std.io.getStdOut().writer();

const Pallet256Int:  u8 = 5;
const RGBInt:        u8 = 2;
const ForegroundInt: u8 = 38;
const BackgroundInt: u8 = 48;

pub const Opts = enum(u8) {
	bold            =  1,
	faint           =  2,
	italic          =  3,
	underline       =  4,
	blinking        =  5,
	inverse         =  7,
	hidden          =  8,
	strikethrough   =  9,
	doubleUnderline = 21,
};

// TODO?
// If xterm is compiled with the 16-color support disabled, it supports the following, from rxvt
// 100 - Set foreground and background color to default
pub const ResetOpts = enum(u8) {
	boldAndFaint  = 22,
	italic        = 23,
	underline     = 24,
	blinking      = 25,
	inverse       = 27,
	hidden        = 28,
	strikethrough = 29,
};

pub const Pallet8Fg = enum(u8) {
	black   = 30,
	red     = 31,
	green   = 32,
	yellow  = 33,
	blue    = 34,
	magenta = 35,
	cyan    = 36,
	white   = 37,
	default = 39,
};

pub const Pallet8Bg = enum(u8) {
	black   = 40,
	red     = 41,
	green   = 42,
	yellow  = 43,
	blue    = 44,
	magenta = 45,
	cyan    = 46,
	white   = 47,
	default = 49,
};

pub const AixtermPallet8Fg = enum(u8) {
	black   = 90,
	red     = 91,
	green   = 92,
	yellow  = 93,
	blue    = 94,
	magenta = 95,
	cyan    = 96,
	white   = 97,
};

pub const AixtermPallet8Bg = enum(u8) {
	black   = 100,
	red     = 101,
	green   = 102,
	yellow  = 103,
	blue    = 104,
	magenta = 105,
	cyan    = 106,
	white   = 107,
};

pub const ResetOpt = enum(u1) { unset = 0, set = 1 };

pub const Opt = enum(u2) { unset = 0, set = 1, reset = 2 };

pub const ColorType = enum(u3) { unset = 0, reset = 1, pallet8 = 2, aixtermPallet8 = 3, pallet256 = 4, rgb = 5 };

pub const Color = packed struct(u27) {
	colorType: ColorType = .unset,
	val:       u24       = 0,
};

const ResetColor: Color = .{.colorType = .reset};

const ParseColorErr = error {
	ColorFormatInvalidChar,
	Pallet256IntInvalidChar,
	RGBIntInvalidChar,
};

// there is weird behavior for ints > 255, which i assume is dependent upon the emulator implementation since i can't find anything about it in the spec
// i'm choosing to just coerce overflows to 0 and mod 256 everything else
fn parseColor(it: *VariadicArgs) !Color {
	// a copy is used to correctly handle advancing the main iter
	var itCopy = it.*;

	// parse format
	const formatOpt = itCopy.nextBetter(u3) catch |err| switch (err) {
			// invalidates the entire sequence
			VariadicArgs.PeekErr.InvalidCharacter => return error.ColorFormatInvalidChar,
			// it likely coerces to a color reset, but
			// empty will coerce to 0 which performs a full reset and the iter does not advance
			VariadicArgs.PeekErr.Empty => return ResetColor,
			// resets the color and the iter does not advance
			VariadicArgs.PeekErr.Overflow => return ResetColor,
	};

	// if the format is null the color is reset and the iter does not advance
	const format = formatOpt orelse return ResetColor;

	// resets the color and does not advance
	if (format != Pallet256Int and format != RGBInt) return ResetColor;

	if (format == Pallet256Int) {		
		const colorVal = itCopy.nextBetter(u16) catch |err| switch (err) {
			// coerces to 0
			VariadicArgs.PeekErr.Empty => 0,
			VariadicArgs.PeekErr.Overflow => 0,
			// invalidates the entire sequence
			VariadicArgs.PeekErr.InvalidCharacter => return error.Pallet256IntInvalidChar,
		};

		// if the val is null the color resets and the iter does not advance
		const val = colorVal orelse return ResetColor;

		// return valid color and advance the iter 2{format, color}
		it.advance(2);
		return .{.colorType = .pallet256, .val = @mod(val, 256)};
	}
	
	if (format == RGBInt) {
		var colors: [3]u16 = undefined;
		for (0..colors.len) |i| {
			const val = itCopy.nextBetter(u16) catch |err| switch (err) {
				// coerces to 0
				VariadicArgs.PeekErr.Empty => 0,
				VariadicArgs.PeekErr.Overflow => 0,
				// invalidates the entire sequence
				VariadicArgs.PeekErr.InvalidCharacter => return error.RGBIntInvalidChar,
			};

			// if there are not at least 3 ints following, reset the color and do not advance the iter
			colors[i] = val orelse return ResetColor; 
		}

		// return rgb and advance the iter 4{format, color, color, color}
		it.advance(4);
		var val: u24 = 0;
		val += @as(u24, @mod(colors[0], 256)) << 16;
		val += @as(u24, @mod(colors[1], 256)) << 8;
		val += @as(u24, @mod(colors[2], 256));
		return .{.colorType = .rgb, .val = val};
	}
	
	unreachable;
}

fn context(str: []const u8) void {
	_ = stdout.write("\x1b[m\x1b[1;4m") catch unreachable;
	_ = stdout.write(str) catch unreachable;
	_ = stdout.write("\x1b[m") catch unreachable;
	_ = stdout.write("\n") catch unreachable;
}

// three columns; reset graphics, preset graphics, args graphics
fn argsPrint(args: []const u8) void {
	_ = stdout.write("\x1b[m\t") catch unreachable;
	_ = stdout.write(args) catch unreachable;

	stdout.print("\x1b[{d}C", .{32-args.len}) catch unreachable;

	_ = stdout.write("\x1b[32;1;4;9m") catch unreachable;
	_ = stdout.write(args) catch unreachable;

	stdout.print("\x1b[{d}C", .{32-args.len}) catch unreachable;
	
	_ = stdout.write("\x1b[") catch unreachable;
	_ = stdout.write(args) catch unreachable;
	_ = stdout.write("m") catch unreachable;
	_ = stdout.write(args) catch unreachable;

	_ = stdout.write("\x1b[m\n\n") catch unreachable;
}

test parseColor {
	const debugPrint = false;

	const NextBetterRes = VariadicArgs.PeekErr!?u16;
	const testFormat = struct {
		name:             []const u8,
		str:              []const u8,
		parseColorExpect: ParseColorErr!Color,
		// unnecessary when error.InvalidCharacter is returned
		remainingExpect:  ?[]const NextBetterRes = null,
	};

	const tests = [_]testFormat{
		// color format
		.{
			.name = "no additional ints resets the color",
			.str = "38",
			.parseColorExpect = ResetColor,
		},
		.{
			.name = "invalidChar invalidates the entire sequence and does not advance the iter",
			.str = "38;5.",
			.parseColorExpect = error.ColorFormatInvalidChar,
		},
		.{
			.name = "overflow resets the color and does not advance the iter",
			.str = "38;999999",
			.parseColorExpect = ResetColor,
			.remainingExpect = &[_]NextBetterRes{error.Overflow}
		},
		.{
			.name = "not 5 or 2 resets the color and does not advance",
			.str = "38;3",
			.parseColorExpect = ResetColor,
			.remainingExpect = &[_]NextBetterRes{3}
		},
		.{
			.name = "empty coerces to 0, resets the color, and does not advance the iter. see ^",
			.str = "38;",
			.parseColorExpect = ResetColor,
			.remainingExpect = &[_]NextBetterRes{error.Empty},
		},

		// pallet256
		.{
			.name = "resets color and does not advance the iter",
			.str = "38;5",
			.parseColorExpect = ResetColor,
			.remainingExpect = &[_]NextBetterRes{5},
		},
		.{
			.name = "empty coerces to 0, pallet256 0 (i think)",
			.str = "38;5;",
			.parseColorExpect = .{.colorType = .pallet256},
		},
		.{
			.name = "pallet256 0",
			.str = "38;5;0",
			.parseColorExpect = .{.colorType = .pallet256},
		},
		.{
			.name = "pallet256 255",
			.str = "38;5;255",
			.parseColorExpect = .{.colorType = .pallet256, .val = 255},
		},
		.{
			.name = "modulo pallet256 0",
			.str = "38;5;256",
			.parseColorExpect = .{.colorType = .pallet256},
		},
		.{
			.name = "invalid char will invalidate the entire sequence",
			.str = "38;5;255.",
			.parseColorExpect = error.Pallet256IntInvalidChar,
		},
		
		// rgb
		.{
			.name = "resets color and does not advance the iter",
			.str = "38;2",
			.parseColorExpect = ResetColor,
			.remainingExpect = &[_]NextBetterRes{2},
		},
		.{
			.name = "resets color and does not advance the iter",
			.str = "38;2;",
			.parseColorExpect = ResetColor,
			.remainingExpect = &[_]NextBetterRes{2, error.Empty},
		},
		.{
			.name = "resets color and does not advance the iter",
			.str = "38;2;;",
			.parseColorExpect = ResetColor,
			.remainingExpect = &[_]NextBetterRes{2, error.Empty, error.Empty},
		},
		.{
			.name = "empty coerces to zero, returns rgb 0,0,0 (I think)",
			.str = "38;2;;;",
			.parseColorExpect = .{.colorType = .rgb},
		},
		.{
			.name = "rgb 0,0,0",
			.str = "38;2;0;0;0",
			.parseColorExpect = .{.colorType = .rgb},
		},
		.{
			.name = "rgb 255,255,255",
			.str = "38;2;255;255;255",
			.parseColorExpect = .{.colorType = .rgb, .val = (255 << 16) + (255 << 8) + 255},
		},
		.{
			.name = "modulo rgb 0,0,0",
			.str = "38;2;256;256;256",
			.parseColorExpect = .{.colorType = .rgb},
		},
		.{
			.name = "overflow rgb 0,0,0",
			.str = "38;2;999999;0;0",
			.parseColorExpect = .{.colorType = .rgb},
		},
		.{
			.name = "invalid char will invalidate the entire sequence",
			.str = "38;2;255.;255;255",
			.parseColorExpect = error.RGBIntInvalidChar,
		},
	};

	for (tests) |t| {
		if (debugPrint) {
			context(t.name);
			argsPrint(t.str);
		}
		
		var iter = VariadicArgs.init(t.str);
		_ = iter.nextBetter(u8) catch unreachable;

		// parseColor
		if (parseColor(&iter)) |res| try expect(res == try t.parseColorExpect)
		else |err| try expect(err == t.parseColorExpect);

		// remaining nextBetter
		if (t.remainingExpect) |re| {
			for (re) |r| {
				if (iter.nextBetter(u16)) |res| try expect(res == try r)
				else |err| try expect(err == r);
			}

			// last nextBetter should return null
			try expect(try iter.nextBetter(u16) == null);
		}
	}
}

// m(...x) -> color / graphics, where x either sets or resets and there are x combos for 8 & 24 bit color
pub const Graphics = packed struct(u73) {
	const Self = @This();
	const fnName:     [1]u8 = .{'m'};
	const default:    Self  = .{.reset = .set};
	const defaultStr: [3]u8 = consts.CSI ++ Self.fnName;
	const minLen:     usize = defaultStr.len;

	reset: ResetOpt = .unset, // 0 (default)

	bold:            Opt = .unset, // set 1, reset 22
	faint:           Opt = .unset, // set 2, reset 22
	italic:          Opt = .unset, // set 3, reset 23
	underline:       Opt = .unset, // set 4, reset 24
	blinking:        Opt = .unset, // set 5, reset 25
	inverse:         Opt = .unset, // set 7, reset 27
	hidden:          Opt = .unset, // set 8, reset 28
	strikethrough:   Opt = .unset, // set 9, reset 29
	doubleUnderline: Opt = .unset, // set 21

	// color can only be set once and will overwrite regardless of colorType
	fg: Color = .{},
	bg: Color = .{},

	pub const ParseErr = error{InvalidCharacter, InsufficientLen, IncorrectFormat} || ParseColorErr;

	pub fn parse(bytes: []const u8) ParseErr!Self {
		if (bytes.len < Self.minLen) return error.InsufficientLen;
		if (!std.mem.eql(u8, &consts.CSI, bytes[0..2])) return error.IncorrectFormat;
		if (!std.mem.eql(u8, &Self.fnName, bytes[bytes.len-Self.fnName.len..])) return error.IncorrectFormat;

		var out: Self = .{};

		// the m is ignored for parsing
		var it = VariadicArgs.init(bytes[2..bytes.len-1]);
		while (true) {
			const next = it.nextBetter(u8) catch |err| switch (err) {
				// empty coerces to 0, a full reset
				VariadicArgs.PeekErr.Empty => 0,
				// invalidates the entire sequence
				VariadicArgs.PeekErr.InvalidCharacter => return error.InvalidCharacter,
				// causes the remaining to be dropped
				VariadicArgs.PeekErr.Overflow => break,
			};

			switch (next orelse break) {
				// full reset
				0  => out = .{.reset = .set},

				// set
				1  => out.bold            = .set,
				2  => out.faint           = .set,
				3  => out.italic          = .set,
				4  => out.underline       = .set,
				5  => out.blinking        = .set,
				7  => out.inverse         = .set,
				8  => out.hidden          = .set,
				9  => out.strikethrough   = .set,
				21 => out.doubleUnderline = .set,
				
				// reset
				22 => {
					out.bold = .reset;
					out.faint = .reset;
				},
				23 => out.italic          = .reset,
				24 => out.underline       = .reset,
				25 => out.blinking        = .reset,
				27 => out.inverse         = .reset,
				28 => out.hidden          = .reset,
				29 => out.strikethrough   = .reset,

				// pallet8
				30...37, 39 => |val| out.fg = .{.colorType = .pallet8, .val = val},
				40...47, 49 => |val| out.bg = .{.colorType = .pallet8, .val = val},

				// aixterm bright/bold pallet8
				90...97   => |val| out.fg = .{.colorType = .aixtermPallet8, .val = val},
				100...107 => |val| out.bg = .{.colorType = .aixtermPallet8, .val = val},

				// 38;5;{color}m     foreground pallet256
				// 38;2;{r};{g};{b}m foreground rgb
				ForegroundInt => out.fg = try parseColor(&it),

				// 48;5;{color}m     background pallet256
				// 48;2;{r};{g};{b}m background rgb
				BackgroundInt => out.bg = try parseColor(&it),

				// causes the remaining to be dropped
				else => break,
			}
		}

		// all dropped must still be valid
		while (true) {
			_ = (it.nextBetter(u8) catch |err| switch (err) {
				// invalidates the entire sequence
				VariadicArgs.PeekErr.InvalidCharacter => return error.InvalidCharacter,
				else => continue,
			}) orelse break;
		}

		// no values were set, the default is to reset
		if (out == Self{}) out.reset = .set;

		return out;
	}

	//pub fn apply(self: @This(), writer: anytype) !usize {
		//return writer.write(self.val[0..self.len]);
	//}

	//pub fn print(self: @This(), writer: anytype, comptime format: []const u8, args: anytype) !void {
		//_ = try writer.write(self.val[0..self.len]);
		//try writer.print(format, args);
		//_ = try writer.write(modeReset);
	//}
	
	//pub fn write(self: @This(), writer: anytype, bytes: []const u8) !usize {
		//var sum: usize = 0;
		//sum += try writer.write(self.val[0..self.len]);
		//sum += try writer.write(bytes);
		//sum += try writer.write(modeReset);
		//return sum;
	//}
};

pub const ResetGraphics: Graphics = Graphics.default;

test Graphics {
	// default
	try expect(try Graphics.parse(&Graphics.defaultStr) == Graphics.default);

	// TODO also print
	// every field parses and prints
	// enum -> bytes -> parse(src) -> print (bytes) -> parse (out)
	// ensures there is no data loss between conversions for all valid values

	const ParsePrintOptsTest = struct {
		optEnum:     type,
		expectedVal: Opt,
	};
	const parsePrintOptsTests = [_]ParsePrintOptsTest{
		.{.optEnum = Opts, .expectedVal = .set},
		.{.optEnum = ResetOpts, .expectedVal = .reset},
	};
	inline for (parsePrintOptsTests) |ppt| {
		inline for (std.meta.fields(ppt.optEnum)) |f| {
			var buf: [Graphics.defaultStr.len + consts.u8MaxStrLen]u8 = undefined;
			const bytes = std.fmt.bufPrint(&buf, "\x1b[{d}m", .{f.value}) catch unreachable;

			// check correct field is set
			var val = Graphics.parse(bytes) catch unreachable;
			if (f.value == @intFromEnum(ResetOpts.boldAndFaint)) {
				try expect(val.bold == ppt.expectedVal);
				try expect(val.faint == ppt.expectedVal);
			}
			else try expect(@field(val, f.name) == ppt.expectedVal);

			// check every other field is unset
			if (f.value == @intFromEnum(ResetOpts.boldAndFaint)) {
				val.bold = .unset;
				val.faint = .unset;
			}
			else @field(val, f.name) = .unset;
			try expect(val == Graphics{});
		}
	}

	const ParsePrintPallet8Test = struct {
		palletEnum:        type,
		expectedColorType: ColorType,
		isFg:              bool,
	};

	const parsePrintPallet8Tests = [_]ParsePrintPallet8Test{
		.{.palletEnum = Pallet8Fg, .expectedColorType = .pallet8, .isFg = true},
		.{.palletEnum = Pallet8Bg, .expectedColorType = .pallet8, .isFg = false},
		.{.palletEnum = AixtermPallet8Fg, .expectedColorType = .aixtermPallet8, .isFg = true},
		.{.palletEnum = AixtermPallet8Bg, .expectedColorType = .aixtermPallet8, .isFg = false},
	};
	inline for (parsePrintPallet8Tests) |pppt| {
		inline for (std.meta.fields(pppt.palletEnum)) |f| {
			var buf: [Graphics.defaultStr.len + consts.u8MaxStrLen]u8 = undefined;
			const bytes = std.fmt.bufPrint(&buf, "\x1b[{d}m", .{f.value}) catch unreachable;

			// check correct field is set
			var val = Graphics.parse(bytes) catch unreachable;
			if (pppt.isFg) {
				try expect(val.fg.colorType == pppt.expectedColorType);
				try expect(val.fg.val == f.value);
			}
			else {
				try expect(val.bg.colorType == pppt.expectedColorType);
				try expect(val.bg.val == f.value);
			}

			// check every other field is unset
			if (pppt.isFg) val.fg = .{} else val.bg = .{};
			try expect(val == Graphics{});
		}
	}
	
	for (0..std.math.maxInt(u8)+1) |i| {
		for ([2]u8{ForegroundInt, BackgroundInt}) |bgFg| {
			var buf: [Graphics.defaultStr.len + consts.u8MaxStrLen + 5]u8 = undefined;
			const bytes = std.fmt.bufPrint(&buf, "\x1b[{d};5;{d}m", .{bgFg, i}) catch unreachable;

			// check correct field is set
			var val = Graphics.parse(bytes) catch unreachable;
			if (bgFg == ForegroundInt) {
				try expect(val.fg.colorType == .pallet256);
				try expect(val.fg.val == i);
			}
			else {
				try expect(val.bg.colorType == .pallet256);
				try expect(val.bg.val == i);
			}

			// check every other field is unset
			if (bgFg == ForegroundInt) val.fg = .{} else val.bg = .{};
			try expect(val == Graphics{});			
		}
	}
}
