const std = @import("std");
const cursor = @import("../escSeq/cursor.zig");
const EscSeq = @import("../escSeq/escSeq.zig").EscSeq;
const input = @import("../input/input.zig");
const alignment = @import("alignment.zig");
const spacing = @import("spacing.zig");
const termios = @import("termios.zig");
const charSentinel = @import("overflow.zig").TextOverflow.charSentinel;
const Bounds = @import("bounds.zig").Bounds;
const Point = @import("bounds.zig").Point;
const Offset = @import("bounds.zig").Offset;

const stdout = std.io.getStdOut().writer();
const assert = std.debug.assert;

// TODO needs to handle codepoints/graphemes when calculating width
// TODO replace client settable strings with something akin to BufferedInput, but that also handles graphemes
pub fn Input(comptime bufSize: usize) type {
	return struct {
		const Self = @This();
		const minCharsAfterPrompt = 2;

		prompt: []const u8 = "> ",

		// TODO implement
		placeholder: ?[]const u8 = null,

		buf: [bufSize]u8 = undefined,
		idx: usize       = 0,
		len: usize       = 0,

		// TODO this should be a type that can stand alone to handle the math, and not need these helper methods on the struct
		// TODO something like a 1 dimensional bounds, that is reliant upon the bounds
		cursorOffsetIndex: usize = 0,

		bounds: Bounds,

		fn cursorOffset(self: Self) !Offset {
			return self.bounds.offsetFromIndex(@truncate(self.cursorOffsetIndex + self.prompt.len));
		}

		fn cursorPos(self: Self) !Point {
			return self.bounds.pointFromOffset(try self.cursorOffset());
		}

		fn incrementCursorOffsetIndex(self: *Self, amount: usize) void {
			self.cursorOffsetIndex = @min(self.cursorOffsetIndex + amount, self.bounds.area() - self.prompt.len - 1);
		}

		pub fn render(self: Self) !void {
			// ensure there are no gaps at the beginning
			assert(self.idx >= self.cursorOffsetIndex);

			const x, const y = self.bounds.origin();
			const width, const height = self.bounds.size();
			const area = width * height;

			// check bounds
			if (width == 0) return error.ZeroWidth;
			if (height == 0) return error.ZeroHeight;
			if (self.prompt.len + Self.minCharsAfterPrompt > width) return error.PromptTooLongForBounds;

			// bounds check cursor
			assert(self.cursorOffsetIndex < area - self.prompt.len);

			// TODO constant escSeq cursorInvis
			_ = try stdout.write("\x1b[?25l");

			// print prompt
			try stdout.print(cursor.MoveCursorAbs.printFmt ++ "{s}", .{y, x, self.prompt});

			const totalAreaToWrite: u32 = @truncate(area - self.prompt.len);
			var offset = try self.bounds.offsetFromIndex(@truncate(self.prompt.len));
			const start: u16 = @truncate(self.idx - self.cursorOffsetIndex);
			var written: usize = 0;

			// print buf
			while (start + written < self.len and written < totalAreaToWrite) {
				const remainingBuf = self.len - start - written;
				const maxWidth = width - offset[0];
				const remainingAreaToWrite = totalAreaToWrite - written;
				const len = @min(maxWidth, remainingBuf, remainingAreaToWrite);
				
				try stdout.print(
					cursor.MoveCursorAbs.printFmt ++ "{s}",
					.{y + offset[1], x + offset[0], self.buf[start+written..start+written+len]},
				);

				written += len;
				offset = self.bounds.shiftOffsetForwards(offset, len) catch break;
			}

			// erase totalAreaToWrite
			while (written < totalAreaToWrite) {
				const len = width - offset[0];
				try stdout.print(
					cursor.MoveCursorAbs.printFmt ++ "\x1b[{d}X",
					.{y + offset[1], x + offset[0], len},
				);

				written += len;
				offset = self.bounds.shiftOffsetForwards(offset, len) catch break;
			}

			// apply overflow sentinels to beginning and end
			// check if beginning is cut off
			if (self.idx > self.cursorOffsetIndex) try stdout.print(
				cursor.MoveCursorAbs.printFmt ++ charSentinel,
				.{y, x + self.prompt.len},
			);
			// check if end is cut off
			if (start + totalAreaToWrite < self.len) try stdout.print(
				cursor.MoveCursorAbs.printFmt ++ charSentinel,
				.{self.bounds.y[1] - 1, self.bounds.x[1] - 1},
			);

			try cursor.MoveCursorAbs.applyVec(try self.cursorPos());
			// TODO constant escSeq cursorVis
			_ = try stdout.write("\x1b[?25h");
		}

		// TODO needs factoring w render
		fn appendAscii(self: *Self, char: u8) !void {
			const width = self.bounds.width();
			const area = self.bounds.area();

			assert(self.len <= self.buf.len);
			assert(self.idx <= self.len);
			assert(self.cursorOffsetIndex < area - self.prompt.len);
			
			if (self.len == self.buf.len) return;

			// copy initial values
			const startingIdx = self.idx;
			const startingCursorOffsetIdx = self.cursorOffsetIndex;

			// shift buf forwards
			if (self.idx < self.len) {
				for (0..self.len-self.idx) |i| self.buf[self.len-i] = self.buf[self.len-i-1];
			}
			// insert char
			self.buf[self.idx] = char;
			self.len += 1;
			self.idx += 1;
			self.incrementCursorOffsetIndex(1);

			// if cursor is at the end: perform a full render
			// as appending a char at the end will shift every char towards the prompt
			if (startingCursorOffsetIdx == area - self.prompt.len - 1) return self.render();

			// if cursor is not at the end: print from starting startingCursorOffsetIdx & starting idx forwards
			// as appending a char in the middle will only update the startingCursorOffsetIdx and shift every char after towards the end
			
			// TODO constant escSeq cursorInvis
			_ = try stdout.write("\x1b[?25l");

			const x, const y = self.bounds.origin();
			const totalAreaToWrite: u32 = @truncate(area - self.prompt.len - startingCursorOffsetIdx);
			var offset = try self.bounds.offsetFromIndex(@truncate(self.prompt.len + startingCursorOffsetIdx));
			var written: usize = 0;

			// rerender [starting idx..len]
			while (startingIdx + written < self.len and written < totalAreaToWrite) {
				const remainingBuf = self.len - startingIdx - written;
				const maxWidth = width - offset[0];
				const remainingAreaToWrite = totalAreaToWrite - written;

				const len = @min(remainingBuf, maxWidth, remainingAreaToWrite);
				try stdout.print(
					cursor.MoveCursorAbs.printFmt ++ "{s}",
					.{y + offset[1], x + offset[0], self.buf[startingIdx+written..startingIdx+written+len]},
				);

				offset = self.bounds.shiftOffsetForwards(offset, len) catch break;
				written += len;
			}

			// overflow: check if end is cut off
			if (startingIdx + totalAreaToWrite < self.len) try stdout.print(
				cursor.MoveCursorAbs.printFmt ++ charSentinel,
				.{self.bounds.y[1] - 1, self.bounds.x[1] - 1},
			);

			try cursor.MoveCursorAbs.applyVec(try self.cursorPos());
			// TODO constant escSeq cursorVis
			_ = try stdout.write("\x1b[?25h");
		}

		// TODO needs efficient rendering for deletes that dont shift the entire buf
		fn delAscii(self: *Self) !void {
			if (self.idx == 0) return;

			// shift left
			if (self.idx < self.len) {
				for (0..self.len-self.idx) |i| self.buf[self.idx+i-1] = self.buf[self.idx+i];
			}
			self.len -|= 1;
			self.idx -|= 1;
			self.cursorOffsetIndex -|= 1;

			try self.render();
		}

		pub fn setBounds(self: *Self, bounds: Bounds) !void {
			var offset = try self.cursorOffset();
			offset[0] = @min(offset[0], bounds.width());
			offset[1] = @min(offset[1], bounds.height());

			self.bounds = bounds;
			self.cursorOffsetIndex = bounds.offsetIndex(offset) - self.prompt.len;

			return self.render();
		}

		pub fn sigwinch(self: *Self, bounds: Bounds) !void {
			return self.setBounds(bounds);
		}

		pub fn handleAscii(self: *Self, char: u8) !?[]const u8 {
			switch (char) {
				// TODO const for enter
				0xa => {
					// TODO constant escSeq cursorInvis
					_ = try stdout.write("\x1b[?25l");
					return self.buf[0..self.len];
				},
				// TODO const for delete
				0x7f => try self.delAscii(),
				else => try self.appendAscii(char),
			}

			return null;
		}

		// TODO handle mouse click to update cursor offset and mouse scroll
		// TODO clean up all the math
		pub fn handleEscSeq(self: *Self, escSeq: EscSeq) !void {
			const startingIdx = self.idx;
			const startingCursorOffsetIdx = self.cursorOffsetIndex;
			const width = self.bounds.width();

			switch (escSeq) {
				.moveCursorLeft => {
					self.idx -|= 1;
					self.cursorOffsetIndex -|= 1;

					// if cursor is at the origin and there is more buffer before the startingIdx
					// render shift right
					if (startingCursorOffsetIdx == 0 and startingIdx > 0) return self.render();

					// update cursor
					return cursor.MoveCursorAbs.applyVec(try self.cursorPos());
				},
				.moveCursorUp => {
					self.idx -|= width;

					// if idx > 0
					// and the cursor is on the first line
					// and this won't produce a gap at the beginning (self.idx >= self.cursorOffsetIndex)
					// dont update the cursor and render shift down
					if (self.idx > 0 and
						self.cursorOffsetIndex < width - self.prompt.len and
						self.idx >= self.cursorOffsetIndex
					) return self.render();

					self.cursorOffsetIndex -|= width;

					// if subtracting the width sends the cursor to origin (also works if the cursor is already at the origin)
					// and adding the difference to the cursorOffsetIndex != startingCursorOffsetIdx (meaning attempted shift left)
					// and there is more buffer before the startingIdx
					// render shift right
					if (self.cursorOffsetIndex == 0 and
						startingCursorOffsetIdx - self.cursorOffsetIndex != 0 and
						startingIdx > 0
					) return self.render();

					// update cursor
					return cursor.MoveCursorAbs.applyVec(try self.cursorPos());
				},
				.moveCursorRight => {
					self.idx = @min(self.idx +| 1, self.len);
					self.incrementCursorOffsetIndex(1);

					// if cursor is at the end and there is more buffer after the startingIdx
					// render shift left
					if (startingCursorOffsetIdx == self.bounds.area() - self.prompt.len - 1 and startingIdx < self.len) return self.render();
					
					// update cursor
					return cursor.MoveCursorAbs.applyVec(try self.cursorPos());
				},
				.moveCursorDown => {
					self.idx = @min(self.idx +| width, self.len);

					const maxCursorOffset = self.bounds.area() - self.prompt.len - 1;
					const cursorLastLineOrigin = maxCursorOffset - width + 1;

					// not on last line, increment width and render updated cursor
					if (startingCursorOffsetIdx < cursorLastLineOrigin) {
						self.cursorOffsetIndex += width;
						return cursor.MoveCursorAbs.applyVec(try self.cursorPos());
					}

					// cursor is on the last line
					const remainingSpaceAfterCursor = maxCursorOffset - startingCursorOffsetIdx;
					const remainingBuf = self.len - startingIdx;

					// the buffer doesnt 'extend' (hidden) to the next line
					// move the cursor to the end of the buf / 1 after if possible
					if (remainingBuf < remainingSpaceAfterCursor) {
						self.cursorOffsetIndex += remainingBuf + 1;
						return cursor.MoveCursorAbs.applyVec(try self.cursorPos());
					}

					// the buffer 'extends' (hidden) to the next line OR it completely fills the last line
					// keep cursor in the same place if possible else to 1 after buf if possible
					// render shift up
					const idxDiff = self.idx - startingIdx;
					const startingX = (self.prompt.len + startingCursorOffsetIdx) % width;
					const endingX = (startingX + idxDiff) % width;
					if (startingX > endingX) self.cursorOffsetIndex -= startingX - endingX
					else if (startingX < endingX) self.cursorOffsetIndex += endingX - startingX;

					return self.render();
				},

				else => {},
			}
		}

		pub fn handleInput(self: *Self, in: input.Input) !?[]const u8 {
			switch (in) {
				.ascii => |v| return self.handleAscii(v),
				.escSeq => |v| try self.handleEscSeq(v),
				.codePoint => |v| {
					// TODO bounds checking
					@memcpy(self.buf[self.len..self.len+v.len], v.bytes());
					self.len += v.len;
					try self.render();
				},
				else => {},
			}

			return null;
		}
	};
}
