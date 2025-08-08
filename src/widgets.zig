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

pub const cursorInvisible: []const u8 = "\x1b[?25l";
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

pub const Alignment = struct {
	x: Align,
	y: Align,

	pub fn origin(self: @This(), winsize: std.posix.winsize, x: u16, y: u16) struct{u16, u16} {
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

pub const StyledText = struct {
	style: ?Graphics = null,
	text:  []const u8,
};

pub fn Menu(comptime options: type) type {
	const ti = comptime @typeInfo(options).@"enum";
	assert(std.meta.hasMethod(options, "text"));

	return struct {
		selected: ti.tag_type = 0,

		selStyle: Graphics = .{
			.fg = .{.type = .rgb, .val = (65 << 16) + (90 << 8) + 119},
			.bold = .set, .underline = .set,
		},
		unselStyle: Graphics = .{
			.fg = .{.type = .rgb, .val = (13 << 16) + (27 << 8) + 42},
		},

		winsize: std.posix.winsize = undefined,
		alignment: Alignment = AlignCM,

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

pub const Text = struct {
	const Self = @This();

	const qToReturn: []const u8 = "press q to return";

	styledText: StyledText = .{.text = "lauren gypsum"},
	winsize:    std.posix.winsize = undefined,
	alignment:  Alignment = AlignCM,

	pub fn render(self: *@This()) !void {
		self.winsize = try getWindowSize(null);
		icanonSet(false);
		echoSet(false);
		_ = try stdout.write(fullWipe);
		_ = try stdout.write(cursorInvisible);

		const height, const width = blk: {
			var height: u16 = 0;
			var width: u16 = 0;

			var iter = std.mem.splitScalar(u8, self.styledText.text, '\n');
			while (iter.next()) |v| {
				// 1 is subtracted to ensure that at least 1 char will be on the next line
				const overflow: u16 = @truncate((v.len -| 1) / self.winsize.col);
				// height is guaranteed to be at least 1 per line, and then an additional per overflow
				height += 1 + overflow;
				if (v.len > width) width = @min(self.winsize.col, v.len);
			}

			if (Self.qToReturn.len > width) width = Self.qToReturn.len;

			break :blk .{height, width};
		};

		const x, var y = self.alignment.origin(self.winsize, width, height);

		if (self.styledText.style) |style| _ = try style.apply(stdout);
		var iter = std.mem.splitScalar(u8, self.styledText.text, '\n');
		while (iter.next()) |v| {
			var winIter = std.mem.window(u8, v, width, width);
			while (winIter.next()) |w| {
				try moveCursor(x, y);
				_ = try stdout.write(w);
				y += 1;

				if (y > self.winsize.row) break;
			}

			if (y > self.winsize.row) break;
		}

		// reset graphics
		if (self.styledText.style != null) _ = try stdout.write("\x1b[m");
		if (y <= self.winsize.row) {
			try moveCursor(x, y);
			_ = try stdout.write(qToReturn);
		}
	}

	pub fn display(self: *@This()) !void {
		try self.render();

		while (true) {
			switch (input.awaitInput()) {
	         .ascii => |v| if (v == 'q') return,
				else => {},
			}
		}
	}
};

pub fn Input(comptime bufSize: usize) type {
	return struct {
		prompt: StyledText = .{
			.style = .{.fg = .{.type = .rgb, .val = (222 << 16) + (222 << 8) + 222}},
			.text = "how much does a polar bear weigh?",
		},
		// TODO placeholder
		buf: [bufSize]u8 = undefined,
		len: usize = 0,

		winsize: std.posix.winsize = undefined,

		alignment: Alignment = AlignTL,

		// TODO selective rerender w bool arg for full rerender
		pub fn render(self: *@This()) !void {
			self.winsize = try getWindowSize(null);
			icanonSet(false);
			echoSet(false);
			_ = try stdout.write(cursorVisible);
			_ = try stdout.write(fullWipe);

			const x, var y = self.alignment.origin(self.winsize, @truncate(@max(self.prompt.text.len, self.len + 2)), 2);

			try moveCursor(x, y);
			if (self.prompt.style) |style| _ = try style.write(stdout, self.prompt.text)
			else _ = try stdout.write(self.prompt.text);
			y += 1;

			try moveCursor(x, y);
			_ = try stdout.write("> ");
			if (self.len > 0) _ = try stdout.write(self.buf[0..self.len]);
		}

		pub fn getInput(self: *@This()) ![]const u8 {
			try self.render();

			while (true) {
				switch (input.awaitInput()) {
					.ascii => |v| {
						switch (v) {
							controlKeyEnter => {
								// TODO instead just stop the cursor from going to a newline
								_ = try stdout.write(cursorInvisible);
								break;
							},
							controlKeyDelete => {
								self.len = self.len -| 1;
								try self.render();
							},
							else => {
								self.buf[self.len] = v;
								self.len += 1;
								try self.render();
							},
						}
					},
					// TODO handle cursor movement?
					.codePoint => |v| {
						@memcpy(self.buf[self.len..self.len+v[0]], v[1..1+v[0]]);
						self.len += v[0];
						try self.render();
					},
					else => {},
				}
			}

	      return self.buf[0..self.len];
		}
	};
}

// TODO progress checklist

const progressBarStr: [1024]u8 = @splat('#');

pub const ProgressBar = struct {
	filledStyle: Graphics = .{
		.fg = .{.type = .rgb, .val = (218 << 16) + (98 << 8) + 125},
		.bold = .set,
	},
	emptyStyle: Graphics = .{.faint = .set},

	title: ?StyledText = null,
	progress: f32 = 0,
	winsize: std.posix.winsize = undefined,
	alignment: Alignment = AlignCM,

	pub fn render(self: *@This()) !void {
		self.winsize = try getWindowSize(null);
		icanonSet(false);
		echoSet(false);
		_ = try stdout.write(fullWipe);
		_ = try stdout.write(cursorInvisible);

		const x, var y = self.alignment.origin(
			self.winsize,
			self.winsize.col / 2,
			// TODO calc bounding box
			if (self.title == null) 1 else 2,
		);

		if (self.title) |title| {
			try moveCursor(x, y);
			y += 1;

			if (title.style) |style| _ = try style.write(stdout, title.text)
			else _ = try stdout.write(title.text);
		}

		try moveCursor(x, y);
		const width = self.winsize.col / 2;
		const widthF: f32 = @floatFromInt(width);
		const filled: usize = @intFromFloat(widthF * self.progress);
		const empty = width - filled;
		_ = try self.filledStyle.write(stdout, progressBarStr[0..filled]);
		_ = try self.emptyStyle.write(stdout, progressBarStr[0..empty]);
	}

	pub fn updateTitle(self: *@This(), title: StyledText) !void {
		self.title = title;
		try self.render();
	}

	pub fn updateProgress(self: *@This(), progress: f32) !void {
		assert(progress >= 0 and progress <= 1);
		self.progress = progress;
		try self.render();
	}
};
