const std = @import("std");
const consts = @import("consts.zig");
const EscSeq = @import("escSeq.zig").EscSeq;
const assert = std.debug.assert;
const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

// TODO bigger in buffer, and remove parsed with iterator

// TODO grapheme handling

const Input = union(enum) {
	ascii:     u8,
	codePoint: [5]u8, // first byte is len
	invalid:   u8,
	escSeq:    EscSeq,
};

pub fn codePointBytes(cp: *const [5]u8) []const u8 {
	return cp[1..1+cp[0]];
}

const bufSize: usize = 128;

// [start, start +% len)
var parsed: [bufSize]Input = undefined;
var start: u7 = 0;
var len: u8 = 0;

// [0..overflow)
var buf: [bufSize]u8 = undefined;
var overflow: u7 = 0;

fn insert(val: Input) void {
	assert(len < bufSize);
	
	parsed[start +% len] = val;
	len += 1;
}

fn pop() Input {
	assert(len > 0);

	const out = parsed[start];
	start = start +% 1;
	len -= 1;
	
	return out;
}

fn incrIfNoOverflow(i: *u7, amount: u7) bool {
	const out, const of = @addWithOverflow(i.*, amount);
	if (of == 1) return false;

	i.* = out;
	return true;
}

// TODO int casting needs better handling
fn awaitRead() void {
	assert(len == 0);

	// TODO better handling, dont know if this can actually fail in this circumstance
	var n = stdin.readAtLeast(buf[overflow..], 1) catch unreachable;
	n += overflow;

	var i: u7 = 0;
	while (i < n) {
		// code points
		//// https://stackoverflow.com/a/68835029
		//// https://www.youtube.com/watch?v=tbdym9ZtepQ good stuff
		switch (buf[i]) {
			// esc seq
			consts.ESC => {
				// TODO if it is not long enough and n == bufLen break so it can go to overflow and try again after another read
				if (n-i >= 3 and (buf[i+1] == '[' or buf[i+1] == 'O')) {
					if (EscSeq.parse(buf[i..n])) |res| {
						insert(.{.escSeq = res[0]});
						if (!incrIfNoOverflow(&i, @truncate(res[1]))) return;
						continue;
					} else |err| if (err == error.InsufficientLen) break;
				}

				// handle it as just the ESC key
				insert(.{.ascii = buf[i]});
				if (!incrIfNoOverflow(&i, 1)) return;
			},

			// 1 byte ascii | unicode code point (no difference)
			0...26, 28...127 => {
				insert(.{.ascii = buf[i]});
				if (!incrIfNoOverflow(&i, 1)) return;
			},

			// unicode code point
			// 2 byte starts with 110XXXXX and following byte 10XXXXXX)
			// 3 byte starts with 1110XXXX and the other two begin with 10XXXXXX)
			// 4 byte starts with 11110XXX and the other three begin with 10XXXXXX)
			192...247 => {
				const additionalBytes: u3 = if (buf[i] >= 192 and buf[i] <= 223) 1
				else if (buf[i] >= 224 and buf[i] <= 239) 2
				else if (buf[i] >= 240 and buf[i] <= 247) 3
				else unreachable;
				
				// overflow guarantee not enough bytes
				_, const of = @addWithOverflow(i, additionalBytes);
				if (of == 1) break;

				// not enough bytes loaded
				if (i + additionalBytes >= n) break;

				const codePointLen: u7 = 1 + additionalBytes;
				var arr: [5]u8 = .{codePointLen, 0, 0, 0, 0};
				@memcpy(arr[1..1+codePointLen], buf[i..i+codePointLen]);

				insert(.{.codePoint = arr});
				if (!incrIfNoOverflow(&i, codePointLen)) return;
			},

			// not 7-bit ascii or valid first unicode byte
			else => {
				insert(.{.invalid = buf[i]});
				if (!incrIfNoOverflow(&i, 1)) return;
			},
		}
	}

	// update overflow and move overflow bytes to beginning of buf
	if (i < n) {
		overflow = @as(u7, @intCast(n))-i;
		std.mem.copyForwards(u8, buf[0..n-i], buf[i..n]);		
	}
}

pub fn awaitInput() Input {
	while (len == 0) awaitRead();
	return pop();
}
