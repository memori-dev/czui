const std = @import("std");
const Graphics = @import("../escSeq/graphics.zig").Graphics;
const input = @import("../input/input.zig");
const alignment = @import("alignment.zig");
const cursor = @import("../escSeq/cursor.zig");
const Bounds = @import("bounds.zig").Bounds;

const linux = std.os.linux;
const assert = std.debug.assert;
const stdout = std.io.getStdOut().writer();
const stdoutHandle = std.io.getStdOut().handle;

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

// TODO remove
pub fn getWindowSize(errno: ?*std.posix.E) !std.posix.winsize {
   var winsize: std.posix.winsize = undefined;
   const err = std.posix.errno(
   	std.posix.system.ioctl(stdoutHandle, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize))
   );

   if (errno) |e| e.* = err;
   if (err == .SUCCESS) return winsize;
   return error.CheckErrno;
}

pub const StyledText = struct {
	style: ?Graphics = null,
	text:  []const u8,
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

		// TODO margin
		alignment: alignment.Alignment = alignment.AlignTL,

		pub fn sigwinch(self: *Self, bounds: Bounds) !void {
			return self.render(bounds);
		}

		// TODO if a char is deleted and it is the last of that line it will need to be cleared
		pub fn rerender(self: *Self, bounds: Bounds) !void {
			const boundsWidth = bounds.width();

			const maxWidth: u16 = @truncate(@min(
				@max(self.prompt.text.len, self.len + 2),
				boundsWidth,
			));
			const alignedBounds = self.alignment.getBounds(bounds, .{maxWidth, 2});
			const x, var y = alignedBounds.origin();
			y += 1;

			const alignedWidth = alignedBounds.width();

			// at least 1 line is guaranteed
			// 2 is added to compensate for "> "
			// 1 is subtracted to truncate on exact division
			const lines = 1 + ((self.len + 2 - 1) / alignedWidth);

			_ = try stdout.write(cursorInvisible);

			try stdout.print(
				cursor.MoveCursorAbs.printFmt ++
				"\x1b[{d}X",
				.{y, bounds.x[0], boundsWidth},
			);

			if (x > 1) try stdout.print("\x1b[{d}C", .{x-1});
			try stdout.print("> {s}", .{self.buf[0..@min(alignedWidth -| 2, self.len)]});

			for (1..lines) |i| {
				const offset = (alignedWidth -| 2) + ((i - 1) * alignedWidth);
				try stdout.print(
					cursor.MoveCursorAbs.printFmt ++
					"\x1b[{d}X" ++
					"{s}",
					.{y + i, bounds.x[0], boundsWidth, self.buf[offset..@min(offset+alignedWidth, self.len)]},
				);
			}

			_ = try stdout.write(cursorVisible);
		}

		// TODO needs to handle codepoints/graphemes when calculating width
		pub fn render(self: *Self, bounds: Bounds) !void {
			icanonSet(false);
			echoSet(false);
			_ = try stdout.write(cursorVisible);
			_ = try stdout.write(fullWipe);

			const alignedBounds = self.alignment.getBounds(bounds, .{@truncate(@max(self.prompt.text.len, self.len + 2)), 2});
			const x, var y = alignedBounds.origin();

			try moveCursor(x, y);
			if (self.prompt.style) |style| _ = try style.write(stdout, self.prompt.text)
			else _ = try stdout.write(self.prompt.text);
			y += 1;

			return self.rerender(bounds);
		}

		pub fn getInput(self: *Self, bounds: Bounds) ![]const u8 {
			try self.render(bounds);

			while (true) switch (input.awaitInput()) {
				.ascii => |v| switch (v) {
					controlKeyEnter => {
						_ = try stdout.write(cursorInvisible);
						break;
					},
					controlKeyDelete => {
						// TODO needs to handle codepoints
						self.len = self.len -| 1;
						try self.rerender(bounds);
					},
					else => {
						self.buf[self.len] = v;
						self.len += 1;
						try self.rerender(bounds);
					},
				},
				.codePoint => |v| {
					@memcpy(self.buf[self.len..self.len+v.len], v.bytes());
					self.len += v.len;
					try self.rerender(bounds);
				},
				else => {},
			};

	      return self.buf[0..self.len];
		}
	};
}

// TODO progress checklist

// TODO better handling and just loop
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
	alignment: alignment.Alignment = alignment.AlignCM,

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

	pub fn sigwinch(self: *Self, _: Bounds) !void {
		return self.render();
	}

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
	         .moveCursorAbs => |pos| if (pos.x == 1 and pos.y == 1) {
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
