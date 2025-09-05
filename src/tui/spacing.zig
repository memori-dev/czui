const Bounds = @import("bounds.zig").Bounds;

pub const Spacing = struct {
	const Self = @This();

	top:    u16 = 0,
	right:  u16 = 0,
	bottom: u16 = 0,
	left:   u16 = 0,

	pub fn vertical(margin: u16) Self {
		return .{.top = margin, .bottom = margin};
	}

	pub fn horizontal(margin: u16) Self {
		return .{.right = margin, .left = margin};
	}

	pub fn even(margin: u16) Self {
		return .{.top = margin, .right = margin, .bottom = margin, .left = margin};
	}

	pub fn innerBounds(self: Self, bounds: Bounds) !Bounds {
		var out = bounds;
		out.x[0] += self.left;
		out.x[1] -|= self.right;
		out.y[0] += self.top;
		out.y[1] -|= self.bottom;

		if (out.x[1] -| out.x[0] == 0) return error.ZeroWidth;
		if (out.y[1] -| out.y[0] == 0) return error.ZeroHeight;

		return out;
	}
};
