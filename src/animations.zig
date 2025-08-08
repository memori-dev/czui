const std = @import("std");
const widgets = @import("widgets.zig");
const stdout = std.io.getStdOut().writer();

pub const Spinner = struct {
	// TODO allow height and width instead of size
	size: u16 = 2,
	index: u16 = 0,
	winsize: std.posix.winsize = undefined,
	alignment: widgets.Alignment = widgets.AlignCM,
	// TODO spinner tail
	spinner: u8 = '#',
	alive: bool = false,

	pub fn render(self: *@This()) !void {
		self.winsize = try widgets.getWindowSize(null);
		widgets.icanonSet(false);
		widgets.echoSet(false);
		_ = try stdout.write(widgets.fullWipe);
		_ = try stdout.write(widgets.cursorInvisible);

		try self.rerender();
	}

	// 1 million render iterations
	// 82450.898ms - full render
	//// _ = try stdout.write(fullWipe);
	// 26081.014ms - selective render
	//// added prevY
	//// cheated by making self.index the previous instead of current
	//// try moveCursor(0, prevY)
   //// _ = try stdout.write(eraseFromCursorToEndOfLine);
	// 17524.820ms - Single print render
	//// changed the 4 calls to write with a single print
   //// try stdout.print("\x1b[{d};0H\x1b[0K\x1b[{d};{d}H{c}", .{prevY, y, x, self.spinner});
   // NB: selective render was also more stable visually at these extreme refresh rates
	pub fn rerender(self: *@This()) !void {
		var x, var y = self.alignment.origin(self.winsize, self.size, self.size);
		var prevY = y;

		//  → →   
		//  0 1 2 ↓
		// ↑3 4 5 ↓
		// ↑6 7 8
		//    ← ←

		// right
		if (self.index <= self.size - 2) {
			self.index += 1;
			x += self.index;
		}
		// down
		else if (self.index != (self.size*self.size) - 1 and self.index % self.size == self.size - 1) {
			prevY += self.index / self.size;

			self.index += self.size;
			x += self.size - 1;
			y += self.index / self.size;
		}
		// left
		else if (self.index > self.size * (self.size - 1) and self.index < self.size * self.size) {
			prevY += self.size - 1;

			self.index -= 1;
			x += self.index % self.size;
			y += self.size - 1;
		}
		// up
		else if (self.index != 0 and self.index % self.size == 0) {
			prevY += self.index / self.size;

			self.index -= self.size;
			y += self.index / self.size;
		}
		else unreachable;

      // moveCursor eraseFromCursorToEndOfLine moveCursor spinner
      try stdout.print("\x1b[{d};0H\x1b[0K\x1b[{d};{d}H{c}", .{prevY, y, x, self.spinner});
	}

	pub fn loop(self: *@This(), delay: u64) !void {
		try self.render();
		self.alive = true;
		var lastTs = std.time.Instant.now() catch unreachable;

		while (self.alive) {
			const now = std.time.Instant.now() catch unreachable;
			if (now.since(lastTs) <= delay) continue;
			lastTs = now;

			try self.rerender();
		}
	}
};
