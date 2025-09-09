const std = @import("std");

const stdout = std.io.getStdOut().writer();
const stdoutHandle = std.io.getStdOut().handle;
const assert = std.debug.assert;

// origin is {1, 1}
// winsize is inclusive @ min & max
//// x [1, winsize.col]
//// y [1, winsize.row]
pub fn getWindowSize(errno: ?*std.posix.E) !std.posix.winsize {
   var winsize: std.posix.winsize = undefined;
   const err = std.posix.errno(
   	std.posix.system.ioctl(stdoutHandle, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize))
   );

   if (errno) |e| e.* = err;
   if (err == .SUCCESS) return winsize;
   return error.CheckErrno;
}

pub const Size = @Vector(2, u16);

pub const Point = @Vector(2, u16);
pub const windowOrigin = Point{1, 1};

pub const Offset = @Vector(2, u16);

// .{min, max}
// half open [min, max)
// min >= 1
// max >= min
pub const Bound = @Vector(2, u16);

// TODO asserts
pub const Bounds = struct {
	const Self = @This();

	x: Bound,
	y: Bound,

	pub fn newFromOriginSize(orig: Point, siz: Size) !Self {
		return .{.x = .{orig[0], orig[0] + siz[0]}, .y = .{orig[1], orig[1] + siz[1]}};
	}

	pub fn newFromWinsize(winsize: std.posix.winsize) Self {
		// 1 is added as Bound is half open and winsize is inclusive
		return .{.x = .{1, winsize.col + 1}, .y = .{1, winsize.row + 1}};
	}

	pub fn new(errno: ?*std.posix.E) !Self {
		const winsize = try getWindowSize(errno);
		return Self.newFromWinsize(winsize);
	}

	pub fn origin(self: Self) Point {
		return .{self.x[0], self.y[0]};
	}

	pub fn end(self: Self) Point {
		return .{self.x[1] - 1, self.y[1] - 1};
	}

	pub fn width(self: Self) u16 {
		return self.x[1] - self.x[0];
	}

	pub fn height(self: Self) u16 {
		return self.y[1] - self.y[0];
	}

	pub fn size(self: Self) Size {
		return .{self.width(), self.height()};
	}

	pub fn area(self: Self) u32 {
		return self.width() * self.height();
	}

	pub fn collides(self: Self, x: u16, y: u16) bool {
		return x >= self.x[0] and
				 x <= self.x[1] and
				 y >= self.y[0] and
				 y <= self.y[1];
	}

	pub fn offsetFromIndex(self: Self, index: u32) !Offset {
		const w, const h = self.size();

		const x: u16 = @truncate(index % w);
		const y: u16 = @truncate(index / w);

		if (y >= h) return error.OffsetIsOutOfBounds;

		return .{x, y};
	}

	pub fn pointFromOffset(self: Self, offset: Offset) !Point {
		const w, const h = self.size();
		if (offset[0] >= w) return error.OffsetXIsOutOfBounds;
		if (offset[1] >= h) return error.OffsetYIsOutOfBounds;

		return .{self.x[0] + offset[0], self.y[0] + offset[1]};
	}

	pub fn shiftOffsetForwards(self: Self, offset: Offset, index: u32) !Offset {
		return self.offsetFromIndex(index + self.offsetIndex(offset));
	}

	pub fn shiftOffsetBackwards(self: Self, offset: Offset, index: u32) !Offset {
		const w = self.width();
		const sum = offset.x + (offset.y * w) - index;

		return self.offsetFromIndex(sum);
	}

	pub fn offsetIndex(self: Self, offset: Offset) u32 {
		return offset[0] + (offset[1] * self.width());
	}

	pub fn eql(a: Self, b: Self) bool {
		return a.x[0] == b.x[0] and
				 a.x[1] == b.x[1] and
				 a.y[0] == b.y[0] and
				 a.y[1] == b.y[1];
	}

	pub fn wipe(self: Self) !void {
		_ = try stdout.write("\x1b[m");
		for (self.y[0]..self.y[1]) |y| {
			// TODO make escSeq constants
			try stdout.print("\x1b[{d};{d}H\x1b[{d}X", .{y, self.x[0], self.x[1] - self.x[0]});
		}
	}

	// TODO fns for updating x and y error{MaxLessThanOne, MinLessThanOne, MinGreaterThanMax}!
};
