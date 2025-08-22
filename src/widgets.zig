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

pub fn Menu(comptime Options: type) type {
	const ti = comptime @typeInfo(Options).@"enum";

	const fields: [ti.fields.len]Options = blk: {
		var out: [ti.fields.len]Options = undefined;
		inline for (ti.fields, 0..) |field, i| out[i] = @field(Options, field.name);

		break :blk out;
	};

	const texts: [ti.fields.len][]const u8 = blk: {
		const hasTextMethod = std.meta.hasMethod(Options, "text");
		var out: [ti.fields.len][]const u8 = undefined;
		inline for (fields, 0..) |field, i| out[i] = if (hasTextMethod) field.text() else @tagName(field);

		break :blk out;
	};

	const width = blk: {
		var out: usize = 0;
		inline for (texts) |text| {
			if (text.len > out) out = text.len;
		}

		break :blk out;
	};

	return struct {
		selected: usize = 0,

		selStyle: Graphics = .{
			.fg = .{.type = .rgb, .val = (65 << 16) + (90 << 8) + 119},
			.bold = .set, .underline = .set,
		},
		unselStyle: Graphics = .{
			.fg = .{.type = .rgb, .val = (35 << 16) + (60 << 8) + 89},
		},

		alignment: Alignment = AlignCM,

		// TODO handle rerenders
			// TODO the solution is to have a renderOption fn that has selected bool
			// TODO call this for the currIndex and then the updated currIndex
		fn updateSelected(self: *@This(), increment: bool) !void {
			assert(self.selected < ti.fields.len);

			if (increment) {
				self.selected += 1;
				// overflow
				if (self.selected == fields.len) self.selected = 0;
			} else {
				// underflow
				if (self.selected == 0) self.selected = fields.len;
				self.selected -= 1;
			}

			try self.render();
		}

		pub fn render(self: *@This()) !void {
			const winsize = try getWindowSize(null);
			icanonSet(false);
			echoSet(false);
			_ = try stdout.write(cursorInvisible);
			_ = try stdout.write(fullWipe);

			const x, var y = self.alignment.origin(winsize, @truncate(width), fields.len);
			inline for (0..texts.len) |i| {
				try moveCursor(x, y);
				if (self.selected == i) _ = try self.selStyle.write(stdout, texts[i])
				else _ = try self.unselStyle.write(stdout, texts[i]);
				
				y += 1;
			}
		}

		pub fn getSelection(self: *@This()) !Options {
			try self.render();

			while (true) switch (input.awaitInput()) {
				.escSeq => |v| switch (v) {
					.moveCursorUp   => try self.updateSelected(false),
					.moveCursorDown => try self.updateSelected(true),
					else            => {},
				},
				.ascii => |v| if (v == controlKeyEnter) return fields[self.selected],
				else => {},
			};
		}
	};
}

// TODO comptime and runtime versions
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

		while (true) switch (input.awaitInput()) {
			.ascii => |v| if (v == 'q') return,
			else => {},
		};
	}
};

pub fn Input(comptime bufSize: usize) type {
	return struct {
		const Self = @This();

		prompt: StyledText = .{
			.style = .{.fg = .{.type = .rgb, .val = (222 << 16) + (222 << 8) + 222}},
			.text = "how much does a polar bear weigh?",
		},
		// TODO placeholder
		buf: [bufSize]u8 = undefined,
		len: usize = 0,

		alignment: Alignment = AlignTL,

		// TODO selective rerender w bool arg for full rerender
		// TODO needs to handle codepoints when calculating width
		pub fn render(self: *Self) !void {
			const winsize = try getWindowSize(null);
			icanonSet(false);
			echoSet(false);
			_ = try stdout.write(cursorVisible);
			_ = try stdout.write(fullWipe);

			const x, var y = self.alignment.origin(winsize, @truncate(@max(self.prompt.text.len, self.len + 2)), 2);

			try moveCursor(x, y);
			if (self.prompt.style) |style| _ = try style.write(stdout, self.prompt.text)
			else _ = try stdout.write(self.prompt.text);
			y += 1;

			try moveCursor(x, y);
			_ = try stdout.write("> ");
			if (self.len > 0) _ = try stdout.write(self.buf[0..self.len]);
		}

		pub fn getInput(self: *Self) ![]const u8 {
			try self.render();

			while (true) switch (input.awaitInput()) {
				.ascii => |v| switch (v) {
					controlKeyEnter => {
						_ = try stdout.write(cursorInvisible);
						break;
					},
					controlKeyDelete => {
						// TODO needs to handle codepoints
						self.len = self.len -| 1;
						try self.render();
					},
					else => {
						self.buf[self.len] = v;
						self.len += 1;
						try self.render();
					},
				},
				// TODO handle cursor movement?
				.codePoint => |v| {
					@memcpy(self.buf[self.len..self.len+v[0]], v[1..1+v[0]]);
					self.len += v[0];
					try self.render();
				},
				else => {},
			};

	      return self.buf[0..self.len];
		}
	};
}

// TODO progress checklist

// TODO better handling, [16]u8 and just loop
// TODO allow for user selected char/codepoint
const progressBarStr: [1024]u8 = @splat('#');

pub const ProgressBar = struct {
	filledStyle: Graphics = .{
		.fg = .{.type = .rgb, .val = (218 << 16) + (98 << 8) + 125},
		.bold = .set,
	},
	emptyStyle: Graphics = .{.faint = .set},

	title: ?StyledText = null,
	progress: f32 = 0,
	alignment: Alignment = AlignCM,

	pub fn render(self: *@This()) !void {
		const winsize = try getWindowSize(null);
		icanonSet(false);
		echoSet(false);
		_ = try stdout.write(fullWipe);
		_ = try stdout.write(cursorInvisible);

		const x, var y = self.alignment.origin(
			winsize,
			winsize.col / 2,
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
		const width = winsize.col / 2;
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

pub const ScrollableText = struct {
	const Self = @This();

	text: []const u8,
	col: u16 = 0,

	precalcOffset: usize = 0,

	pub fn updateCol(self: *Self, incr: bool) !void {
		if (incr) self.col +|= 1 else self.col -|= 1;
		try self.render();
	}

	pub fn setRowToEnd(self: *Self) !void {
		self.precalcOffset = std.mem.lastIndexOfScalar(u8, self.text, '\n') orelse 0;
		try self.render();
	}

	pub fn setRow(self: *Self, row: u16) !void {
		self.precalcOffset = 0;

		for (0..row) |_| {
			if (self.precalcOffset >= self.text.len) break;

			self.precalcOffset += std.mem.indexOfScalar(u8, self.text[self.precalcOffset..], '\n') orelse break;
			self.precalcOffset += 1;
		}

		try self.render();
	}

	pub fn updateRow(self: *Self, incr: bool, diff: u16) !void {
		for (0..diff) |_| {
			// increment
			if (incr) {
				if (self.precalcOffset >= self.text.len) break;

				self.precalcOffset += std.mem.indexOfScalar(u8, self.text[self.precalcOffset..], '\n') orelse break;
				self.precalcOffset += 1;
				continue;
			}

			// decrement
			const next = std.mem.lastIndexOfScalar(u8, self.text[0..self.precalcOffset], '\n') orelse 0;
			self.precalcOffset = std.mem.lastIndexOfScalar(u8, self.text[0..next], '\n') orelse 0;
			if (self.precalcOffset != 0) self.precalcOffset += 1;
		}

		try self.render();
	}

	// TODO ensure the col is <= max width - 1
	pub fn render(self: *Self) !void {
		const winsize = try getWindowSize(null);
		icanonSet(false);
		echoSet(false);
		_ = try stdout.write(fullWipe);
		_ = try stdout.write(cursorInvisible);

		// TODO ansi esc seq width handling
		// TODO codepoint width handling

		var offset = self.precalcOffset;
		var y: u16 = 1;
		while (y <= winsize.row and offset < self.text.len) {
			try moveCursor(0, y);

			const end = std.mem.indexOfScalar(u8, self.text[offset..], '\n') orelse self.text.len - offset;
			if (self.col <= end) {
				const start = offset + self.col;
				const writableEnd = start + @min(@as(usize, @intCast(winsize.col)), end - self.col);
				_ = try stdout.write(self.text[start..writableEnd]);
			}

			y += 1;
			offset += end + 1;
		}
	}

	pub fn renderLoop(self: *Self) !void {
		try self.render();

		while (true) switch (input.awaitInput()) {
         .escSeq => |v| switch (v) {
				.moveCursorUp    => try self.updateRow(false, 1),
				.moveCursorDown  => try self.updateRow(true, 1),
				.moveCursorRight => try self.updateCol(true),
				.moveCursorLeft  => try self.updateCol(false),
	         .navKey => |w| switch (w) {
					.pageUp   => try self.updateRow(false, (try getWindowSize(null)).row),
					.pageDown => try self.updateRow(true, (try getWindowSize(null)).row),
					else => {},
	         },
	         // home
	         .moveCursorAbs => |pos| if (pos[0] == 1 and pos[1] == 1) {
					self.col = 0;
					try self.setRow(0);
	         },
	         // end
	         .moveCursorToStartOfPrevLine => |lines| if (lines == 1) try self.setRowToEnd(),
				else => {},
         },
         .ascii => |v| switch (v) {
				controlKeyEnter => try self.updateRow(true, 1),
				' ' => try self.updateRow(true, (try getWindowSize(null)).row),
				'q' => return,
				else => {},
         },
			else => {},
		};
	}
};
