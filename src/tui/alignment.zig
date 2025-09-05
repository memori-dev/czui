const std = @import("std");
const Bound = @import("bounds.zig").Bound;
const Bounds = @import("bounds.zig").Bounds;
const Size = @import("bounds.zig").Size;
const Point = @import("bounds.zig").Point;

// origin: 1, 1
// writable area is inclusive of winsize
//// x [1, winsize.col]
//// y [1, winsize.row]
pub const Align = enum {
	const Self = @This();

	origin,
	middle,
	ending,
	// TODO stretch
	// TODO space

	fn getBound(self: Self, bound: Bound, size: u16) Bound {
		const min, const max = bound;

		switch(self) {
			.origin => return .{min, @min(min + size, max)},
			.middle => {
				const padding: u16 = @divTrunc(max -| min -| size, 2);
				return .{min + padding, max - padding};
			},
			.ending => return .{@max(max -| size, 1), max},
		}
	}
};

pub const Alignment = struct {
	const Self = @This();

	x: Align,
	y: Align,

	pub fn getBounds(self: Self, bounds: Bounds, size: Size) Bounds {
		return .{.x = self.x.getBound(bounds.x, size[0]), .y = self.y.getBound(bounds.y, size[1])};
	}
};

// T -> TOP,  M -> Middle, B -> Bottom
// L -> Left, M -> Middle, R -> Right
pub const AlignTL = Alignment{.x = .origin, .y = .origin};
pub const AlignTM = Alignment{.x = .middle, .y = .origin};
pub const AlignTR = Alignment{.x = .ending, .y = .origin};
pub const AlignML = Alignment{.x = .origin, .y = .middle};
pub const AlignMM = Alignment{.x = .middle, .y = .middle};
pub const AlignMR = Alignment{.x = .ending, .y = .middle};
pub const AlignBL = Alignment{.x = .origin, .y = .ending};
pub const AlignBM = Alignment{.x = .middle, .y = .ending};
pub const AlignBR = Alignment{.x = .ending, .y = .ending};

pub const Alignments = [_]Alignment{AlignTL,AlignTM,AlignTR,AlignML,AlignMM,AlignMR,AlignBL,AlignBM,AlignBR};
