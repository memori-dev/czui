const std = @import("std");
const Bounds = @import("bounds.zig").Bounds;

var errHandler:    ?*const fn (err: anyerror) void                            = null;
var activeDisplay: ?*anyopaque                                                = null;
var rerenderFn:    ?*const fn (ptr: *anyopaque, bounds: Bounds) anyerror!void = null;
var prevBounds:    ?Bounds                                                    = null;
var mux = std.Thread.Mutex{};

fn winchHandler(_: c_int) callconv(.C) void {
	mux.lock();
	defer mux.unlock();

	const bounds = Bounds.new(null) catch |err| {
		if (errHandler) |eh| eh(err);
		return;
	};

	if (prevBounds) |v| if (std.meta.eql(v.x, bounds.x) and std.meta.eql(v.y, bounds.y)) return;
	prevBounds = bounds;

	if (activeDisplay) |v| rerenderFn.?(v, bounds) catch |err| if (errHandler) |eh| eh(err);
}

pub fn setErrHandler(eh: *const fn (err: anyerror) void) void {
	mux.lock();
	defer mux.unlock();

	errHandler = eh;
}

pub fn rerenderOnUpdate(display: anytype) void {
	mux.lock();
	defer mux.unlock();

	const act = std.os.linux.Sigaction {
		.handler = .{.handler = winchHandler},
		.mask = std.os.linux.empty_sigset,
		.flags = 0,
	};
	_ = std.os.linux.sigaction(std.os.linux.SIG.WINCH, &act, null);

	const T = @TypeOf(display);
	const ptr_info = @typeInfo(T);
	const gen = struct {
		pub fn render(pointer: *anyopaque, bounds: Bounds) anyerror!void {
			const self: T = @ptrCast(@alignCast(pointer));
			return ptr_info.@"pointer".child.sigwinch(self, bounds);
		}
	};

	activeDisplay = display;
	rerenderFn = gen.render;
}

pub fn stopRerenderOnUpdate() void {
	mux.lock();
	defer mux.unlock();

	const act = std.os.linux.Sigaction {
		.handler = .{.handler = null},
		.mask = std.os.linux.empty_sigset,
		.flags = 0,
	};
	_ = std.os.linux.sigaction(std.os.linux.SIG.WINCH, &act, null);

	activeDisplay = null;
	rerenderFn = null;
	prevBounds = null;
}
