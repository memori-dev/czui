const std = @import("std");
const input = @import("../input/input.zig");
const PrivateMode = @import("incantationSpec.zig").PrivateMode;
const ModeValue = @import("escSeq.zig").ModeValue;
const VariadicArgs = @import("variadicArgs.zig");

const stdout = std.io.getStdOut().writer();
const stdin  = std.io.getStdIn().writer();
const assert = std.debug.assert;

var captureX10IsSet = false;
var captureAllIsSet = false;
var mux = std.Thread.Mutex{};

// TODO remove dependency on input
// TODO better error handling

// this only works with terminal emulators that support
//// DECRQM to query private mode compatibility
//// SET_X10_MOUSE   OR   SET_ANY_EVENT_MOUSE
//// SET_SGR_EXT_MODE_MOUSE 

pub fn captureX10MouseEvents(set: bool) !void {
	mux.lock();
	defer mux.unlock();

	if (captureX10IsSet == set) return;
	captureX10IsSet = set;

	// TODO drop all input
	try stdout.print("\x1b[?9$p", .{});
	const rpm9 = input.awaitInput().escSeq.reqPrivateMode;
	assert(rpm9.privateMode == PrivateMode.sendMouseXYOnBtnPress);
	assert(rpm9.value == ModeValue.set or rpm9.value == ModeValue.reset);
	
	// TODO drop all input
	try stdout.print("\x1b[?1006$p", .{});
	const rpm1006 = input.awaitInput().escSeq.reqPrivateMode;
	assert(rpm1006.privateMode == PrivateMode.sgrMouseMode);
	assert(rpm1006.value == ModeValue.set or rpm1006.value == ModeValue.reset);

	_ = try stdout.write(if (set) "\x1b[?9;1006h" else "\x1b[?9;1006l");
}

pub fn captureAllMouseEvents(set: bool) !void {
	mux.lock();
	defer mux.unlock();

	if (captureAllIsSet == set) return;
	captureAllIsSet = set;

	// TODO drop all input
	try stdout.print("\x1b[?1003$p", .{});
	const rpm1003 = input.awaitInput().escSeq.reqPrivateMode;
	assert(rpm1003.privateMode == PrivateMode.allMotionMouseTracking);
	assert(rpm1003.value == ModeValue.set or rpm1003.value == ModeValue.reset);

	// TODO drop all input
	try stdout.print("\x1b[?1006$p", .{});
	const rpm1006 = input.awaitInput().escSeq.reqPrivateMode;
	assert(rpm1006.privateMode == PrivateMode.sgrMouseMode);
	assert(rpm1006.value == ModeValue.set or rpm1006.value == ModeValue.reset);

	_ = try stdout.write(if (set) "\x1b[?1003;1006h" else "\x1b[?1003;1006l");
}

// (v & 0b00011100) >> 2 
pub const Modifier = enum(u3) {
	const Self = @This();
	const mask = 0b00011100;

	none  = 0,
	shift = 1,
	alt   = 2,
	ctrl  = 4,
};

// v & 0b11100011
pub const Event = enum(u8) {
	const mask = 0b11100011;

	leftPress   =  0,
	middlePress =  1,
	rightPress  =  2,

	leftDrag    = 32,
	middleDrag  = 33,
	rightDrag   = 34,
	move        = 35,

	scrollUp    = 64,
	scrollDown  = 65,
	scrollLeft  = 66,
	scrollRight = 67,

	button8     = 128,
	button9     = 129,
	button10    = 130,
	button11    = 131,
};

pub const MouseEvent = packed struct {
	const Self = @This();

	event:     Event,
	modifier:  u3,
	// 'm' denotes release, else 'M'
	isRelease: bool,
	x:         u16,
	y:         u16,

	pub fn parse(bytes: []const u8) !Self {
		if (bytes[0] != '<') return error.InvalidFormat;
		var it = VariadicArgs.init(bytes[1..bytes.len-1]);
		const eventModifier = try it.nextBetter(u8) orelse return error.InvalidFormat;


		return .{
			.event    = try std.meta.intToEnum(Event, eventModifier & Event.mask),
			.modifier = @truncate((eventModifier & Modifier.mask) >> 2),
			.isRelease = bytes[bytes.len-1] == 'm',
			.x = try it.nextBetter(u16) orelse return error.InvalidFormat,
			.y = try it.nextBetter(u16) orelse return error.InvalidFormat,
		};
	}
};
