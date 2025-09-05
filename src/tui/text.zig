const std = @import("std");
const widgets = @import("widgets.zig");
const alignment = @import("alignment.zig");
const charTextOverflowSentinel = @import("overflow.zig").TextOverflow.charSentinel;
const Overflow = @import("overflow.zig").Overflow;
const TextOverflow = @import("overflow.zig").TextOverflow;
const Bounds = @import("bounds.zig").Bounds;
const Graphics = @import("../escSeq/graphics.zig").Graphics;
const Size = @import("bounds.zig").Size;

const stdout = std.io.getStdOut().writer();

// TODO comptime and runtime versions
// TODO ansi esc / unicode / grapheme
pub const Text = struct {
	const Self = @This();

	styledText:   widgets.StyledText = .{.text = "lauren gypsum"},
	alignment:    alignment.Alignment  = alignment.AlignMM,
	overflow:     Overflow = .clip,
	textOverflow: TextOverflow = .clip,

	pub fn getAlignmentBounds(self: Self, bounds: Bounds) !Bounds {
		const bWidth, const bHeight = bounds.size();

		var maxWidth: u16 = 0;
		var maxHeight: u16 = 0;
		var iter = std.mem.splitScalar(u8, self.styledText.text, '\n');
		while (iter.next()) |v| {
			// textOverflow
			maxHeight += switch (self.textOverflow) {
				// overflow is ignored and lines are represented 1:1
				.clip, .sentinel => 1,
				// 1 is subtracted to ensure that at least 1 char will be on the next line
				.wrap => 1 + @as(u16, @truncate((v.len -| 1) / bWidth)),
				// return error on overflow, else lines are represented 1:1
				.err => if (v.len > bWidth) return error.TextOverflow else 1,
			};

			if (v.len > maxWidth) maxWidth = @intCast(v.len);
		}
		maxWidth = @min(bWidth, maxWidth);

		// overflow
		maxHeight = switch (self.overflow) {
			// both are capped to bHeight
			.clip, .sentinel => @min(bHeight, maxHeight),
			// return error on overflow, else valid
			.err => if (maxHeight > bHeight) return error.Overflow else maxHeight,
		};

		return self.alignment.getBounds(bounds, .{maxWidth, maxHeight});
	}

	pub fn sigwinch(self: *Self, bounds: Bounds) !void {
		_ = try self.render(bounds);
	}

	pub fn render(self: Self, bounds: Bounds) !Size {
		const alignmentBounds = try self.getAlignmentBounds(bounds);
		const maxY = alignmentBounds.y[1];
		const width = alignmentBounds.width();

		// apply style
		if (self.styledText.style) |style| {
			try widgets.moveCursor(alignmentBounds.x[0], alignmentBounds.y[0]);
			_ = try style.apply(stdout);
		}

		var lineIter = std.mem.splitScalar(u8, self.styledText.text, '\n');
		const x = alignmentBounds.x[0];
		var y = alignmentBounds.y[0];
		while (lineIter.next()) |line| {
			switch (self.overflow) {
				.clip => if (y >= maxY) break,
				.sentinel => if (y == maxY - 1 and lineIter.peek() != null) {
					_ = try stdout.write(charTextOverflowSentinel);
					break;
				},
				// getAlignmentBounds should never allow this
				.err => if (y > maxY) unreachable,
			}

			switch (self.textOverflow) {
				.clip => {
					try widgets.moveCursor(x, y);
					_ = try stdout.write(line[0..@min(width, line.len)]);
				},
				.sentinel => {
					try widgets.moveCursor(x, y);
					if (line.len <= width) {
						_ = try stdout.write(line);
						continue;
					}

					_ = try stdout.write(line[0..width-1]);
					_ = try stdout.write(charTextOverflowSentinel);
				},
				.wrap => {
					var wrapIter = std.mem.window(u8, line, width, width);
					while (wrapIter.next()) |w| {
						try widgets.moveCursor(x, y);
						_ = try stdout.write(w);
						y += 1;

						if (y >= maxY) continue;
					}
				},
				.err => {
					// getAlignmentBounds should never allow this
					if (line.len > width) unreachable;
					_ = try stdout.write(line);
				},
			}
		}

		if (self.styledText.style != null) _ = try stdout.write(&Graphics.defaultStr);

		return alignmentBounds.size();
	}
};
