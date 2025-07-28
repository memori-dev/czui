const std = @import("std");
const consts = @import("consts.zig");
const VariadicArgs = @import("variadicArgs.zig");

const Pallet256Int:  u8 = 5;
const RGBInt:        u8 = 2;
const ForegroundInt: u8 = 38;
const BackgroundInt: u8 = 48;

pub const ResetOpt = enum(u1) { unset, set };

pub const Opt = enum(u2) { unset, set, reset };

pub const ColorType = enum(u3) { unset, pallet8, pallet256, rgb, reset };

pub const Color = packed struct {
	colorType: ColorType = .unset,
	val:       u24       = 0,
};

fn parseColor(it: *VariadicArgs) !?Color {
	// a copy is used to correctly handle advancing the main iter
	var itCopy = it.*;

	// parse format
	const formatOpt = itCopy.nextBetter(u3) catch |err| switch (err) {
			// empty coerces to 0 which performs a full reset and the iter does not advance
			VariadicArgs.PeekErr.Empty => return null,
			// invalidates the entire sequence
			VariadicArgs.PeekErr.InvalidCharacter => return error.ColorFormatInvalidChar,
			// resets the color and the iter does not advance
			VariadicArgs.PeekErr.Overflow => return .{.colorType = .reset},
	};

	// if the format is null the color is reset and the iter does not advance
	const format = formatOpt orelse return .{.colorType = .reset};

	// resets the color and does not advance
	if (format != Pallet256Int and format != RGBInt) return .{.colorType = .reset};

	if (format == Pallet256Int) {
		const colorVal = itCopy.nextBetter(u16) catch |err| switch (err) {
			// coerces to 0
			VariadicArgs.PeekErr.Empty => 0,
			VariadicArgs.PeekErr.Overflow => 0,
			// invalidates the entire sequence
			VariadicArgs.PeekErr.InvalidCharacter => return error.Pallet256IntInvalidChar,
		};

		// if the val is null the color resets and the iter does not advance
		const val = colorVal orelse return .{.colorType = .reset};

		// return valid color and advance the iter 2
		it.advance(2);
		return .{.colorType = .pallet256, .val = @mod(val, 255)};
	}
	
	if (format == RGBInt) {
		var colors: [3]u16 = undefined;
		for (0..colors.len) |i| {
			const val = itCopy.nextBetter(u16) catch |err| switch (err) {
				// coerces to 0
				VariadicArgs.PeekErr.Empty => 0,
				VariadicArgs.PeekErr.Overflow => 0,
				// invalidates the entire sequence
				VariadicArgs.PeekErr.InvalidCharacter => return error.Pallet256IntInvalidChar,
			};

			// if there are not at least 3 ints following, reset the color and do not advance the iter
			colors[i] = val orelse return .{.colorType = .reset}; 
		}

		// return rgb and advance the iter 4
		it.advance(4);
		var val: u24 = 0;
		val += @as(u24, @mod(colors[0], 255)) << 16;
		val += @as(u24, @mod(colors[1], 255)) << 8;
		val += @as(u24, @mod(colors[2], 255));
		return .{.colorType = .rgb, .val = val};
	}
	
	unreachable;
}

// m(...x) -> color / graphics, where x either sets or resets and there are x combos for 8 & 24 bit color
pub const Graphics = packed struct {
	const Self = @This();

	reset: ResetOpt = .unset, // 0 (default)

	bold:            Opt = .unset, // 1, 22
	faint:           Opt = .unset, // 2, 22
	italic:          Opt = .unset, // 3, 23
	underline:       Opt = .unset, // 4, 24
	blinking:        Opt = .unset, // 5, 25
	inverse:         Opt = .unset, // 7, 27
	hidden:          Opt = .unset, // 8, 28
	strikethrough:   Opt = .unset, // 9, 29
	doubleUnderline: Opt = .unset, // 21

	// color can only be set once and will overwrite regardless of colorType
	fg: Color = .{},
	bg: Color = .{},

	pub fn parse(bytes: []const u8) !Self {
		// TODO length check
		// TODO format check
		//assert(bytes[bytes.len-1] == 'm');

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
				90...97   => |val| out.fg = .{.colorType = .pallet8, .val = val},
				100...107 => |val| out.bg = .{.colorType = .pallet8, .val = val},

				// 38;5;{color}m     foreground pallet256
				// 38;2;{r};{g};{b}m foreground rgb
				ForegroundInt => {
					if (try parseColor(&it)) |color| out.fg = color;
				},

				// 48;5;{color}m     background pallet256
				// 48;2;{r};{g};{b}m background rgb
				BackgroundInt => {
					if (try parseColor(&it)) |color| out.bg = color;
				},

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





	//noBoldOrFaint   // 22
	//noItalic        // 23
	//noUnderline     // 24
	//steady          // 25
	//positive        // 27
	//visible         // 28
	//noStrikethrough // 29

	// both can be applied to create faint bold
	//try stdout.print("\x1b[1;2mtesting\x1b[mtesting\n", .{});
	// bold
	//try stdout.print("\x1b[1mtesting\x1b[mtesting\n", .{});
	// faint
	//try stdout.print("\x1b[2mtesting\x1b[mtesting\n", .{});

	// 22 resets faint and bold
	//try stdout.print("\x1b[1;2;22mtesting\x1b[mtesting\n", .{});

	// foreground
	// 30 Black
	// 31 Red
	// 32 Green
	// 33 Yellow
	// 34 Blue
	// 35 Magenta
	// 36 Cyan
	// 37 White
	// 39 default, ECMA-48 3rd

	// background
	// 40 Black
	// 41 Red
	// 42 Green
	// 43 Yellow
	// 44 Blue
	// 45 Magenta
	// 46 Cyan
	// 47 White
	// 49 default, ECMA-48 3rd

	// aixterm bright/bold foreground
	// 90 Black
	// 91 Red
	// 92 Green
	// 93 Yellow
	// 94 Blue
	// 95 Magenta
	// 96 Cyan
	// 97 White

	// aixterm bright/bold background
	// 100 Black
	// 101 Red
	// 102 Green
	// 103 Yellow
	// 104 Blue
	// 105 Magenta
	// 106 Cyan
	// 107 White

	// TODO?
	// If xterm is compiled with the 16-color support disabled, it supports the following, from rxvt
	// 100 - Set foreground and background color to default

	// 256
	// 38;5;{ID}m - foreground
	// 48;5;{ID}m - background
				
	// RGB
	// 38;2;{r};{g};{b}m - foreground
	// 48;2;{r};{g};{b}m - background
