const std = @import("std");
const consts = @import("../escSeq/consts.zig");
const EscSeq = @import("../escSeq/escSeq.zig").EscSeq;

const assert = std.debug.assert;
const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

// TODO grapheme handling

pub const CodePoint = struct {
	const Self = @This();

	len: u3,
	buf: [4]u8,

	pub fn bytes(self: Self) []const u8 {
		return self.buf[0..self.len];
	}
};

pub const InputType = enum {
	ascii,
	invalid,
	codePoint,
	escSeq,
};

pub const Input = union(InputType) {
	const Self = @This();

	ascii:     u8,
	invalid:   u8,
	codePoint: CodePoint,
	escSeq:    EscSeq,
};

const ByteBuf = struct {
	const Self = @This();

	buf: [46]u8 = undefined,
	len: u6 = 0,

	fn append(self: *Self, char: u8) void {
		assert(self.len < self.buf.len);

		self.buf[self.len] = char;
		self.len += 1;
	}
};

const CodePointBuf = struct {
	const Self = @This();

	buf: [9]CodePoint = undefined,
	len: u4 = 0,

	fn append(self: *Self, codePoint: CodePoint) void {
		assert(self.len < self.buf.len);

		self.buf[self.len] = codePoint;
		self.len += 1;
	}
};

// TODO maximize ascii, invalid, and codePoint size
// allows for reading multiple of the same input type at once
const BufferedInput = union(InputType) {
	ascii:     ByteBuf,
	invalid:   ByteBuf,
	codePoint: CodePointBuf,
	escSeq:    EscSeq,

	test {
		assert(@sizeOf(Input) == @sizeOf(BufferedInput));
	}
};

const InputIterator = struct {
	const Self = @This();

	// [start..len)
	buf:   [1024]u8 = undefined,
	start: usize    = 0,
	len:   usize    = 0,

	next: ?Input = null,

	fn advanceBuf(self: *Self, len: usize) void {
		self.start += len;
		self.len -= len;

		assert(self.start + self.len <= self.buf.len);
	}

	fn shiftRemainingBufToBeginning(self: *Self) void {
		std.mem.copyForwards(u8,
			self.buf[0..self.len],
			self.buf[self.start..self.start+self.len],
		);
		self.start = 0;
	}

	// TODO better handling, dont know if this can actually fail in this circumstance
	fn readAtLeast(self: *Self) void {
		self.shiftRemainingBufToBeginning();
		self.len += stdin.readAtLeast(self.buf[self.len..], 1) catch unreachable;
	}

	// TODO better handling, dont know if this can actually fail in this circumstance
	fn readAll(self: *Self) void {
		self.shiftRemainingBufToBeginning();
		self.len += stdin.readAll(self.buf[self.len..]) catch unreachable;
	}

	fn consumeNext(self: *Self) ?Input {
		if (self.next) |n| {
			self.next = null;
			return n;
		}

		return null;
	}

	fn parse(self: *Self) Input {
		if (self.len == 0) self.readAtLeast();

		// code points
		//// https://stackoverflow.com/a/68835029
		//// https://www.youtube.com/watch?v=tbdym9ZtepQ
		const firstByte = self.buf[self.start];
		switch (firstByte) {
			// esc seq
			consts.ESC => {
				if (self.len < 3) self.readAll();

				// TODO just try parsing and implement better error handling else just handle ESC key
				// TODO if it is not long enough and n == bufLen break so it can go to overflow and try again after another read
				if (self.len >= 3 and self.buf[self.start+1] == '[' or self.buf[self.start+1] == 'O') {
					const es, const len = EscSeq.parse(self.buf[self.start..self.start+self.len]) catch |err| {
						// TODO fix
						if (err == error.InsufficientLen) {
							self.readAll();
							return self.parse();
						}

						self.advanceBuf(1);
						return .{.ascii = firstByte};
					};

					self.advanceBuf(len);
					return .{.escSeq = es};
				}

				// handle it as just the ESC key
				self.advanceBuf(1);
				return .{.ascii = firstByte};
			},

			// 1 byte ascii/code point
			0...26, 28...127 => {
				self.advanceBuf(1);
				return .{.ascii = firstByte};
			},

			// 2-4 byte code point
			// 2 byte starts with 110XXXXX and following byte 10XXXXXX)
			// 3 byte starts with 1110XXXX and the other two begin with 10XXXXXX)
			// 4 byte starts with 11110XXX and the other three begin with 10XXXXXX)
			192...247 => {
				const codePointLen: u3 = switch (firstByte) {
					192...223 => 2,
					224...239 => 3,
					240...247 => 4,
					else => unreachable
				};
				
				if (self.len < codePointLen) inputIterator.readAll();
				if (self.len < codePointLen) {
					self.advanceBuf(1);
					return .{.invalid = firstByte};
				}

				var arr: [4]u8 = undefined;
				@memcpy(arr[0..codePointLen], self.buf[self.start..self.start+codePointLen]);

				self.advanceBuf(codePointLen);
				return .{.codePoint = .{.len = codePointLen, .buf = arr}};
			},

			// not 7-bit ascii or valid first unicode byte
			else => {
				self.advanceBuf(1);
				return .{.invalid = firstByte};
			},
		}
	}
};

var inputIterator: InputIterator = .{};

pub fn awaitInput() Input {
	if (inputIterator.consumeNext()) |n| return n;
	return inputIterator.parse();
}

pub fn awaitBufferedInput() BufferedInput {
	// load as much as possible
	inputIterator.readAtLeast();

	const first = if (inputIterator.consumeNext()) |n| n else inputIterator.parse();
	const firstId = @intFromEnum(first);

	switch (first) {
		.ascii => {
			var out: ByteBuf = .{};
			out.append(first.ascii);

			while (inputIterator.len > 0 and out.len < out.buf.len) {
				const next = inputIterator.parse();
				if (@intFromEnum(next) != firstId) {
					inputIterator.next = next;
					break;
				}

				out.append(next.ascii);
			}

			return .{.ascii = out};
		},
		.invalid => {
			var out: ByteBuf = .{};
			out.append(first.invalid);

			while (inputIterator.len > 0 and out.len < out.buf.len) {
				const next = inputIterator.parse();
				if (@intFromEnum(next) != firstId) {
					inputIterator.next = next;
					break;
				}

				out.append(next.invalid);
			}

			return .{.invalid = out};
		},
		.codePoint => {
			var out: CodePointBuf = .{};
			out.append(first.codePoint);

			while (inputIterator.len > 0 and out.len < out.buf.len) {
				const next = inputIterator.parse();
				if (@intFromEnum(next) != firstId) {
					inputIterator.next = next;
					break;
				}

				out.append(next.codePoint);
			}

			return .{.codePoint = out};
		},
		.escSeq => |v| return .{.escSeq = v},
	}
}
