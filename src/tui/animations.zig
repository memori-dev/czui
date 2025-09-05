const std = @import("std");
const widgets = @import("widgets.zig");
const alignment = @import("alignment.zig");
const Bounds = @import("bounds.zig").Bounds;
const stdout = std.io.getStdOut().writer();

// TODO bounds handling
pub const Spinner = struct {
	const Self = @This();

	// TODO allow height and width instead of size
	size: u16 = 2,
	index: u16 = 0,
	alignment: alignment.Alignment = alignment.AlignMM,
	// TODO spinner tail
	spinner: u8 = '#',
	alive: bool = false,

	alignedBounds: Bounds = undefined,

	pub fn sigwinch(self: *Self, bounds: Bounds) !void {
		return self.render(bounds);
	}

	pub fn render(self: *Self, bounds: Bounds) !void {
		widgets.icanonSet(false);
		widgets.echoSet(false);
		_ = try stdout.write(widgets.fullWipe);
		_ = try stdout.write(widgets.cursorInvisible);

		self.alignedBounds = self.alignment.getBounds(bounds, .{self.size, self.size});

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
	pub fn rerender(self: *Self) !void {
		var x, var y = self.alignedBounds.origin();
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

		// TODO use constants
      // moveCursor eraseFromCursorToEndOfLine moveCursor spinner
      try stdout.print("\x1b[{d};0H\x1b[0K\x1b[{d};{d}H{c}", .{prevY, y, x, self.spinner});
	}

	pub fn loop(self: *Self, bounds: Bounds, delay: u64) !void {
		try self.render(bounds);
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

pub const ProgressBarOscillator = struct {
   minDelay: u64 = 10_000_000,
   diff: f32 = 0.03,
   lastTs: std.time.Instant = undefined,
   forwards: bool = true,
   pb: *widgets.ProgressBar,

   pub fn new(pb: *widgets.ProgressBar) @This() {
      return .{
         .pb = pb,
         .lastTs = std.time.Instant.now() catch unreachable,
      };
   }

   pub fn render(self: *@This()) !void {
      return self.oscillate();
   }

   pub fn oscillate(self: *@This()) !void {
      const now = std.time.Instant.now() catch unreachable;
      if (now.since(self.lastTs) <= self.minDelay) return;
      self.lastTs = now;

      var progress = self.pb.progress + if (self.forwards) self.diff else -self.diff;
      if (progress > 1) {
         self.forwards = false;
         progress = 1;
      } else if (progress < 0) {
         self.forwards = true;
         progress = 0;
      }

      try self.pb.updateProgress(progress);
   }
};

// TODO animation ideas
// pong game
// layering animations
//// ascii art text and snow falling in the background
//// render the snow first and then the ascii art text "over top"
