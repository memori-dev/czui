const std = @import("std");
const stdout = std.io.getStdOut().writer();
const assert = std.debug.assert;

const ESC: u8 = 27;

// Quick intro
//// https://notes.burke.libbey.me/ansi-escape-codes/
// References
//// https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Functions-using-CSI-_-ordered-by-the-final-character_s_
//// https://man7.org/linux/man-pages/man4/console_codes.4.html
// Combo examples
//// https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
//// https://gitlab.com/greggink/youtube_episode_terminal_control_2/-/blob/main/tc.h

const altScreenEnter: []const u8 = "\x1b[?1049h";
const altScreenExit:  []const u8 = "\x1b[?1049l";

const cursorInvisible: []const u8 = "\x1b[?25l";
const cursorVisible:   []const u8 = "\x1b[?25h";
const cursorToOrigin:  []const u8 = "\x1b[H";
const cursorMoveFmt:   []const u8 = "\x1b[{d};{d}H";

const eraseScreen:                []const u8 = "\x1b[2J";
const eraseScrollback:            []const u8 = "\x1b[3J";
const eraseFromCursorToEndOfLine: []const u8 = "\x1b[0K";

const modeReset:         []const u8 = "\x1b[0m";
const modeBold:          []const u8 = "\x1b[1m";
const modeFaint:         []const u8 = "\x1b[2m";
const modeItalic:        []const u8 = "\x1b[3m";
const modeUnderline:     []const u8 = "\x1b[4m";
const modeBlinking:      []const u8 = "\x1b[5m";
const modeInverse:       []const u8 = "\x1b[7m";
const modeHidden:        []const u8 = "\x1b[8m";
const modeStrikethrough: []const u8 = "\x1b[9m";

//pub const mouseDetection: []const u8 = "\x1b[?1000;1006;1015h";
pub const mouseDetection: []const u8 = "\x1b[?1003;1006;1015h";

pub const fullWipe = eraseScreen ++ eraseScrollback ++ cursorToOrigin;

// cursor starts at {1,1}
// when y exceeds the winsize.row it will just set the cursor to winsize.row (causing unexpected overwrites)
pub fn moveCursor(x: u16, y: u16) !void {
	return stdout.print(cursorMoveFmt, .{y, x});
}

pub const ParseErr = error{
	NoMatch,
	InsufficientLen,
};

pub const FnKey = enum(u64) {
	F1    = 0x1b4f50,
	F2    = 0x1b4f51,
	F3    = 0x1b4f52,
	F4    = 0x1b4f53,
	F5    = 0x1b5b31357e,
	F6    = 0x1b5b31377e,
	F7    = 0x1b5b31387e,
	F8    = 0x1b5b31397e,
	F9    = 0x1b5b32307e,
	F10   = 0x1b5b32317e,
	F11   = 0x1b5b32337e,
	F12   = 0x1b5b32347e,
	F1TTY = 0x1b5b5b41,
	F2TTY = 0x1b5b5b42,
	F3TTY = 0x1b5b5b43,
	F4TTY = 0x1b5b5b44,
	F5TTY = 0x1b5b5b45,

	pub fn parse(bytes: []const u8) ParseErr!struct{@This(), usize} {
		if (bytes.len < 3) return ParseErr.InsufficientLen;
		if (bytes[0] != ESC) return ParseErr.NoMatch;

		switch (bytes[1]) {
			0x4f => return switch (bytes[2]) {
				0x50 => .{.F1, 3},
				0x51 => .{.F2, 3},
				0x52 => .{.F3, 3},
				0x53 => .{.F4, 3},
				else => ParseErr.NoMatch,
			},

			0x5b => switch (bytes[2]) {
				0x31 => {
					if (bytes.len < 5) return ParseErr.InsufficientLen;
					if (bytes[4] != 0x7e) return ParseErr.NoMatch;

					return switch (bytes[3]) {
						0x35 => .{.F5, 5},
						0x37 => .{.F6, 5},
						0x38 => .{.F7, 5},
						0x39 => .{.F8, 5},
						else => ParseErr.NoMatch,
					};
				},

				0x32 => {
					if (bytes.len < 5) return ParseErr.InsufficientLen;
					if (bytes[4] != 0x7e) return ParseErr.NoMatch;

					return switch (bytes[3]) {
						0x30 => .{.F9,  5},
						0x31 => .{.F10, 5},
						0x33 => .{.F11, 5},
						0x34 => .{.F12, 5},
						else => ParseErr.NoMatch,
					};
				},
				
				0x5b => {
					if (bytes.len < 4) return ParseErr.InsufficientLen;

					return switch (bytes[3]) {
						0x41 => .{.F1TTY, 4},
						0x42 => .{.F2TTY, 4},
						0x43 => .{.F3TTY, 4},
						0x44 => .{.F4TTY, 4},
						0x45 => .{.F5TTY, 4},
						else => ParseErr.NoMatch,
					};
				},
				
				else => return ParseErr.NoMatch,
			},

			else => return ParseErr.NoMatch,
		}
	}
};

pub const NavKey = enum(u32) {
	insert     = 0x1b5b327e,
	delete     = 0x1b5b337e,
	pageUp     = 0x1b5b357e,
	pageDown   = 0x1b5b367e,

	arrowUp    = 0x1b5b41,
	arrowDown  = 0x1b5b42,
	arrowRight = 0x1b5b43,
	arrowLeft  = 0x1b5b44,

	end        = 0x1b5b46,
	home       = 0x1b5b48,

	fn parse(bytes: []const u8) ParseErr!struct{@This(), usize} {
		if (bytes.len < 3) return ParseErr.InsufficientLen;
		if (bytes[0] != ESC or bytes[1] != 0x5b) return ParseErr.NoMatch;

		switch (bytes[2]) {
			0x32, 0x33, 0x35, 0x36 => {
				if (bytes.len < 4) return ParseErr.InsufficientLen;
				if (bytes[3] != 0x7e) return ParseErr.NoMatch;

				return switch (bytes[2]) {
					0x32 => .{.insert,   4},
					0x33 => .{.delete,   4},
					0x35 => .{.pageUp,   4},
					0x36 => .{.pageDown, 4},
					else => unreachable,
				};
			},

			0x41 => return .{.arrowUp,    3},
			0x42 => return .{.arrowDown,  3},
			0x43 => return .{.arrowRight, 3},
			0x44 => return .{.arrowLeft,  3},

			0x46 => return .{.end,  3},
			0x48 => return .{.home, 3},

			else => return ParseErr.NoMatch,
		}
	}
};

// TODO control keys?

const ResetMode = packed struct {
	keyboardAction: bool = false, // 2
	replace:        bool = false, // 4
	sendReceive:    bool = false, // 12
	normalLinefeed: bool = false, // 20
};

const PrivateMode = packed struct {
	isHigh: bool,

	applicationCursorKeys: bool = false, // 1
	designateUSASCII: bool = false, // 2
	columnMode132: bool = false, // 3
	smoothScroll: bool = false, // 4
	reverseVideo: bool = false, // 5
	origin: bool = false, // 6
	autoWrap: bool = false, // 7
	autoRepeat: bool = false, // 8
	sendMouseXYOnBtnPress: bool = false, // 9
	showToolbar: bool = false, // 10
	startBlinkingCursorATT: bool = false, // 12
	startBlinkingCursor: bool = false, // 13
	enableXorBlinkingCursor: bool = false, // 14
	printFormFeed: bool = false, // 18
	setPrintExtentToFullScreen: bool = false, // 19
	showCursor: bool = false, // 25
	showScrollbar: bool = false, // 30
	enableFontShiftingFns: bool = false, // 35
	enterTektronix: bool = false, // 38
	allow80To132: bool = false, // 40
	moreFix: bool = false, // 41
	enableNationalReplacementCharSets: bool = false, // 42
	enableGraphicExpandedPrint: bool = false, // 43
	marginBellOrGraphicPrintColor: bool = false, // 44 TODO depends
	reverseWraparoundOrGraphicPrintColor: bool = false, // 45
	startLoggingOrGraphicPrint: bool = false, // 46 TODO depends
	alternateScreenBufferOrGraphicRotatedPrint: bool = false, // 47 TODO depends
	applicationKeypad: bool = false, // 66
	BackarrowSendsBackspace: bool = false, // 67
	leftAndRightMargin: bool = false, // 69
	sixelDisplay: bool = false, // 80
	doNotClearScreenOnDECCOLM: bool = false, // 95
	sendMouseXYOnBtnPressAndRelease: bool = false, // 1000
	hiliteMouseTracking: bool = false, // 1001
	cellMotionMouseTracking: bool = false, // 1002
	allMotionMouseTracking: bool = false, // 1003
	sendFocusInFocusOut: bool = false, // 1004
	utf8Mouse: bool = false, // 1005
	sgrMouseMode: bool = false, // 1006
	alternateScroll: bool = false, // 1007
	scrollToBorromOnTTYOutput: bool = false, // 1010
	scrollToBottomOnKeyPress: bool = false, // 1011
	fastScroll: bool = false, // 1014
	urxvtMouse: bool = false, // 1015
	sgrMousePixel: bool = false, // 1016
	interpretMetaKey: bool = false, // 1034
	specialModifiersAltNumlock: bool = false, // 1035
	sendEscOnMetaKeyModifier: bool = false, // 1036
	sendDelFromEditKeypadDel: bool = false, // 1037
	sendEscOnAltKeyModifier: bool = false, // 1039
	keepSelectionIfNotHighlighted: bool = false, // 1040
	urgencyWindowManagerHintOnCtrlG: bool = false, // 1042
	raiseWindowOnCtrlG: bool = false, // 1043
	reuseMostRecentDataFromClipboard: bool = false, // 1044
	extendedReverseWraparound: bool = false, // 1045
	switchingAlternateScreenBuffer: bool = false, // 1046
	alternateScreenBuffer: bool = false, // 1047
	saveCursor: bool = false, // 1048
	saveCursorSwitchClearedAlternateScreenBuffer: bool = false, // 1049
	terminfoTermcapFnKey: bool = false, // 1050
	sunFnKey: bool = false, // 1051
	hpFnKey: bool = false, // 1052
	scoFnKey: bool = false, // 1053
	legacyKeyboardEmulation: bool = false, // 1060
	vt220KeyboardEmulation: bool = false, // 1061
	readlineMouseBtn1: bool = false, // 2001
	readlineMouseBtn2: bool = false, // 2002
	readlineMouseBtn3: bool = false, // 2003
	bracketedPasteMode: bool = false, // 2004
	readlineCharQuoting: bool = false, // 2005
	readlineNewlinePasting: bool = false, // 2006
};

const RGB = struct {u8, u8, u8};

const Color = union(enum) {
	// TODO pallet8 constants fg (30...39) & bg (40...49)
	pallet8:   u8,
	// TODO pallet16 constants fg (90...97) & bg (100...107)
	pallet16:  u8,
	pallet256: u8,
	rbg:       RGB,
};

// m(...x) -> color / graphics, where x either sets or resets and there are x combos for 8 & 24 bit color
// When parsing a 0 should full reset to defaults with reset set to true
// color can only be set once and will overwrite
// TODO make packed
const Graphics = struct {
	reset: bool = false, // 0

	bold:          bool = false, // 1
	faint:         bool = false, // 2
	italic:        bool = false, // 3
	underline:     bool = false, // 4
	blinking:      bool = false, // 5
	inverse:       bool = false, // 7
	hidden:        bool = false, // 8
	strikethrough: bool = false, // 9

	doubleUnderline: bool = false, // 21
	normal:          bool = false, // 22
	noItalics:       bool = false, // 23
	noUnderline:     bool = false, // 24
	steady:          bool = false, // 25
	positive:        bool = false, // 27
	visible:         bool = false, // 28
	noStrikethrough: bool = false, // 29

	fg: ?Color = null,
	bg: ?Color = null,
};

// So far from testing, if additional args are provided they are dropped
pub const EscSeq = union(enum) {
	fnKey: FnKey,
	navKey: NavKey,

	// @(?x) -> insert x (default 1) blank chars
	insertBlankChars: u16,
	// L(?x) -> insert x (default 1) blank lines above
	insertBlankLines: u16,
	

	// A(?x) -> move cursor up x (default 1) rows
	moveCursorUp: u16,
	// TODO: CSI Ps e, is apparently the same fn but didnt work
	// B(?x) -> move cursor down x (default 1) rows
	moveCursorDown: u16,
	// C(?x) -> move cursor right x (default 1) cols
	moveCursorRight: u16,
	// D(?x) -> move cursor left x (default 1) cols
	moveCursorLeft: u16,


	// E(?x) -> move cursor to start of next line, x (default 1) lines down
	moveCursorToStartOfNextLine: u16,
	// F(?x) -> moves cursor to start of prev line, x (default 1) lines up
	moveCursorToStartOfPrevLine: u16,


	// G(?x) -> moves cursor to column x (default 1)
	moveCursorAbsCol: u16,
	// d(?x) -> moves cursor to row x (default 1)
	moveCursorAbsRow: u16,
	// H(?y, ?x) -> move cursor to y (default 1), x (default 1)
	// f(?y, ?x) -> move cursor to y (default 1), x (default 1)
	moveCursorAbs: struct{u16, u16},


	// I(?x) -> Cursor Forward Tabulation x (default 1) tab stops
	cursorForwardTabulation: u16,
	// Z(?x) -> cursor backward tabulation x (default 1) tab stops
	cursorBackwardTabulation: u16,


	// TODO vt220 "ESC[?xJ" variant?
	// J(?x) -> erase based upon x (default 0)
	//// 0 - erase from cursor until end of screen
	//// 1 - erase from cursor to beginning of screen
	//// 2 - erase all
	//// 3 - erase saved lines (scrollback)
	eraseDisplay: u2,
	// TODO vt220 "ESC[?xK" variant?
	// K(?x) -> erase based upon x (default 0)
	//// 0 - erase from cursor to end of line
	//// 1 - erase start of line to the cursor
	//// 2 - erase the entire line
	//// 3 - erase the entire saved line (scrollback)
	eraseLine: u2,
	// X(?x) -> erase x (default 1) chars on current line
	eraseChars: u16,


	// M(?x) -> delete x (default 1) lines
	deleteLines: u16,
	// P(?x) -> delete x (default 1) chars on current line
	deleteChars: u16,


	// S(?x) -> scroll up x (default 1) lines
	scrollUp: u16,
	// T(?x) -> scroll down x (default 1) lines
	scrollDown: u16,


	// b(?x) -> repeat preceeding char x (default 1) times
	repeatPreceedingChar: u16,


	// h(x) -> high (set)
	// l(x) -> low  (unset)
	//// "\x1b[{x}{h/l}" -> (re)set mode
	resetMode: ResetMode,
	// TODO i dont see any results from this and there were no changes when trying reported x values
	//// "\x1b[={x}{h/l}" -> (un)set screen mode
	//screenMode: ScreenMode,
	//// "\x1b[?{x}{h/l}" -> (un)set private modes
	privateMode: PrivateMode,


	// m(...x) -> sets graphics dependant upon x (default 0)
	graphics: Graphics,


	// n(x) -> device status report
	//// 5 - status report
	//// 6 - request cursor position (reports as \x1b[#;#R)
	deviceStatusReport: u3,


	// q (x) -> set cursor style (default 1)
	//// 1 - blinking block
	//// 2 - steady block
	//// 3 - blinking underline
	//// 4 - steady underline
	//// 5 - blinking bar
	//// 6 - steady bar
	setCursorStyle: u3,


	// s() -> save cursor position
	saveCursorPosition: void,
	// u() -> restores the cursor to the last saved position
	restoreCursorPosition: void,


	unknown: void,

	mouse: Mouse,
};

// TODO are any optional?
// TODO is col row the correct order?
// M(moveType, col, row)
// ex. mouse scroll up "ESC[96;34;28M"
//// moveType
////// 67 move?
////// 96 -> scroll up
////// 97 -> scroll down
const Mouse = struct {
	moveType: u8,
	col: u8,
	row: u8,
};

// TODO could I make the parsers generative

fn isKnownAnsiEscapeFnChar(byte: u8) bool {
	return switch (byte) {
		'A'...'M', 'P'...'T', 'W'...'Z', 'a'...'i', 'l'...'n', 'p'...'z', '@', '^', '`', '{', '}', '|', '~' => true,
		else => false,
	};
}

pub fn parse(bytes: []const u8) ParseErr!struct{EscSeq, usize} {
	assert(bytes.len >= 3 and bytes[0] == ESC);

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
			else |err| if (err == ParseErr.InsufficientLen) encounteredInsufficientLen = true;

			if (NavKey.parse(bytes)) |res| return .{.{.navKey = res[0]}, res[1]}
			else |err| if (err == ParseErr.InsufficientLen) encounteredInsufficientLen = true;


			var i: usize = 2;
			var found = false;
			while (i < bytes.len) {
				if (isKnownAnsiEscapeFnChar(bytes[i])) {
					found = true;
					break;
				}

				i += 1;
			}

			if (!found) return ParseErr.InsufficientLen;

			stdout.print("'\\0x1b{s}'\n", .{bytes[1..i]}) catch unreachable;

			// TODO parse sequence
			return ParseErr.InsufficientLen;
		},

		else => return ParseErr.NoMatch,
	}
}
