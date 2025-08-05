const std = @import("std");
const linux = std.os.linux;
const assert = std.debug.assert;
const stdout = std.io.getStdOut().writer();
const stdoutHandle = std.io.getStdOut().handle;
const Graphics = @import("graphics.zig").Graphics;
const input = @import("input.zig");

const controlKeyTab    = 0x9;
const controlKeyEnter  = 0xa;
const controlKeyEscape = 0x1b;
const controlKeyDelete = 0x7f;

const altScreenEnter: []const u8 = "\x1b[?1049h";
const altScreenExit:  []const u8 = "\x1b[?1049l";

const cursorInvisible: []const u8 = "\x1b[?25l";
const cursorVisible:   []const u8 = "\x1b[?25h";
const cursorToOrigin:  []const u8 = "\x1b[H";
const cursorMoveFmt:   []const u8 = "\x1b[{d};{d}H";

const eraseScreen:                []const u8 = "\x1b[2J";
const eraseScrollback:            []const u8 = "\x1b[3J";
const eraseFromCursorToEndOfLine: []const u8 = "\x1b[0K";

const modeReset:         []const u8 = "\x1b[0m";
const modeBold:          []const u8 = "\x1b[1m";
const modeFaint:         []const u8 = "\x1b[2m";
const modeItalic:        []const u8 = "\x1b[3m";
const modeUnderline:     []const u8 = "\x1b[4m";
const modeBlinking:      []const u8 = "\x1b[5m";
const modeInverse:       []const u8 = "\x1b[7m";
const modeHidden:        []const u8 = "\x1b[8m";
const modeStrikethrough: []const u8 = "\x1b[9m";

//pub const mouseDetection: []const u8 = "\x1b[?1000;1006;1015h";
pub const mouseDetection: []const u8 = "\x1b[?1003;1006;1015h";

pub const fullWipe = eraseScreen ++ eraseScrollback ++ cursorToOrigin;

// cursor starts at {1,1}
// when y exceeds the winsize.row it will just set the cursor to winsize.row (causing unexpected overwrites)
pub fn moveCursor(x: u16, y: u16) !void {
	return stdout.print(cursorMoveFmt, .{y, x});
}

// https://ziglang.org/documentation/master/std/#std.os.linux.termios
// https://ziglang.org/documentation/master/std/#std.os.linux.tc_lflag_t
pub fn icanonSet(val: bool) void {
	var term: linux.termios = undefined;
	_ = linux.tcgetattr(1, &term);
	term.lflag.ICANON = val;
	_ = linux.tcsetattr(1, std.posix.TCSA.NOW, &term);
}

pub fn echoSet(val: bool) void {
	var term: linux.termios = undefined;
	_ = linux.tcgetattr(1, &term);
	term.lflag.ECHO = val;
	_ = linux.tcsetattr(1, std.posix.TCSA.NOW, &term);
}

pub fn getWindowSize(errno: ?*std.posix.E) !std.posix.winsize {
   var winsize: std.posix.winsize = undefined;
   const err = std.posix.errno(
   	std.posix.system.ioctl(stdoutHandle, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize))
   );

   if (errno) |e| e.* = err;
   if (err == .SUCCESS) return winsize;
   return error.CheckErrno;
}

// origin: 1, 1
// writable area is inclusive of winsize
//// x [1, winsize.col]
//// y [1, winsize.row]
const Align = enum {
	origin,
	middle,
	ending,

	fn coord(self: @This(), winsizeVal: u16, val: u16) u16 {
		return switch(self) {
			.origin => 1,
			.middle => @max((winsizeVal -| val) / 2, 1),
			.ending => @max((winsizeVal + 1) -| val, 1),
		};
	}
};

const Alignment = struct {
	x: Align,
	y: Align,

	fn origin(self: @This(), winsize: std.posix.winsize, x: u16, y: u16) struct{u16, u16} {
		return .{self.x.coord(winsize.col, x), self.y.coord(winsize.row, y)};
	}
};

// T -> TOP, C -> Center, B -> Bottom
// L -> Left, M -> Middle, R -> Right
pub const AlignTL = Alignment{.x = .origin, .y = .origin};
pub const AlignTM = Alignment{.x = .middle, .y = .origin};
pub const AlignTR = Alignment{.x = .ending, .y = .origin};
pub const AlignCL = Alignment{.x = .origin, .y = .middle};
pub const AlignCM = Alignment{.x = .middle, .y = .middle};
pub const AlignCR = Alignment{.x = .ending, .y = .middle};
pub const AlignBL = Alignment{.x = .origin, .y = .ending};
pub const AlignBM = Alignment{.x = .middle, .y = .ending};
pub const AlignBR = Alignment{.x = .ending, .y = .ending};

pub fn Menu(comptime options: type) type {
	const ti = comptime @typeInfo(options).@"enum";
	assert(std.meta.hasMethod(options, "text"));

	return struct {
		selected: ti.tag_type = 0,

		selStyle: Graphics = .{
			.fg = .{.type = .rgb, .val = (65 << 16) + (90 << 8) + 119},
			.bold = .set, .underline = .set,
		},

		winsize: std.posix.winsize = undefined,
		alignment: Alignment = AlignCM,

		unselStyle: Graphics = .{
			.fg = .{.type = .rgb, .val = (13 << 16) + (27 << 8) + 42},
		},

		// TODO handle rerenders
			// TODO the solution is to have a renderOption fn that has selected bool
			// TODO call this for the currIndex and then the updated currIndex
		fn updateSelected(self: *@This(), increment: bool) !void {
			var currIndex: ti.tag_type = undefined;
			inline for (ti.fields, 0..) |field, i| {
				if (field.value == self.selected) currIndex = i;
			}

			// this should never happen, i hope
			assert(currIndex >= 0 and currIndex < ti.fields.len);

			if (increment) {
				currIndex = currIndex +% 1;
				if (currIndex < 0 or currIndex >= ti.fields.len) currIndex = 0;
			} else {
				currIndex = currIndex -% 1;
				if (currIndex < 0 or currIndex >= ti.fields.len) currIndex = ti.fields.len - 1;
			}

			self.selected = currIndex;

			try self.render();
		}

		pub fn render(self: *@This()) !void {
			self.winsize = try getWindowSize(null);
			icanonSet(false);
			echoSet(false);
			_ = try stdout.write(cursorInvisible);
			_ = try stdout.write(fullWipe);

			// TODO just calc this at comptime?
			var width: usize = 0;
			inline for (ti.fields) |field| {
				const n = @field(options, field.name).text().len;
				if (n > width) width = n;
			}
			const x, var y = self.alignment.origin(self.winsize, @truncate(width), ti.fields.len);

			inline for (ti.fields, 0..) |field, i| {
				const f = @field(options, field.name);

				try moveCursor(x, y);
				if (self.selected == i) _ = try self.selStyle.write(stdout, f.text())
				else _ = try self.unselStyle.write(stdout, f.text());
				
				y += 1;
			}
		}

		pub fn getSelection(self: *@This()) !options {
			try self.render();

			while (true) {
				switch (input.awaitInput()) {
		         .escSeq => |v| {
		         	switch (v) {
							.moveCursorUp   => try self.updateSelected(false),
							.moveCursorDown => try self.updateSelected(true),
							else            => {},		         		
		         	}
		         },
		         .ascii => |v| {
		         	if (v != controlKeyEnter) continue;
						inline for (ti.fields, 0..) |field, i| if (self.selected == i) return @field(options, field.name);
		         },
					else => {},
				}
			}
		}
	};
}
