const std = @import("std");
const consts = @import("consts.zig");

// TODO testing
pub const FnKey = enum(u64) {
	const Self = @This();

	const default:    ?Self  = null;
	const defaultStr: ?[0]u8 = null;
	const minLen:     usize  = consts.SS3.len + 1;

	F1    = 0x1b4f50,
	F2    = 0x1b4f51,
	F3    = 0x1b4f52,
	F4    = 0x1b4f53,
	F5    = 0x1b5b31357e,
	F6    = 0x1b5b31377e,
	F7    = 0x1b5b31387e,
	F8    = 0x1b5b31397e,
	F9    = 0x1b5b32307e,
	F10   = 0x1b5b32317e,
	F11   = 0x1b5b32337e,
	F12   = 0x1b5b32347e,
	F1TTY = 0x1b5b5b41,
	F2TTY = 0x1b5b5b42,
	F3TTY = 0x1b5b5b43,
	F4TTY = 0x1b5b5b44,
	F5TTY = 0x1b5b5b45,

	pub const ParseErr = error{
		NoMatch,
		InsufficientLen,
		IncorrectFormat
	};

	pub fn parse(bytes: []const u8) Self.ParseErr!struct{@This(), usize} {
		if (bytes.len < Self.minLen) return error.InsufficientLen;
		if (bytes[0] != consts.ESC) return error.IncorrectFormat;
		if (bytes[1] != 'O' and bytes[1] != '[') return error.IncorrectFormat;

		switch (bytes[1]) {
			0x4f => return switch (bytes[2]) {
				0x50 => .{.F1, 3},
				0x51 => .{.F2, 3},
				0x52 => .{.F3, 3},
				0x53 => .{.F4, 3},
				else => error.NoMatch,
			},

			0x5b => switch (bytes[2]) {
				0x31 => {
					if (bytes.len < 5) return error.InsufficientLen;
					if (bytes[4] != 0x7e) return error.NoMatch;

					return switch (bytes[3]) {
						0x35 => .{.F5, 5},
						0x37 => .{.F6, 5},
						0x38 => .{.F7, 5},
						0x39 => .{.F8, 5},
						else => error.NoMatch,
					};
				},

				0x32 => {
					if (bytes.len < 5) return error.InsufficientLen;
					if (bytes[4] != 0x7e) return error.NoMatch;

					return switch (bytes[3]) {
						0x30 => .{.F9,  5},
						0x31 => .{.F10, 5},
						0x33 => .{.F11, 5},
						0x34 => .{.F12, 5},
						else => error.NoMatch,
					};
				},
				
				0x5b => {
					if (bytes.len < 4) return error.InsufficientLen;

					return switch (bytes[3]) {
						0x41 => .{.F1TTY, 4},
						0x42 => .{.F2TTY, 4},
						0x43 => .{.F3TTY, 4},
						0x44 => .{.F4TTY, 4},
						0x45 => .{.F5TTY, 4},
						else => error.NoMatch,
					};
				},
				
				else => return error.NoMatch,
			},

			else => unreachable,
		}
	}

	pub fn print(self: Self) [6]u8 {
		const out = std.mem.toBytes(self)[0..5];

		const len = if (out[1] == 'O') 3
		else if (out[1] == '[' and (out[2] == 0x31 or out[2] == 0x32)) 5
		else if (out[1] == '[' and out[2] == '[') 4
		else unreachable;

		return [1]u8{len} ++ out;
	}
};
