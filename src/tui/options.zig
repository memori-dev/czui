const std = @import("std");
const Graphics = @import("../escSeq/graphics.zig").Graphics;
const widgets = @import("widgets.zig");
const alignment = @import("alignment.zig");
const Bounds = @import("bounds.zig").Bounds;
const Size = @import("bounds.zig").Size;
const Point = @import("bounds.zig").Point;
const Input = @import("../input/input.zig").Input;
const mouse = @import("../escSeq/mouse.zig");
const Spacing = @import("spacing.zig").Spacing;
const overflow = @import("overflow.zig");
const cursor = @import("../escSeq/cursor.zig");

const stdout = std.io.getStdOut().writer();

pub const Layout = enum {
	vertical,
	horizontal,
};

// TODO collapsible

// TODO vertical bar
//// .layout == .vertical
////// uses min width and max height to print every option
			//if (self.layout == .vertical) {
				//var longest: u16 = 0;
				//inline for (texts, 0..) |text, i| {
					//if (text.len > writableWidth and self.overflow == .err) return error.TextOverflow;
					//height += 1 + self.gap;
					//if (text.len > longest) longest = text.len;
				//}

				//width += longest;

				// subtract last gap as there are no proceeding options
				//height -= self.gap;

				//if (height > bHeight)

				// TODO test height doesnt exceed
				// TODO set height to max
			//}

pub fn HorizontalBar(comptime Options: type) type {
	const ti = comptime @typeInfo(Options).@"enum";

	const fields: [ti.fields.len]Options = blk: {
		var out: [ti.fields.len]Options = undefined;
		inline for (ti.fields, 0..) |field, i| out[i] = @field(Options, field.name);

		break :blk out;
	};

	const keys: [ti.fields.len]u8 = blk: {
		const hasKeyMethod = std.meta.hasMethod(Options, "key");
		var out: [ti.fields.len]u8 = undefined;
		inline for (fields, 0..) |field, i| {
			out[i] = if (hasKeyMethod) field.key()
						else if (i < 26) 'a' + i
						else if (i < 52) 'A' + i - 26
						else if (i <= 62) '0' + i - 52
						else unreachable;
		}

		break :blk out;
	};

	const texts: [ti.fields.len][]const u8 = blk: {
		const hasTextMethod = std.meta.hasMethod(Options, "text");
		var out: [ti.fields.len][]const u8 = undefined;
		inline for (fields, 0..) |field, i| out[i] = if (hasTextMethod)  field.text() else @tagName(field);

		break :blk out;
	};

	return struct {
		const Self = @This();

		style: Graphics = .{
			.fg = .{.type = .pallet256, .val = 0},
			.bg = .{.type = .pallet256, .val = 117},
		},
		highlightStyle: Graphics = .{
			.fg = .{.type = .pallet256, .val = 0},
			.bg = .{.type = .pallet256, .val = 255},
		},
		bg: Graphics = .{
			.bg = .{.type = .pallet256, .val = 117},
		},

		// TODO alignment: alignment.Align = .origin,
		// TODO text alignment
		// TODO padding
		margin: Spacing = .{},
		gap:    u16    = 1,

		highlighted: ?usize = null,

		// calc'd
		width: u16 = 0,
		height: u16 = 0,
		origin: Point = undefined,
		fieldOrigins: [ti.fields.len]Point = undefined,

		fn calcLayout(self: *Self, bounds: Bounds) !void {
			const innerBounds = try self.margin.innerBounds(bounds);
			const writableWidth, const writableHeight = innerBounds.size();

			var xOffset: u16 = 0;
			var yOffset: u16 = 0;
			inline for (texts, 0..) |text, i| {
				const textLen = @min(@as(u16, @truncate(text.len + 4)), writableWidth);

				if (xOffset + textLen > writableWidth) {
					if (yOffset + 1 >= writableHeight) return error.Overflow;

					xOffset = 0;
					yOffset += 1;
				}

				self.fieldOrigins[i] = .{innerBounds.x[0] + xOffset, innerBounds.y[0] + yOffset};
				xOffset += textLen + self.gap;
			}

			self.origin = innerBounds.origin();
			self.width = writableWidth;
			self.height = yOffset + 1;
		}

		pub fn render(self: *Self, bounds: Bounds) !Bounds {
			try self.calcLayout(bounds);

			// apply background
			_ = try self.bg.set(stdout);
			for (0..self.height) |yOffset| try stdout.print(
				cursor.MoveCursorAbs.printFmt ++
				// TODO make ansi esc sequences constants
				"\x1b[{d}X",
				.{self.origin[1] + yOffset, self.origin[0], self.width},
			);

			// print options
			for (0..texts.len) |i| try self.renderOption(i);

			return Bounds.newFromOriginSize(self.origin, .{self.width, self.height});
		}

		fn renderOption(self: Self, i: usize) !void {
			try cursor.MoveCursorAbs.applyPoint(self.fieldOrigins[i]);
			
			const style = if (self.highlighted != null and self.highlighted.? == i) self.highlightStyle else self.style;
			_ = try style.apply(stdout);
			
			const len = @min(self.width, texts[i].len + 4);
			if (len < texts[i].len + 4) _ = try stdout.print("[{c}] {s}{s}\x1b[m", .{keys[i], texts[i][0..len-|5], overflow.TextOverflow.charSentinel})
			else try stdout.print("[{c}] {s}\x1b[m", .{keys[i], texts[i]});
		}

		pub fn updateHighlighted(self: *Self, highlighted: ?usize) !void {
			const prev = self.highlighted;
			self.highlighted = highlighted;

			if (prev) |v| try self.renderOption(v);
			if (highlighted) |v| try self.renderOption(v);
		}

		fn mouseIntersectsOption(self: Self, me: mouse.MouseEvent) ?usize {
			for (0..texts.len) |i| {
				const x, const y = self.fieldOrigins[i];
				if (me.y == y and me.x >= x and me.x < x + texts[i].len + 4) return i;
			}

			return null;
		}

		fn handleMouse(self: *Self, me: mouse.MouseEvent) !?Options {
			switch (me.event) {
				.leftPress => {
					const intersection = self.mouseIntersectsOption(me);

					// update highlight on press, return selected on release
					if (!me.isRelease) try self.updateHighlighted(intersection)
					else if (intersection) |v| return fields[v];
				},
				.move => try self.updateHighlighted(self.mouseIntersectsOption(me)),
				else => {},
			}

			return null;
		}

		pub fn handleInput(self: *Self, input: Input) !?Options {
			switch (input) {
				// mouse
	         .escSeq => |v| switch (v) {
	         	.mouse => |m| return self.handleMouse(m),
	         	else => {},
	         },
	         // select using key
	         .ascii => |v| for (0..keys.len) |i| if (keys[i] == v) return fields[i],
         	else => {},
      	}

      	return null;
		}
	};
}
