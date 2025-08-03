const std = @import("std");
const consts = @import("consts.zig");
const expect = std.testing.expect;
const VariadicArgs = @import("variadicArgs.zig");
const stdout = std.io.getStdOut().writer();
const assert = std.debug.assert;

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

pub const UnsetSet = enum(u1) { unset = 0, set = 1 };

pub const UnsetSetReset = enum(u2) { unset = 0, set = 1, reset = 2 };

pub const ColorType = enum(u3) { unset = 0, reset = 1, pallet8 = 2, aixtermPallet8 = 3, pallet256 = 4, rgb = 5 };

pub const Color = packed struct(u27) {
	type: ColorType = .unset,
	val:  u24       = 0,
};

const ResetColor: Color = .{.type = .reset};

const ParseColorErr = error {
	ColorFormatInvalidChar,
	ColorFormatOverflow,
	Pallet256IntInvalidChar,
	Pallet256IntOverflow,
	RGBIntInvalidChar,
	RGBIntOverflow,
};

// empty is coerced to 0
// 38/48 (fg/bg) and a non 2/5 (pallet256/rgb), including null, proceeding int will coerce to a color reset
// overflow is an error and will invalidate the entire sequence
// if insufficent args are presented, for both pallet256 or rgb, then the color is reset and the iter does not advance
fn parseColor(it: *VariadicArgs) !Color {
	// a copy is used to correctly handle advancing the main iter
	var itCopy = it.*;

	// parse format
	const formatOpt = itCopy.nextBetter(u8) catch |err| switch (err) {
			// it likely coerces to a color reset, but
			// empty will coerce to 0 which performs a full reset and the iter does not advance
			VariadicArgs.PeekErr.Empty => return ResetColor,
			// invalidates the entire sequence
			VariadicArgs.PeekErr.InvalidCharacter => return error.ColorFormatInvalidChar,
			VariadicArgs.PeekErr.Overflow => return error.ColorFormatOverflow,
	};

	// if the format is null the color is reset and the iter does not advance
	const format = formatOpt orelse return ResetColor;

	// resets the color and does not advance
	if (format != Pallet256Int and format != RGBInt) return ResetColor;

	if (format == Pallet256Int) {		
		const colorVal = itCopy.nextBetter(u8) catch |err| switch (err) {
			// coerces to 0
			VariadicArgs.PeekErr.Empty => 0,
			// invalidates the entire sequence
			VariadicArgs.PeekErr.InvalidCharacter => return error.Pallet256IntInvalidChar,
			VariadicArgs.PeekErr.Overflow => return error.Pallet256IntOverflow,
		};

		// if the val is null the color resets and the iter does not advance
		const val = colorVal orelse return ResetColor;

		// return valid color and advance the iter 2{format, color}
		it.advance(2);
		return .{.type = .pallet256, .val = val};
	}
	
	if (format == RGBInt) {
		var colors: [3]u8 = undefined;
		for (0..colors.len) |i| {
			const val = itCopy.nextBetter(u8) catch |err| switch (err) {
				// coerces to 0
				VariadicArgs.PeekErr.Empty => 0,
				// invalidates the entire sequence
				VariadicArgs.PeekErr.InvalidCharacter => return error.RGBIntInvalidChar,
				VariadicArgs.PeekErr.Overflow => return error.RGBIntOverflow,
			};

			// if there are not at least 3 ints following, reset the color and do not advance the iter
			colors[i] = val orelse return ResetColor; 
		}

		// return rgb and advance the iter 4{format, color, color, color}
		it.advance(4);
		const val: u24 = (@as(u24, colors[0]) << 16) + (@as(u24, colors[1]) << 8) + @as(u24, colors[2]);
		return .{.type = .rgb, .val = val};
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

// TODO testing of entire input space given updated constraints
test parseColor {
	const debugPrint = false;

	const NextBetterRes = VariadicArgs.PeekErr!?u8;
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
			.parseColorExpect = error.ColorFormatOverflow,
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
			.parseColorExpect = .{.type = .pallet256},
		},
		.{
			.name = "pallet256 0",
			.str = "38;5;0",
			.parseColorExpect = .{.type = .pallet256},
		},
		.{
			.name = "pallet256 255",
			.str = "38;5;255",
			.parseColorExpect = .{.type = .pallet256, .val = 255},
		},
		.{
			.name = "invalid char will invalidate the entire sequence",
			.str = "38;5;255.",
			.parseColorExpect = error.Pallet256IntInvalidChar,
		},
		.{
			.name = "pallet256 overflow",
			.str = "38;5;256",
			.parseColorExpect = error.Pallet256IntOverflow,
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
			.parseColorExpect = .{.type = .rgb},
		},
		.{
			.name = "rgb 0,0,0",
			.str = "38;2;0;0;0",
			.parseColorExpect = .{.type = .rgb},
		},
		.{
			.name = "rgb 255,255,255",
			.str = "38;2;255;255;255",
			.parseColorExpect = .{.type = .rgb, .val = (255 << 16) + (255 << 8) + 255},
		},
		.{
			.name = "rgb overflow 256,256,256",
			.str = "38;2;256;256;256",
			.parseColorExpect = error.RGBIntOverflow,
		},
		.{
			.name = "rgb overflow 999999,0,0",
			.str = "38;2;999999;0;0",
			.parseColorExpect = error.RGBIntOverflow,
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
				if (iter.nextBetter(u8)) |res| try expect(res == try r)
				else |err| try expect(err == r);
			}

			// last nextBetter should return null
			try expect(try iter.nextBetter(u8) == null);
		}
	}
}

// m(...x) -> color / graphics, where x either sets or resets and there are x combos for 8 & 24 bit color
pub const Graphics = packed struct(u72) {
	const Self = @This();
	const fnName:     [1]u8 = .{'m'};
	const default:    Self  = .{.reset = .set};
	const defaultStr: [3]u8 = consts.CSI ++ Self.fnName;
	const minLen:     usize = defaultStr.len;

	reset: UnsetSet = .unset, // 0 (default)

	bold:            UnsetSetReset = .unset, // set 1, reset 22
	faint:           UnsetSetReset = .unset, // set 2, reset 22
	italic:          UnsetSetReset = .unset, // set 3, reset 23
	underline:       UnsetSetReset = .unset, // set 4, reset 24
	blinking:        UnsetSetReset = .unset, // set 5, reset 25
	inverse:         UnsetSetReset = .unset, // set 7, reset 27
	hidden:          UnsetSetReset = .unset, // set 8, reset 28
	strikethrough:   UnsetSetReset = .unset, // set 9, reset 29
	doubleUnderline: UnsetSet = .unset, // set 21

	// color can only be set once and will overwrite regardless of type
	fg: Color = .{},
	bg: Color = .{},

	pub const ParseErr = error{InsufficientLen, IncorrectFormat, InvalidCharacter, Overflow, UnknownIdentifier} || ParseColorErr;

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
				VariadicArgs.PeekErr.Overflow => return error.Overflow,
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
				30...37, 39 => |val| out.fg = .{.type = .pallet8, .val = val},
				40...47, 49 => |val| out.bg = .{.type = .pallet8, .val = val},

				// aixterm bright/bold pallet8
				90...97   => |val| out.fg = .{.type = .aixtermPallet8, .val = val},
				100...107 => |val| out.bg = .{.type = .aixtermPallet8, .val = val},

				// 38;5;{color}m     foreground pallet256
				// 38;2;{r};{g};{b}m foreground rgb
				ForegroundInt => {
					// TODO this will 'mutate' out.bg if there is not some piece of code between parseColor and assigning to out.fg
					// TODO i dont know why this is an issue, nor why this fixes it
					// TODO ex. assembly is included in _asm_graphics.txt showing the differences generated by lldb assemble when the out.fg assignment is the current line
					// TODO original line was ```ForegroundInt => out.fg = try parseColor(&it),```
					var c = try parseColor(&it);
					c.val +%= 1;
					c.val -%= 1;
					out.fg = c;
				},

				// 48;5;{color}m     background pallet256
				// 48;2;{r};{g};{b}m background rgb
				BackgroundInt => out.bg = try parseColor(&it),

				// invalidates the entire sequence
				else => return error.UnknownIdentifier,
			}
		}

		assert(it.nextBetter(u8) catch unreachable == null);

		// no values were set, the default is to reset
		if (out == Self{}) out.reset = .set;

		return out;
	}

	// CSI   ->  2
	// reset ->  1                -> ";"
	// opts  -> 26 == (9 * 2) + 8 -> "21;22;23;...29"
	// fg    -> 16                -> "38;2;255;255;255"
	// bg    -> 16                -> "48;2;255;255;255"
	pub const colorMaxPrintLen: usize = 16;
	// fn    ->  1                -> 'm'
	pub const maxPrintLen: usize = consts.CSI.len+1+26+(Self.colorMaxPrintLen*2)+Self.fnName.len;

	pub fn print(self: @This()) struct{[Self.maxPrintLen]u8, usize} {
		var out: [Self.maxPrintLen]u8 = undefined;
		std.mem.copyForwards(u8, &out, &consts.CSI);

		var index: usize = consts.CSI.len;

		// reset must be set first
		if (self.reset == .set) {
			out[index] = ';';
			index += 1;
		}

		// bold and faint require special handling due to both being bound to one reset code
		// TODO generate strings from Enums and reference that
		if (self.bold == .reset or self.faint == .reset) {
			std.mem.copyForwards(u8, out[index..], "22;");
			index += 3;
		}
		if (self.bold == .set) {
			std.mem.copyForwards(u8, out[index..], "1;");
			index += 2;
		}
		if (self.faint == .set) {
			std.mem.copyForwards(u8, out[index..], "2;");
			index += 2;
		}

		if (self.italic != .unset) {
			index += (std.fmt.bufPrint(
				out[index..],
				"{d};",
				.{if (self.italic == .set) @intFromEnum(Opts.italic) else @intFromEnum(ResetOpts.italic)}
			) catch unreachable).len;
		}
		if (self.underline != .unset) {
			index += (std.fmt.bufPrint(
				out[index..],
				"{d};",
				.{if (self.underline == .set) @intFromEnum(Opts.underline) else @intFromEnum(ResetOpts.underline)}
			) catch unreachable).len;
		}
		if (self.blinking != .unset) {
			index += (std.fmt.bufPrint(
				out[index..],
				"{d};",
				.{if (self.blinking == .set) @intFromEnum(Opts.blinking) else @intFromEnum(ResetOpts.blinking)}
			) catch unreachable).len;
		}
		if (self.inverse != .unset) {
			index += (std.fmt.bufPrint(
				out[index..],
				"{d};",
				.{if (self.inverse == .set) @intFromEnum(Opts.inverse) else @intFromEnum(ResetOpts.inverse)}
			) catch unreachable).len;
		}
		if (self.hidden != .unset) {
			index += (std.fmt.bufPrint(
				out[index..],
				"{d};",
				.{if (self.hidden == .set) @intFromEnum(Opts.hidden) else @intFromEnum(ResetOpts.hidden)}
			) catch unreachable).len;
		}
		if (self.strikethrough != .unset) {
			index += (std.fmt.bufPrint(
				out[index..],
				"{d};",
				.{if (self.strikethrough == .set) @intFromEnum(Opts.strikethrough) else @intFromEnum(ResetOpts.strikethrough)}
			) catch unreachable).len;
		}
		if (self.doubleUnderline == .set) {
			index += (std.fmt.bufPrint(out[index..], "{d};", .{@intFromEnum(Opts.doubleUnderline)}) catch unreachable).len;
		}

		inline for (std.meta.fields(Self)) |f| {
			if (f.type != Color) continue;

			const fgBgInt = if (std.mem.eql(u8, f.name, "fg")) ForegroundInt else BackgroundInt;

			switch (@field(self, f.name).type) {
				// TODO generate the string from Pallet8Fg.default and reference that
				.reset => {
					std.mem.copyForwards(u8, out[index..], "39;");
					index += 3;
				},
				// TODO generate the strings
				.pallet8, .aixtermPallet8 => {
					index += (std.fmt.bufPrint(out[index..], "{d};", .{@field(self, f.name).val}) catch unreachable).len;
				},
				.pallet256 => {
					index += (std.fmt.bufPrint(out[index..], "{d};5;{d};", .{fgBgInt, @field(self, f.name).val}) catch unreachable).len;
				},
				.rgb => {
					index += (std.fmt.bufPrint(
						out[index..],
						"{d};2;{d};{d};{d}",
						.{fgBgInt, (@field(self, f.name).val >> 16) & 255, (@field(self, f.name).val >> 8) & 255, @field(self, f.name).val & 255}
					) catch unreachable).len;
				},
				.unset => {},
			}
		}

		if (out[index-1] == ';') out[index-1] = 'm'
		else {
			out[index] = 'm';
			index += 1;
		}

		return .{out, index};
	}
};

pub const ResetGraphics: Graphics = Graphics.default;

// parse(bytes) src -> print(src) outBytes, outLen -> parse(outBytes) out
fn testBytesParsePrintParse(bytes: []const u8) !void {
	const src = Graphics.parse(bytes) catch unreachable;

	// print(src) outBytes, outLen
	const outBytes, const outLen = src.print();
	try expect(std.mem.eql(u8, bytes, outBytes[0..outLen]));

	// parse(outBytes) out
	const out = Graphics.parse(outBytes[0..outLen]) catch unreachable;
	try expect(src == out);
}

test Graphics {
	// basic input space testing of one unit
	// a unit is 1 byte for Opts, ResetOpts, Pallet8, & AixtermPallet8; but 2 bytes for Pallet256 FG/BG; and 4 bytes for RGB FG/BG

	// valid basic input space:
	// every field parses and prints
	// enum -> bytes -> parse(bytes) src -> print(src) outBytes, outLen -> parse(outBytes) out
	// ensures there is no data loss between conversions for all valid values
	{
		// default
		{
			const bytes = &Graphics.defaultStr;
			try expect(Graphics.parse(bytes) catch unreachable == Graphics.default);
			try testBytesParsePrintParse(bytes);
		}

		// opts
		// resetOpts
		const ParsePrintOptsTest = struct {
			optEnum:     type,
			expectedSet: bool,
		};
		const parsePrintOptsTests = [_]ParsePrintOptsTest{
			.{.optEnum = Opts, .expectedSet = true},
			.{.optEnum = ResetOpts, .expectedSet = false},
		};
		inline for (parsePrintOptsTests) |ppt| {
			inline for (std.meta.fields(ppt.optEnum)) |f| {
				var buf: [Graphics.defaultStr.len + consts.u8MaxStrLen]u8 = undefined;
				const bytes = std.fmt.bufPrint(&buf, "\x1b[{d}m", .{f.value}) catch unreachable;

				// check correct field is set
				var src = Graphics.parse(bytes) catch unreachable;
				if (f.value == @intFromEnum(ResetOpts.boldAndFaint)) {
					try expect(src.bold == if (ppt.expectedSet) .set else .reset);
					try expect(src.faint == if (ppt.expectedSet) .set else .reset);
				}
				else try expect(@field(src, f.name) == if (ppt.expectedSet) .set else .reset);
				
				// check every other field is unset
				if (f.value == @intFromEnum(ResetOpts.boldAndFaint)) {
					src.bold = .unset;
					src.faint = .unset;
				}
				else @field(src, f.name) = .unset;
				try expect(src == Graphics{});					

				try testBytesParsePrintParse(bytes);
			}
		}

		// pallet8
		// aixtermPallet8
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
				var src = Graphics.parse(bytes) catch unreachable;
				if (pppt.isFg) {
					try expect(src.fg.type == pppt.expectedColorType);
					try expect(src.fg.val == f.value);
				}
				else {
					try expect(src.bg.type == pppt.expectedColorType);
					try expect(src.bg.val == f.value);
				}

				// check every other field is unset
				if (pppt.isFg) src.fg = .{} else src.bg = .{};
				try expect(src == Graphics{});

				try testBytesParsePrintParse(bytes);
			}
		}

		// palllet256
		for (0..std.math.maxInt(u8)+1) |i| {
			for ([2]u8{ForegroundInt, BackgroundInt}) |bgFg| {
				var buf: [Graphics.defaultStr.len + consts.u8MaxStrLen + 5]u8 = undefined;
				const bytes = std.fmt.bufPrint(&buf, "\x1b[{d};5;{d}m", .{bgFg, i}) catch unreachable;

				// check correct field is set
				var src = Graphics.parse(bytes) catch unreachable;
				if (bgFg == ForegroundInt) {
					try expect(src.fg.type == .pallet256);
					try expect(src.fg.val == i);
				}
				else {
					try expect(src.bg.type == .pallet256);
					try expect(src.bg.val == i);
				}

				// check every other field is unset
				if (bgFg == ForegroundInt) src.fg = .{} else src.bg = .{};
				try expect(src == Graphics{});

				try testBytesParsePrintParse(bytes);
			}
		}

		// rgb
		// bufPrint is called at each step instead of once in the innermost loop for speed; this is ~2.5x faster
		for ([2]u8{ForegroundInt, BackgroundInt}) |bgFg| {
			var buf: [Graphics.defaultStr.len + 3 + 2 + (3 * consts.u8MaxStrLen) + 2 + 1]u8 = undefined;
			buf[0] = '\x1b';
			buf[1] = '[';
			const bgFgLen = (std.fmt.bufPrint(buf[2..], "{d};2;", .{bgFg}) catch unreachable).len + 2;

			for (0..std.math.maxInt(u8)+1) |i| {
				const oneLen = (std.fmt.bufPrint(buf[bgFgLen..], "{d};", .{i}) catch unreachable).len;

				for (0..std.math.maxInt(u8)+1) |j| {
					const twoLen = (std.fmt.bufPrint(buf[bgFgLen + oneLen..], "{d};", .{j}) catch unreachable).len;
		
					for (0..std.math.maxInt(u8)+1) |k| {
						const threeLen = (std.fmt.bufPrint(buf[bgFgLen + oneLen + twoLen..], "{d}m", .{k}) catch unreachable).len;
						const expectedVal = (@as(u24, @intCast(i)) << 16) + (@as(u24, @intCast(j)) << 8) + @as(u24, @intCast(k));
						const bytes = buf[0..bgFgLen+oneLen+twoLen+threeLen];

						// check correct field is set
						var src = Graphics.parse(bytes) catch unreachable;
						if (bgFg == ForegroundInt) {
							try expect(src.fg.type == .rgb);
							try expect(src.fg.val == expectedVal);
						}
						else {
							try expect(src.bg.type == .rgb);
							try expect(src.bg.val == expectedVal);
						}

						// check every other field is unset
						if (bgFg == ForegroundInt) src.fg = .{} else src.bg = .{};
						try expect(src == Graphics{});

						try testBytesParsePrintParse(bytes);
					}
				}
			}
		}
	}

	// invalid basic input space:
	// unknown identifiers invalidate the entire sequence
	{
		const count = std.meta.fields(Opts).len +
							std.meta.fields(ResetOpts).len +
							std.meta.fields(Pallet8Fg).len +
							std.meta.fields(Pallet8Bg).len +
							std.meta.fields(AixtermPallet8Fg).len +
							std.meta.fields(AixtermPallet8Bg).len +
							3; // zero, fg, and bg
		var knownVals: [count]u8 = undefined;
		var index: usize = 0;
		const types = [6]type{Opts, ResetOpts, Pallet8Fg, Pallet8Bg, AixtermPallet8Fg, AixtermPallet8Bg};
		inline for (types) |T| {
			inline for (std.meta.fields(T)) |f| {
				knownVals[index] = f.value;
				index += 1;
			}
		}
		knownVals[index] = 0;
		knownVals[index+1] = ForegroundInt;
		knownVals[index+2] = BackgroundInt;

		var buf: [Graphics.defaultStr.len + consts.u8MaxStrLen]u8 = undefined;
		for (0..std.math.maxInt(u8)+1) |i| {
			if (std.mem.indexOfScalar(u8, &knownVals, @truncate(i)) != null) continue;
			const bytes = std.fmt.bufPrint(&buf, "\x1b[{d}m", .{i}) catch unreachable;
			try expect(Graphics.parse(bytes) == error.UnknownIdentifier);
		}
	}

	// combinatory input space testing of multiple units

	// ability to reset faint & bold and then set each individually and independently
	{
		var buf: [Graphics.defaultStr.len + (consts.u8MaxStrLen * 2) + 1]u8 = undefined;
		var bytes: []const u8 = undefined;

		// faint
		bytes = std.fmt.bufPrint(&buf, "\x1b[{d}m", .{@intFromEnum(Opts.faint)}) catch unreachable;
		try expect(Graphics.parse(bytes) catch unreachable == Graphics{.faint = .set});

		// bold
		bytes = std.fmt.bufPrint(&buf, "\x1b[{d}m", .{@intFromEnum(Opts.bold)}) catch unreachable;
		try expect(Graphics.parse(bytes) catch unreachable == Graphics{.bold = .set});

		// reset bold and faint == rbf
		bytes = std.fmt.bufPrint(&buf, "\x1b[{d}m", .{@intFromEnum(ResetOpts.boldAndFaint)}) catch unreachable;
		try expect(Graphics.parse(bytes) catch unreachable == Graphics{.faint = .reset, .bold = .reset});
		try testBytesParsePrintParse(bytes);

		// rbf & faint
		bytes = std.fmt.bufPrint(&buf, "\x1b[{d};{d}m", .{@intFromEnum(ResetOpts.boldAndFaint), @intFromEnum(Opts.faint)}) catch unreachable;
		try expect(Graphics.parse(bytes) catch unreachable == Graphics{.faint = .set, .bold = .reset});
		try testBytesParsePrintParse(bytes);

		// rbf & bold
		bytes = std.fmt.bufPrint(&buf, "\x1b[{d};{d}m", .{@intFromEnum(ResetOpts.boldAndFaint), @intFromEnum(Opts.bold)}) catch unreachable;
		try expect(Graphics.parse(bytes) catch unreachable == Graphics{.faint = .reset, .bold = .set});
		try testBytesParsePrintParse(bytes);
	}

	// color overwriting
	{
		const ColorTest = struct {
			argsStr: []const u8,
			color:   Color,
		};

		const ColorTestSet = struct {
			isFg:  bool,
			tests: []const ColorTest,			
		};

		const fgTestSet = ColorTestSet{
			.isFg = true,
			.tests = &[_]ColorTest{
				.{.argsStr = "30",         .color = .{.type = .pallet8,        .val = 30}},
				.{.argsStr = "90",         .color = .{.type = .aixtermPallet8, .val = 90}},
				.{.argsStr = "38;5;1",     .color = .{.type = .pallet256,      .val = 1}},
				.{.argsStr = "38;2;1;1;1", .color = .{.type = .rgb,            .val = (1 << 16) + (1 << 8) + 1}},
				.{.argsStr = "38",         .color = .{.type = .reset}},
			},
		};

		const bgTestSet = ColorTestSet{
			.isFg = false,
			.tests = &[_]ColorTest{
				.{.argsStr = "40",         .color = .{.type = .pallet8,        .val = 40}},
				.{.argsStr = "100",        .color = .{.type = .aixtermPallet8, .val = 100}},
				.{.argsStr = "48;5;1",     .color = .{.type = .pallet256,      .val = 1}},
				.{.argsStr = "48;2;1;1;1", .color = .{.type = .rgb,            .val = (1 << 16) + (1 << 8) + 1}},
				.{.argsStr = "48",         .color = .{.type = .reset}},
			},
		};

		for ([2]ColorTestSet{fgTestSet, bgTestSet}) |cts| {
			for (cts.tests) |c1| {
				for (cts.tests) |c2| {
					var buf: [Graphics.minLen + (Graphics.colorMaxPrintLen*2) + 2]u8 = undefined;
					std.mem.copyForwards(u8, &buf, &consts.CSI);
					var len: usize = 2;
					std.mem.copyForwards(u8, buf[len..], c1.argsStr);
					len += c1.argsStr.len;
					buf[len] = ';';
					len += 1;
					std.mem.copyForwards(u8, buf[len..], c2.argsStr);
					len += c2.argsStr.len;
					buf[len] = 'm';
					len += 1;

					const bytes = buf[0..len];
					const src = Graphics.parse(bytes) catch unreachable;
					if (cts.isFg) {
						try expect(src.fg == c2.color);
						try expect(src.bg.type == .unset);
					} else {
						try expect(src.bg == c2.color);
						try expect(src.fg.type == .unset);
					}
				}
			}			
		}

		// test all possibilities in a row
		for ([2]ColorTestSet{fgTestSet, bgTestSet}) |cts| {
			var buf: [Graphics.minLen + 32]u8 = undefined;
			std.mem.copyForwards(u8, &buf, &consts.CSI);
			var len: usize = 2;
			
			for (cts.tests) |t| {
				std.mem.copyForwards(u8, buf[len..], t.argsStr);
				len += t.argsStr.len;
				buf[len] = 'm';
				len += 1;

				const bytes = buf[0..len];
				const src = Graphics.parse(bytes) catch unreachable;
				if (cts.isFg) {
					try expect(src.fg == t.color);
					try expect(src.bg.type == .unset);
				} else {
					try expect(src.bg == t.color);
					try expect(src.fg.type == .unset);
				}

				buf[len-1] = ';';
			}
		}
	}

	// TODO test reset, both 0 and empty, in the middle of args
	{
	}

	// TODO set, reset, set
	{
	}
}
