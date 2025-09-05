const std = @import("std");

const stdout = std.io.getStdOut().writer();
const stdoutHandle = std.io.getStdOut().handle;

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

// .{min, max}
// half open [min, max)
// min >= 1
// max >= min
pub const Bound = @Vector(2, u16);

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

	pub fn width(self: Self) u16 {
		return self.x[1] - self.x[0];
	}

	pub fn height(self: Self) u16 {
		return self.y[1] - self.y[0];
	}

	pub fn size(self: Self) Size {
		return .{self.width(), self.height()};
	}

	pub fn wipe(self: Self) !void {
		_ = try stdout.write("\x1b[m");
		for (self.y[0]..self.y[1]) |y| {
			// TODO make escSeq constants
			_ = try stdout.write("\x1b[{d};{d}H\x1b[{d}X", .{y, self.x[0], self.x[1] - self.x[0]});
		}
	}

	// TODO fns for updating x and y error{MaxLessThanOne, MinLessThanOne, MinGreaterThanMax}!
};
