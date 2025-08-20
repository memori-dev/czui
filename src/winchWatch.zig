const std = @import("std");

var activeScreen: ?*anyopaque = null;
var renderFn: ?*const fn (ptr: *anyopaque) anyerror!void = null;
var mux: std.Thread.Mutex = std.Thread.Mutex{};

pub fn setActiveScreen(ptr: anytype) void {
	mux.lock();
	defer mux.unlock();

	const T = @TypeOf(ptr);
	const ptr_info = @typeInfo(T);	
	const gen = struct {
		pub fn render(pointer: *anyopaque) anyerror!void {
			const self: T = @ptrCast(@alignCast(pointer));
			return ptr_info.@"pointer".child.render(self);
		}
	};

	activeScreen = ptr;
	renderFn = gen.render;
}

fn winchHandler(_: c_int) callconv(.C) void {
	mux.lock();
	defer mux.unlock();

	if (activeScreen) |v| renderFn.?(v) catch {};
}

pub fn init() void {
	const act = std.os.linux.Sigaction {
		.handler = .{ .handler = winchHandler },
		.mask = std.os.linux.empty_sigset,
		.flags = 0,
	};
	_ = std.os.linux.sigaction(std.os.linux.SIG.WINCH, &act, null);
}
