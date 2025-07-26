const std = @import("std");
const consts = @import("consts.zig");

pub const VariadicArg = @This();
const Self = VariadicArg;
	
it: std.mem.SplitIterator(u8, .scalar),

const Err = error{InvalidCharacter};

// invalid characters, meaning non-numeric, will return an error
// empty ints are valid and are skipped, eg. "1;;3"
// very large numbers do not cause an error, eg. 999... repeating for 128 characters. but, they are skipped if they are larger than the int bitwidth provided
pub fn next(self: *Self, comptime T: type) Self.Err!?T {
	while (self.it.next()) |str| {
		if (str.len == 0) continue;

		const val = std.fmt.parseInt(T, str, 10) catch |err| {
			switch (err) {
				error.InvalidCharacter => return error.InvalidCharacter,
				error.Overflow => continue,
			}
		};

		return val;
	}

	return null;
}

pub fn init(bytes: []const u8) Self {
	return .{.it = std.mem.splitScalar(u8, bytes, consts.separator)};
}

test VariadicArg {
	const expect = std.testing.expect;

	inline for (consts.UInt1To16) |T| {
		// empty: returns null
		{
			var it = Self.init("");
			while (it.next(T) catch unreachable) |_| unreachable;
			try expect(it.next(T) catch unreachable == null);
		}

		// one int that overflows: returns null
		{
			var buf: [consts.u16MaxStrLen]u8 = undefined;
			const overflow: u32 = @intCast(std.math.maxInt(T)+1);
			const str = std.fmt.bufPrint(&buf, "{d}", .{overflow}) catch unreachable;
			var it = Self.init(str);
			while (it.next(T) catch unreachable) |_| unreachable;
			try expect(it.next(T) catch unreachable == null);
		}

		// one int with InvalidChar: returns InvalidChar, then null
		{
			var buf: [consts.u16MaxStrLen]u8 = undefined;

			for (0..std.math.maxInt(T)+1) |v| {
				const strLen = (std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable).len;
				for (0..strLen) |i| {
					const str = std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable;
					// push each index out of the numeric range while avoiding ';'
					str[i] += 12;
					var it = Self.init(str);
					try expect(it.next(T) == Self.Err.InvalidCharacter);
					while (it.next(T) catch unreachable) |_| unreachable;
				}
			}
		}

		// two ints; first valid and second with InvalidChar (assumes that if the second fails any proceeding will cause a failure)
		{
			const val: u16 = 1;
			var buf: [consts.u16MaxStrLen+2]u8 = undefined;
			buf[0] = val + consts.ASCIIIntOffset;
			buf[1] = consts.separator;

			for (0..std.math.maxInt(T)+1) |v| {
				const strLen = (std.fmt.bufPrint(buf[2..], "{d}", .{v}) catch unreachable).len;
				for (0..strLen) |i| {
					const str = std.fmt.bufPrint(buf[2..], "{d}", .{v}) catch unreachable;
					// push each index out of the numeric range
					str[i] += 12;
					var it = Self.init(buf[0..str.len+2]);
					try expect((it.next(T) catch unreachable).? == val);
					try expect(it.next(T) == Self.Err.InvalidCharacter);
					while (it.next(T) catch unreachable) |_| unreachable;
				}
			}
		}

		// one valid int
		{
			var buf: [consts.u16MaxStrLen]u8 = undefined;
			for (0..std.math.maxInt(T)+1) |v| {
				const str = std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable;
				var it = Self.init(str);
				try expect((it.next(T) catch unreachable).? == v);
				while (it.next(T) catch unreachable) |_| unreachable;
			}
		}

		// two valid ints (assumes that if the second passes any additional will pass)
		{
			const val: u16 = 1;
			var buf: [consts.u16MaxStrLen + 2]u8 = undefined;
			buf[0] = val + consts.ASCIIIntOffset;
			buf[1] = consts.separator;

			for (0..std.math.maxInt(T)+1) |v| {
				const len = (std.fmt.bufPrint(buf[2..], "{d}", .{v}) catch unreachable).len;
				var it = Self.init(buf[0..len+2]);
				try expect((it.next(T) catch unreachable).? == val);
				try expect((it.next(T) catch unreachable).? == v);
				while (it.next(T) catch unreachable) |_| unreachable;
			}
		}

		// three ints; first valid, second empty, third valid (assumes that if the second passes any additional will pass)
		{
			const val: u16 = 1;
			var buf: [consts.u16MaxStrLen + 3]u8 = undefined;
			buf[0] = val + consts.ASCIIIntOffset;
			buf[1] = consts.separator;
			buf[2] = consts.separator;

			for (0..std.math.maxInt(T)+1) |v| {
				const len = (std.fmt.bufPrint(buf[3..], "{d}", .{v}) catch unreachable).len;
				var it = Self.init(buf[0..len+3]);
				try expect((it.next(T) catch unreachable).? == val);
				try expect((it.next(T) catch unreachable).? == v);
				while (it.next(T) catch unreachable) |_| unreachable;
			}
		}
	}
}
