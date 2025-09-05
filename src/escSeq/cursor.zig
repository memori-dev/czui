const std = @import("std");
const consts = @import("consts.zig");

const stdout = std.io.getStdOut().writer();

pub const MoveCursorAbs = struct {
	const Self = @This();
	pub const printFmt: []const u8 = consts.CSI ++ "{d};{d}H";

	x: u16,
	y: u16,

	pub fn apply(x: u16, y: u16) !void {
		return stdout.print(Self.printFmt, .{y, x});
	}

	pub fn applyVec(vec: @Vector(2, u16)) !void {
		return stdout.print(Self.printFmt, .{vec[1], vec[0]});
	}
};
