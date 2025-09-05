const std = @import("std");
const Graphics = @import("../escSeq/graphics.zig").Graphics;
const alignment = @import("alignment.zig");
const input = @import("../input/input.zig");
const Bounds = @import("bounds.zig").Bounds;
const cursor = @import("../escSeq/cursor.zig");
const mouse = @import("../escSeq/mouse.zig");
const widgets = @import("widgets.zig");

const assert = std.debug.assert;
const stdout = std.io.getStdOut().writer();

// TODO cleanup
pub fn Menu(comptime Options: type) type {
	const ti = comptime @typeInfo(Options).@"enum";

	const fields: [ti.fields.len]Options = blk: {
		var out: [ti.fields.len]Options = undefined;
		inline for (ti.fields, 0..) |field, i| out[i] = @field(Options, field.name);

		break :blk out;
	};

	const texts: [ti.fields.len][]const u8 = blk: {
		const hasTextMethod = std.meta.hasMethod(Options, "text");
		var out: [ti.fields.len][]const u8 = undefined;
		inline for (fields, 0..) |field, i| out[i] = if (hasTextMethod) field.text() else @tagName(field);

		break :blk out;
	};

	const width = blk: {
		var out: usize = 0;
		inline for (texts) |text| out = @max(out, text.len);
		break :blk out;
	};

	return struct {
		const Self = @This();

		selected: usize = 0,

		selStyle: Graphics = .{
			.fg = .{.type = .rgb, .val = (65 << 16) + (90 << 8) + 119},
			.bold = .set, .underline = .set,
		},
		unselStyle: Graphics = .{
			.fg = .{.type = .rgb, .val = (35 << 16) + (60 << 8) + 89},
		},

		alignment: alignment.Alignment = alignment.AlignMM,

		pub fn rerender(self: *Self, bounds: Bounds, prev: usize) !void {
			const alignedBounds = self.alignment.getBounds(bounds, .{@truncate(width), fields.len});
			const x, const y = alignedBounds.origin();
			
			try cursor.MoveCursorAbs.apply(x, y + @as(u16, @truncate(prev)));
			_ = try self.unselStyle.write(stdout, texts[prev]);

			try cursor.MoveCursorAbs.apply(x, y + @as(u16, @truncate(self.selected)));
			_ = try self.selStyle.write(stdout, texts[self.selected]);
		}

		fn updateSelected(self: *Self, bounds: Bounds, increment: bool) !void {
			assert(self.selected < ti.fields.len);

			const prev = self.selected;

			if (increment) {
				self.selected += 1;
				// overflow
				if (self.selected == fields.len) self.selected = 0;
			} else {
				// underflow
				if (self.selected == 0) self.selected = fields.len;
				self.selected -= 1;
			}

			try self.rerender(bounds, prev);
		}

		fn mouseIntersectsOption(self: Self, bounds: Bounds, me: mouse.MouseEvent) ?usize {
			const alignedBounds = self.alignment.getBounds(bounds, .{@truncate(width), fields.len});
			const x, var y = alignedBounds.origin();

			for (0..texts.len) |i| {
				if (me.y == y and me.x >= x and me.x < x + texts[i].len) return i;
				y += 1;
			}

			return null;
		}

		fn handleMouse(self: *Self, bounds: Bounds, me: mouse.MouseEvent) !?Options {
			switch (me.event) {
				.leftPress => {
					// update highlight on press, return selected on release
					if (self.mouseIntersectsOption(bounds, me)) |v| {
						if (me.isRelease) return fields[v];
						
						const prev = self.selected;
						self.selected = v;
						try self.rerender(bounds, prev);
					}
				},
				.move => if (self.mouseIntersectsOption(bounds, me)) |v| {
					const prev = self.selected;
					self.selected = v;
					try self.rerender(bounds, prev);
				},
				else => {},
			}

			return null;
		}

		pub fn sigwinch(self: *Self, bounds: Bounds) !void {
			return self.render(bounds);
		}

		pub fn render(self: *Self, bounds: Bounds) !void {
			widgets.icanonSet(false);
			widgets.echoSet(false);
	      try mouse.captureAllMouseEvents(true);
			_ = try stdout.write(widgets.cursorInvisible);
			_ = try stdout.write(widgets.fullWipe);

			const alignedBounds = self.alignment.getBounds(bounds, .{@truncate(width), fields.len});
			const x, var y = alignedBounds.origin();
			for (0..texts.len) |i| {
				try cursor.MoveCursorAbs.apply(x, y);
				if (self.selected == i) _ = try self.selStyle.write(stdout, texts[i])
				else _ = try self.unselStyle.write(stdout, texts[i]);
				
				y += 1;
			}
		}

		pub fn getSelection(self: *Self, bounds: Bounds) !Options {
			try self.render(bounds);

			while (true) switch (input.awaitInput()) {
				.escSeq => |v| switch (v) {
					.moveCursorUp       => try self.updateSelected(bounds, false),
	         	.cursorBackwardsTab => try self.updateSelected(bounds, false),
					.moveCursorDown     => try self.updateSelected(bounds, true),
	         	.mouse              => |m| if (try self.handleMouse(bounds, m)) |out| return out,
					else => {},
				},
				.ascii => |v| switch (v) {
					0x9 => try self.updateSelected(bounds, true),
					0xa => return fields[self.selected],
					else => {},
				},
				else => {},
			};
		}
	};
}
