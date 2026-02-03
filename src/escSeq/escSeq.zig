const std = @import("std");
const consts = @import("consts.zig");
const VariadicArgs = @import("variadicArgs.zig");
const stdout = std.io.getStdOut().writer();
const assert = std.debug.assert;

const FnKey = @import("fnKey.zig").FnKey;
const NavKey = @import("singularArg.zig").NavKey;

const EraseDisplay = @import("singularArg.zig").EraseDisplay;
const EraseLine = @import("singularArg.zig").EraseLine;

const SetResetMode = @import("_genHighLow.zig").SetResetMode;
const PrivateMode = @import("_genHighLow.zig").PrivateMode;

const Graphics = @import("graphics.zig").Graphics;

const DeviceStatusReport = @import("singularArg.zig").DeviceStatusReport;

const CursorStyle = @import("singularArg.zig").CursorStyle;
const PrivateModeSpec = @import("incantationSpec.zig").PrivateMode;

const cursor = @import("cursor.zig");

const mouse = @import("mouse.zig");

// Quick intro
//// https://notes.burke.libbey.me/ansi-escape-codes/
// References
//// https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Functions-using-CSI-_-ordered-by-the-final-character_s_
//// https://man7.org/linux/man-pages/man4/console_codes.4.html
// Combo examples
//// https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
//// https://gitlab.com/greggink/youtube_episode_terminal_control_2/-/blob/main/tc.h

fn parseFirstInteger(comptime T: type, bytes: []const u8) ?T {
	var it = std.mem.splitSequence(u8, bytes, ";");
	const res = std.fmt.parseInt(T, it.first(), 10);
	if (res) |v| return v
	else |_| return null;
}

pub const ModeValue = enum(u3) {
	notRecognized = 0,
	set           = 1,
	reset         = 2,
	permSet       = 3,
	permReset     = 4,
};

// \x1b[?{privateMode};{value}$y
pub const ReqPrivateMode = struct {
	const Self = @This();

	privateMode: PrivateModeSpec,
	value:       ModeValue,

	pub fn parse(bytes: []const u8) !Self {
		if (bytes[0] != '?') return error.InvalidFormat;
		if (bytes[bytes.len-1] != '$') return error.InvalidFormat;

		var it = VariadicArgs.init(bytes[1..bytes.len-1]);
		return .{
			.privateMode = try std.meta.intToEnum(PrivateModeSpec, try it.nextBetter(u11) orelse return error.InvalidFormat),
			.value = try std.meta.intToEnum(ModeValue, try it.nextBetter(u3) orelse return error.InvalidFormat),
		};
	}
};

// TODO control keys?
// all unsigned ints have a default value of 1
pub const EscSeq = union(enum) {
	const Self = @This();

	fnKey: FnKey,
	// ~(x)
	navKey: NavKey,

	// @(?x) - insert x (default 1) blank chars
	insertBlankChars: u16,
	// L(?x) - insert x (default 1) blank lines above
	insertBlankLines: u16,


	// A(?x) - move cursor up x (default 1) rows
	moveCursorUp: u16,
	// TODO: CSI Ps e, is apparently the same fn but didnt work
	// B(?x) - move cursor down x (default 1) rows
	moveCursorDown: u16,
	// C(?x) - move cursor right x (default 1) cols
	moveCursorRight: u16,
	// D(?x) - move cursor left x (default 1) cols
	moveCursorLeft: u16,


	// E(?x) - move cursor to start of next line, x (default 1) lines down
	moveCursorToStartOfNextLine: u16,
	// F(?x) - moves cursor to start of prev line, x (default 1) lines up
	// TODO this and the 'end' key have a collision, but don't do the same thing
	// TODO im also seeing 'end' being SS3 instead of CSI, but isn't the case when testing
	moveCursorToStartOfPrevLine: u16,


	// G(?x) - moves cursor to column x (default 1)
	moveCursorAbsCol: u16,
	// d(?x) - moves cursor to row x (default 1)
	moveCursorAbsRow: u16,


	// H(?y, ?x) - move cursor to y (default 1), x (default 1)
	// f(?y, ?x) - move cursor to y (default 1), x (default 1)
	moveCursorAbs: cursor.MoveCursorAbs,


	// I(?x) - Cursor Forward Tabulation x (default 1) tab stops
	cursorForwardsTab: u16,
	// Z(?x) - cursor backward tabulation x (default 1) tab stops
	// shift + tab
	cursorBackwardsTab: u16,


	// TODO vt220 "ESC[?xJ" variant?
	// J(?x)
	eraseDisplay: EraseDisplay,
	// TODO vt220 "ESC[?xK" variant?
	// K(?x)
	eraseLine: EraseLine,
	// X(?x) - erase x (default 1) chars on current line
	eraseChars: u16,


	// M(?x) - delete x (default 1) lines
	deleteLines: u16,
	// P(?x) - delete x (default 1) chars on current line
	deleteChars: u16,


	// S(?x) - scroll up x (default 1) lines
	scrollUp: u16,
	// T(?x) - scroll down x (default 1) lines
	scrollDown: u16,


	// b(?x) - repeat preceeding char x (default 1) times
	repeatPreceedingChar: u16,


	// {h/l}(...x)
	setResetMode: SetResetMode,
	// ?{h/l}(...x)
	privateMode: PrivateMode,
	// TODO i dont see any results from this and there were no changes when trying reported x values
	// ={h/l}(...x) -> (un)set screen mode
	//screenMode: ScreenMode,


	reqPrivateMode: ReqPrivateMode,


	// m(...x) - sets graphics dependant upon x (default 0)
	graphics: Graphics,

	// <{event};{x};{y}M
	// <{event};{x};{y}m
	mouse: mouse.MouseEvent,


	// n(x)
	deviceStatusReport: DeviceStatusReport,


	// " q"(?x)
	setCursorStyle: CursorStyle,


	// s() - save cursor position
	saveCursorPosition: void,
	// u() - restores the cursor to the last saved position
	restoreCursorPosition: void,

	unknown: void,

	pub fn parse(bytes: []const u8) !struct{Self, usize} {
		if (bytes.len < 3) return error.InsufficientLen;
		if (bytes[0] != consts.ESC) return error.IncorrectFormat;

		switch (bytes[1]) {
			// FnKey F1 to F4
			0x4f => {
				const fnKey, const len = try FnKey.parse(bytes);
				return .{.{.fnKey = fnKey}, len};
			},

			0x5b => {
				// having one instance of ParseErr.InsufficientLen will coerce to that over no match
				var encounteredInsufficientLen = false;

				if (FnKey.parse(bytes)) |res| return .{.{.fnKey = res[0]}, res[1]}
				else |err| if (err == error.InsufficientLen) encounteredInsufficientLen = true;

				for (2..bytes.len) |i| {
					switch (bytes[i]) {
						NavKey.fnName[0] => return .{.{.navKey = try NavKey.parse(bytes[0..i+1])}, i+1},
						
						'@' => return .{.{.insertBlankChars = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						'L' => return .{.{.insertBlankLines = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},

						'A' => return .{.{.moveCursorUp    = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						'B' => return .{.{.moveCursorDown  = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						'C' => return .{.{.moveCursorRight = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						'D' => return .{.{.moveCursorLeft  = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},

						'E' => return .{.{.moveCursorToStartOfNextLine = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						'F' => return .{.{.moveCursorToStartOfPrevLine = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},

						'G' => return .{.{.moveCursorAbsCol = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						'd' => return .{.{.moveCursorAbsRow = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						
						'H', 'f' => {
							var it = VariadicArgs.init(bytes[2..i]);
							const row = it.nextBetter(u16) catch |err| switch (err) {
								VariadicArgs.PeekErr.Empty => 1,
								VariadicArgs.PeekErr.InvalidCharacter => return err,
								VariadicArgs.PeekErr.Overflow => 1,
							};
							const col = it.nextBetter(u16) catch |err| switch (err) {
								VariadicArgs.PeekErr.Empty => 1,
								VariadicArgs.PeekErr.InvalidCharacter => return err,
								VariadicArgs.PeekErr.Overflow => 1,
							};
							return .{.{.moveCursorAbs = .{.x = col orelse 1, .y = row orelse 1}}, i+1};
						},

						'I' => return .{.{.cursorForwardsTab =  parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						'Z' => return .{.{.cursorBackwardsTab = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},

						// TODO orelse 1
						'J' => return .{.{.eraseDisplay = try EraseDisplay.parse(bytes[0..i+1])}, i+1},
						// TODO orelse 1
						'K' => return .{.{.eraseLine    = try EraseLine.parse(bytes[0..i+1])}, i+1},
						'X' => return .{.{.eraseChars   = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},

						'M' => {
							// mouse
							if (bytes[2] == '<') return .{.{.mouse = try mouse.MouseEvent.parse(bytes[2..i+1])}, i+1};

							// deleteLines
							return .{.{.deleteLines = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1};
						},
						'P' => return .{.{.deleteChars = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						
						'S' => return .{.{.scrollUp   = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						'T' => return .{.{.scrollDown = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},

						'b' => return .{.{.repeatPreceedingChar = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},

						'h', 'l' => return switch (bytes[2]) {
							'='  => return error.unhandled,
							'?'  => .{.{.privateMode = try PrivateMode.parse(bytes[0..i+1])}, i+1},
							else => .{.{.setResetMode = try SetResetMode.parse(bytes[0..i+1])}, i+1},
						},

						'm' => {
							// mouse
							if (bytes[2] == '<') return .{.{.mouse = try mouse.MouseEvent.parse(bytes[2..i+1])}, i+1};

							// graphics
							return .{.{.graphics = try Graphics.parse(bytes[0..i+1])}, i+1};
						},

						'n' => return .{.{.deviceStatusReport = try DeviceStatusReport.parse(bytes[0..i+1])}, i+1},

						CursorStyle.fnName[0] => {
							if (CursorStyle.parse(bytes[0..i+1])) |val| return .{.{.setCursorStyle = val}, i+1}
							else |_| return .{.{.unknown = {}}, i+1};
						},

						's' => return .{.{.saveCursorPosition    = {}}, i+1},
						'u' => return .{.{.restoreCursorPosition = {}}, i+1},

						'y' => return .{.{.reqPrivateMode = try ReqPrivateMode.parse(bytes[2..i])}, i+1},

						else => {},
					}
				}

				if (encounteredInsufficientLen) return error.InsufficientLen;
				return error.NoMatch;
			},

			else => return error.NoMatch,
		}
	}
};

// TODO tests
//// TODO single int arg
////// no int passed in should return the default
////// the first int passed in should return that int
////// multiple ints passed in should return the first int
////// incorrect should return what?
//// TODO multiple int args
//// TODO no args
