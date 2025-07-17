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
	// \x1b4f or "ESCO" is called SS3
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
	// TODO move into '~' fn in EscSeq
	insert     = 0x1b5b327e,
	delete     = 0x1b5b337e,
	pageUp     = 0x1b5b357e,
	pageDown   = 0x1b5b367e,

	// These have "collisions" with mouseMoveX
	//arrowUp    = 0x1b5b41,
	//arrowDown  = 0x1b5b42,
	//arrowRight = 0x1b5b43,
	//arrowLeft  = 0x1b5b44,

	// These have "collisions" with moveCursorToStartOfPrevLine & moveCursorAbs
	//end        = 0x1b5b46,
	//home       = 0x1b5b48,

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

			//0x41 => return .{.arrowUp,    3},
			//0x42 => return .{.arrowDown,  3},
			//0x43 => return .{.arrowRight, 3},
			//0x44 => return .{.arrowLeft,  3},

			//0x46 => return .{.end,  3},
			//0x48 => return .{.home, 3},

			else => return ParseErr.NoMatch,
		}
	}
};

// TODO control keys?

// TODO would the default be that all are false (not including isHigh)?
const ResetMode = packed struct {
	isHigh:         bool,

	keyboardAction: bool = false, // 2
	replace:        bool = false, // 4
	sendReceive:    bool = false, // 12
	normalLinefeed: bool = false, // 20

	fn parse(bytes: []const u8) @This() {
		var out = @This(){.isHigh = bytes[bytes.len-1] == 'h'};

		// the h/l is ignored for proper parsing
		var it = IntParserIterator.init(bytes[0..bytes.len-1]);
		while (true) {
			const val = it.next(u11) catch |err| {
				switch (err) {
					error.NoRemaining => break,
					else => continue,
				}
			};

			switch (val) {
				2    => out.keyboardAction = true,
				4    => out.replace        = true,
				12   => out.sendReceive    = true,
				20   => out.normalLinefeed = true,
				else => {},
			}
		}

		return out;
	}
};

// TODO would the default be that all are false (not including isHigh)?
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
	backarrowSendsBackspace: bool = false, // 67
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

	fn parse(bytes: []const u8) @This() {
		assert(bytes[0] == '?');
		var out = @This(){.isHigh = bytes[bytes.len-1] == 'h'};

		// the ? and h/l are ignored for proper parsing
		var it = IntParserIterator.init(bytes[1..bytes.len-1]);
		while (true) {
			const val = it.next(u11) catch |err| {
				switch (err) {
					error.NoRemaining => break,
					else => continue,
				}
			};

			switch (val) {
				1    => out.applicationCursorKeys = true,
				2    => out.designateUSASCII = true,
				3    => out.columnMode132 = true,
				4    => out.smoothScroll = true,
				5    => out.reverseVideo = true,
				6    => out.origin = true,
				7    => out.autoWrap = true,
				8    => out.autoRepeat = true,
				9    => out.sendMouseXYOnBtnPress = true,
				10   => out.showToolbar = true,
				12   => out.startBlinkingCursorATT = true,
				13   => out.startBlinkingCursor = true,
				14   => out.enableXorBlinkingCursor = true,
				18   => out.printFormFeed = true,
				19   => out.setPrintExtentToFullScreen = true,
				25   => out.showCursor = true,
				30   => out.showScrollbar = true,
				35   => out.enableFontShiftingFns = true,
				38   => out.enterTektronix = true,
				40   => out.allow80To132 = true,
				41   => out.moreFix = true,
				42   => out.enableNationalReplacementCharSets = true,
				43   => out.enableGraphicExpandedPrint = true,
				44   => out.marginBellOrGraphicPrintColor = true, // TODO depends
				45   => out.reverseWraparoundOrGraphicPrintColor = true,
				46   => out.startLoggingOrGraphicPrint = true, // TODO depends
				47   => out.alternateScreenBufferOrGraphicRotatedPrint = true, // TODO depends
				66   => out.applicationKeypad = true,
				67   => out.backarrowSendsBackspace = true,
				69   => out.leftAndRightMargin = true,
				80   => out.sixelDisplay = true,
				95   => out.doNotClearScreenOnDECCOLM = true,
				1000 => out.sendMouseXYOnBtnPressAndRelease = true,
				1001 => out.hiliteMouseTracking = true,
				1002 => out.cellMotionMouseTracking = true,
				1003 => out.allMotionMouseTracking = true,
				1004 => out.sendFocusInFocusOut = true,
				1005 => out.utf8Mouse = true,
				1006 => out.sgrMouseMode = true,
				1007 => out.alternateScroll = true,
				1010 => out.scrollToBorromOnTTYOutput = true,
				1011 => out.scrollToBottomOnKeyPress = true,
				1014 => out.fastScroll = true,
				1015 => out.urxvtMouse = true,
				1016 => out.sgrMousePixel = true,
				1034 => out.interpretMetaKey = true,
				1035 => out.specialModifiersAltNumlock = true,
				1036 => out.sendEscOnMetaKeyModifier = true,
				1037 => out.sendDelFromEditKeypadDel = true,
				1039 => out.sendEscOnAltKeyModifier = true,
				1040 => out.keepSelectionIfNotHighlighted = true,
				1042 => out.urgencyWindowManagerHintOnCtrlG = true,
				1043 => out.raiseWindowOnCtrlG = true,
				1044 => out.reuseMostRecentDataFromClipboard = true,
				1045 => out.extendedReverseWraparound = true,
				1046 => out.switchingAlternateScreenBuffer = true,
				1047 => out.alternateScreenBuffer = true,
				1048 => out.saveCursor = true,
				1049 => out.saveCursorSwitchClearedAlternateScreenBuffer = true,
				1050 => out.terminfoTermcapFnKey = true,
				1051 => out.sunFnKey = true,
				1052 => out.hpFnKey = true,
				1053 => out.scoFnKey = true,
				1060 => out.legacyKeyboardEmulation = true,
				1061 => out.vt220KeyboardEmulation = true,
				2001 => out.readlineMouseBtn1 = true,
				2002 => out.readlineMouseBtn2 = true,
				2003 => out.readlineMouseBtn3 = true,
				2004 => out.bracketedPasteMode = true,
				2005 => out.readlineCharQuoting = true,
				2006 => out.readlineNewlinePasting = true,
				else => {},
			}
		}

		return out;
	}
};

const RGB = struct {u8, u8, u8};

const Color = union(enum) {
	pallet8:   u8,
	pallet256: u8,
	rgb:       RGB,
};

const GraphicResetOpt = enum(u1) {
	Unset,
	Set,
};

const GraphicOpt = enum(u2) {
	Unset,
	Set,
	Reset,
};

// m(...x) -> color / graphics, where x either sets or resets and there are x combos for 8 & 24 bit color
// TODO make packed
const Graphics = struct {
	reset: GraphicResetOpt = .Unset, // 0 (default)

	bold:            GraphicOpt = .Unset, // 1
	faint:           GraphicOpt = .Unset, // 2
	italic:          GraphicOpt = .Unset, // 3
	underline:       GraphicOpt = .Unset, // 4
	blinking:        GraphicOpt = .Unset, // 5
	inverse:         GraphicOpt = .Unset, // 7
	hidden:          GraphicOpt = .Unset, // 8
	strikethrough:   GraphicOpt = .Unset, // 9
	doubleUnderline: GraphicOpt = .Unset, // 21
	//noBoldOrFaint   // 22
	//noItalic        // 23
	//noUnderline     // 24
	//steady          // 25
	//positive        // 27
	//visible         // 28
	//noStrikethrough // 29

	// both can be applied to create faint bold
	//try stdout.print("\x1b[1;2mtesting\x1b[mtesting\n", .{});
	// bold
	//try stdout.print("\x1b[1mtesting\x1b[mtesting\n", .{});
	// faint
	//try stdout.print("\x1b[2mtesting\x1b[mtesting\n", .{});

	// 22 resets faint and bold
	//try stdout.print("\x1b[1;2;22mtesting\x1b[mtesting\n", .{});

	// foreground
	// 30 Black
	// 31 Red
	// 32 Green
	// 33 Yellow
	// 34 Blue
	// 35 Magenta
	// 36 Cyan
	// 37 White
	// 39 default, ECMA-48 3rd

	// background
	// 40 Black
	// 41 Red
	// 42 Green
	// 43 Yellow
	// 44 Blue
	// 45 Magenta
	// 46 Cyan
	// 47 White
	// 49 default, ECMA-48 3rd

	// aixterm bright/bold foreground
	// 90 Black
	// 91 Red
	// 92 Green
	// 93 Yellow
	// 94 Blue
	// 95 Magenta
	// 96 Cyan
	// 97 White

	// aixterm bright/bold background
	// 100 Black
	// 101 Red
	// 102 Green
	// 103 Yellow
	// 104 Blue
	// 105 Magenta
	// 106 Cyan
	// 107 White

	// TODO?
	// If xterm is compiled with the 16-color support disabled, it supports the following, from rxvt
	// 100 - Set foreground and background color to default

	// 256
	// 38;5;{ID}m - foreground
	// 48;5;{ID}m - background
				
	// RGB
	// 38;2;{r};{g};{b}m - foreground
	// 48;2;{r};{g};{b}m - background

	fg: ?Color = null,
	bg: ?Color = null,

	fn parse(bytes: []const u8) @This() {
		assert(bytes[bytes.len-1] == 'm');

		var out: @This() = .{};

		// the m is ignored for proper parsing
		var it = IntParserIterator.init(bytes[0..bytes.len-1]);
		// TODO will need state for multi int sequences
		// color can only be set once and will overwrite
		while (true) {
			const val = it.next(u8) catch |err| {
				switch (err) {
					error.NoRemaining => break,
					else => continue,
				}
			};

			switch (val) {
				// Full reset
				0  => out = .{.reset = .Set},

				// Set
				1  => out.bold            = .Set,
				2  => out.faint           = .Set,
				3  => out.italic          = .Set,
				4  => out.underline       = .Set,
				5  => out.blinking        = .Set,
				7  => out.inverse         = .Set,
				8  => out.hidden          = .Set,
				9  => out.strikethrough   = .Set,
				21 => out.doubleUnderline = .Set,
				
				// Reset
				22 => {
					out.bold = .Reset;
					out.faint = .Reset;
				},
				23 => out.italic          = .Reset,
				24 => out.underline       = .Reset,
				25 => out.blinking        = .Reset,
				27 => out.inverse         = .Reset,
				28 => out.hidden          = .Reset,
				29 => out.strikethrough   = .Reset,

				// pallet8
				30...37, 39 => out.fg = .{.pallet8 = val},
				40...47, 49 => out.bg = .{.pallet8 = val},

				// aixterm bright/bold pallet8
				90...97   => out.fg = .{.pallet8 = val},
				100...107 => out.bg = .{.pallet8 = val},

				// foreground/background pallet256/rgb
				// 38;5;{color}m     foreground pallet256
				// 38;2;{r};{g};{b}m foreground rgb
				// 48;5;{color}m     background pallet256
				// 48;2;{r};{g};{b}m background rgb
				38, 48 => {
					const format = it.next(u3) catch continue;
					var color: Color = undefined;

					if (format == 5) color = .{.pallet256 = it.next(u8) catch continue}
					else if (format == 2) {
						color = .{.rgb = .{
							it.next(u8) catch continue,
							it.next(u8) catch continue,
							it.next(u8) catch continue,
						}};
					}

					if (val == 38) out.fg = color
					else if (val == 48) out.bg = color
					else unreachable;
				},

				else => {},
			}

		}

		return out;
	}
};

const IntParserIterator = struct {
	it: std.mem.SplitIterator(u8, .sequence),

	fn next(self: *@This(), comptime T: type) !T {
		if (self.it.next()) |str| return std.fmt.parseInt(T, str, 10);
		return error.NoRemaining;
	}

	fn nextOrElse(self: *@This(), comptime T: type, default: T) T {
		if (self.it.next()) |str| {
			if (std.fmt.parseInt(T, str, 10)) |v| return v
			else |_| return default;
		}

		return default;
	}

	fn init(bytes: []const u8) @This() {
		return .{.it = std.mem.splitSequence(u8, bytes, ";")};
	}
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
	// TODO this and the 'end' key have a collision, but don't do the same thing
	// TODO im also seeing 'end' being SS3 instead of CSI, but isn't the case when testing
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

	// TODO
	mouse: Mouse,

	fn parseFirstInteger(comptime T: type, bytes: []const u8) ?T {
		var it = std.mem.splitSequence(u8, bytes, ";");
		const res = std.fmt.parseInt(T, it.first(), 10);
		if (res) |v| return v
		else |_| return null;
	}

	pub fn parse(bytes: []const u8) ParseErr!struct{@This(), usize} {
		if (bytes.len < 3) return ParseErr.InsufficientLen;
		if (bytes[0] != ESC) return ParseErr.NoMatch;

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

				for (2..bytes.len) |i| {
					switch (bytes[i]) {
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
							var it = IntParserIterator.init(bytes[2..i]);
							return .{.{.moveCursorAbs = .{it.nextOrElse(u16, 1), it.nextOrElse(u16, 1)}}, i+1};
						},

						'I' => return .{.{.cursorForwardTabulation =  parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						'Z' => return .{.{.cursorBackwardTabulation = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},

						'J' => return .{.{.eraseDisplay = parseFirstInteger(u2,  bytes[2..i]) orelse 1}, i+1},
						'K' => return .{.{.eraseLine    = parseFirstInteger(u2,  bytes[2..i]) orelse 1}, i+1},
						'X' => return .{.{.eraseChars   = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},

						'M' => return .{.{.deleteLines = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						'P' => return .{.{.deleteChars = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						
						'S' => return .{.{.scrollUp   = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},
						'T' => return .{.{.scrollDown = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},

						'b' => return .{.{.repeatPreceedingChar = parseFirstInteger(u16, bytes[2..i]) orelse 1}, i+1},

						'h', 'l' => return switch (bytes[2]) {
							// TODO not currently handling screenMode
							'='  => .{.{.unknown = {}}, i+1},
							'?'  => .{.{.privateMode = PrivateMode.parse(bytes[2..i+1])}, i+1},
							else => .{.{.resetMode = ResetMode.parse(bytes[2..i+1])}, i+1},
						},

						'm' => return .{.{.graphics = Graphics.parse(bytes[2..i+1])}, i+1},

						// TODO not sure theres a default
						'n' => return .{.{.deviceStatusReport = parseFirstInteger(u3, bytes[2..i]) orelse 5}, i+1},
						
						'q' => return .{.{.setCursorStyle = parseFirstInteger(u3, bytes[2..i]) orelse 1}, i+1},

						's' => return .{.{.saveCursorPosition    = {}}, i+1},
						'u' => return .{.{.restoreCursorPosition = {}}, i+1},

						// TODO mouse

						else => {},
					}
				}

				if (encounteredInsufficientLen) return ParseErr.InsufficientLen;
				return ParseErr.NoMatch;
			},

			else => return ParseErr.NoMatch,
		}
	}
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

const expect = std.testing.expect;

fn intToBytesBigEndian(comptime T: type, val: T) struct{[@sizeOf(@TypeOf(val))]u8, usize} {
	var out = std.mem.toBytes(std.mem.nativeToBig(T, @as(T, val)));
	var len: usize = @sizeOf(@TypeOf(val));
	for (0..out.len) |i| {
		if (out[0] != 0) break;
		for (0..out.len-1) |j| out[j] = out[j+1];
		out[out.len-1-i] = 0;
		len -= 1;
	}

	return .{out, len};
}

fn testEnumKeys(comptime Enum: type, comptime tag: std.meta.Tag(EscSeq)) !void {
	inline for (std.meta.fields(Enum)) |f| {
		const instance: Enum = @enumFromInt(f.value);
		const bytes, const enumKeyLen = intToBytesBigEndian(std.meta.Tag(Enum), f.value);
		
		const enumOut, const enumOutLen = try Enum.parse(&bytes);
		try expect(enumOut == instance);
		try expect(enumKeyLen == enumOutLen);
		for (1..enumKeyLen-1) |i| try expect(Enum.parse(bytes[0..i]) == ParseErr.InsufficientLen);

		const escOut, const escOutLen = try EscSeq.parse(&bytes);
		try expect(std.meta.activeTag(escOut) == tag);
		try expect(@field(escOut, @tagName(tag)) == instance);
		try expect(enumKeyLen == escOutLen);
		for (1..enumKeyLen-1) |i| try expect(EscSeq.parse(bytes[0..i]) == ParseErr.InsufficientLen);
	}
}


// none should return the default
fn testEmpty(comptime T: type, comptime tag: std.meta.Tag(EscSeq), comptime fnChar: u8, comptime default: T) !void {
	const in = std.fmt.comptimePrint("\x1b[{c}", .{fnChar});
	const out, const len = try EscSeq.parse(in);
	
	try expect(std.meta.activeTag(out) == tag);
	try expect(std.mem.eql(u8, &std.mem.toBytes(@field(out, @tagName(tag))), &std.mem.toBytes(default)));
	try expect(len == in.len);
}

fn tupleToAnsiEscParamsStr(comptime T: type, comptime tuple: T) [256]u8 {
	var buf: [256]u8 = undefined;
	var i: u8 = 1;
	inline for (tuple) |v| {
		const out = std.fmt.bufPrint(buf[i..], "{d}", .{v}) catch unreachable;
		i += @as(u8, @truncate(out.len)) + 1;
		buf[i-1] = ';';
	}

	buf[0] = i-1;

	return buf;
}

// correct should return what was passed in
fn testCorrect(comptime T: type, comptime tag: std.meta.Tag(EscSeq), comptime fnChar: u8, comptime value: T) !void {
	const in = std.fmt.comptimePrint("\x1b[{any}{c}", .{value, fnChar});
	const out, const len = try EscSeq.parse(in);
	try expect(std.meta.activeTag(out) == tag);
	try expect(@field(out, @tagName(tag)) == value);
	try expect(len == in.len);
}

// correct should return what was passed in
fn testCorrectTuple(comptime T: type, comptime tag: std.meta.Tag(EscSeq), comptime fnChar: u8, comptime value: T) !void {
	const tupleStr = tupleToAnsiEscParamsStr(T, value);
	var buf: [1024]u8 = undefined;
	const in = std.fmt.bufPrint(&buf, "\x1b[{s}{c}", .{tupleStr[1..tupleStr[0]], fnChar}) catch unreachable;
	const out, const len = try EscSeq.parse(in);
	try expect(std.meta.activeTag(out) == tag);
	try expect(std.mem.eql(u8, &std.mem.toBytes(@field(out, @tagName(tag))), &std.mem.toBytes(value)));
	try expect(len == in.len);
}

// incorrect should return the default
// underscore is not a fn char and is not numeric
fn testIncorrect(comptime T: type, comptime tag: std.meta.Tag(EscSeq), comptime fnChar: u8, comptime default: T) !void {
	const in = std.fmt.comptimePrint("\x1b[_{c}", .{fnChar});
	const out, const len = try EscSeq.parse(in);
	try expect(std.meta.activeTag(out) == tag);
	try expect(std.mem.eql(u8, &std.mem.toBytes(@field(out, @tagName(tag))), &std.mem.toBytes(default)));
	try expect(len == in.len);
}

// multiple should return the first, from my own testing
fn testTooMany(comptime T: type, comptime tag: std.meta.Tag(EscSeq), comptime fnChar: u8, comptime value: T) !void {
	const in = std.fmt.comptimePrint("\x1b[{d};{d};{d}{c}", .{value, value +% 1, value -% 1, fnChar});
	const out, const len = try EscSeq.parse(in);
	try expect(std.meta.activeTag(out) == tag);
	try expect(@field(out, @tagName(tag)) == value);
	try expect(len == in.len);	
}

// multiple should return the first, from my own testing
fn testTooManyTuple(comptime T: type, comptime tag: std.meta.Tag(EscSeq), comptime fnChar: u8, comptime value: T) !void {
	const tupleStr = tupleToAnsiEscParamsStr(T, value);
	var buf: [1024]u8 = undefined;
	const in = std.fmt.bufPrint(&buf, "\x1b[{s};{d};{d}{c}", .{tupleStr[1..tupleStr[0]], value[0] +% 1, value[0] -% 1, fnChar}) catch unreachable;
	const out, const len = try EscSeq.parse(in);
	try expect(std.meta.activeTag(out) == tag);
	try expect(std.mem.eql(u8, &std.mem.toBytes(@field(out, @tagName(tag))), &std.mem.toBytes(value)));
	try expect(len == in.len);	
}

fn testTooManyVoid(comptime tag: std.meta.Tag(EscSeq), comptime fnChar: u8) !void {
	const in = std.fmt.comptimePrint("\x1b[1;2;3{c}", .{fnChar});
	const out, const len = try EscSeq.parse(in);
	try expect(std.meta.activeTag(out) == tag);
	try expect(@field(out, @tagName(tag)) == {});
	try expect(len == in.len);	
}

fn testSingleIntEscSeq(comptime T: type, comptime tag: std.meta.Tag(EscSeq), comptime fnChar: u8, comptime default: T) !void {
	const nonDefault: T = 3;
	try expect(nonDefault != default);

	try testEmpty(T, tag, fnChar, default);
	try testCorrect(T, tag, fnChar, nonDefault);
	try testIncorrect(T, tag, fnChar, default);
	try testTooMany(T, tag, fnChar, nonDefault);
}

fn testVoidEscSeq(comptime tag: std.meta.Tag(EscSeq), comptime fnChar: u8) !void {
	try testEmpty(void, tag, fnChar, {});
	try testIncorrect(void, tag, fnChar, {});
	try testTooManyVoid(tag, fnChar);
}

test "EscSeq" {
	try testEnumKeys(FnKey, EscSeq.fnKey);
	try testEnumKeys(NavKey, EscSeq.navKey);

	try testSingleIntEscSeq(u16, EscSeq.insertBlankChars, '@', 1);
	try testSingleIntEscSeq(u16, EscSeq.insertBlankLines, 'L', 1);

	try testSingleIntEscSeq(u16, EscSeq.moveCursorUp,    'A', 1);
	try testSingleIntEscSeq(u16, EscSeq.moveCursorDown,  'B', 1);
	try testSingleIntEscSeq(u16, EscSeq.moveCursorRight, 'C', 1);
	try testSingleIntEscSeq(u16, EscSeq.moveCursorLeft,  'D', 1);

	try testSingleIntEscSeq(u16, EscSeq.moveCursorToStartOfNextLine, 'E', 1);
	try testSingleIntEscSeq(u16, EscSeq.moveCursorToStartOfPrevLine, 'F', 1);

	try testSingleIntEscSeq(u16, EscSeq.moveCursorAbsCol, 'G', 1);
	try testSingleIntEscSeq(u16, EscSeq.moveCursorAbsRow, 'd', 1);

	try testEmpty(struct{u16, u16},        EscSeq.moveCursorAbs, 'H', .{1,1});
	try testCorrectTuple(struct{u16, u16}, EscSeq.moveCursorAbs, 'H', .{24,94});
	try testIncorrect(struct{u16, u16},    EscSeq.moveCursorAbs, 'H', .{1,1});
	try testTooManyTuple(struct{u16, u16}, EscSeq.moveCursorAbs, 'H', .{24,94});
	try testEmpty(struct{u16, u16},        EscSeq.moveCursorAbs, 'f', .{1,1});
	try testCorrectTuple(struct{u16, u16}, EscSeq.moveCursorAbs, 'f', .{24,94});
	try testIncorrect(struct{u16, u16},    EscSeq.moveCursorAbs, 'f', .{1,1});
	try testTooManyTuple(struct{u16, u16}, EscSeq.moveCursorAbs, 'f', .{24,94});

	try testSingleIntEscSeq(u16, EscSeq.cursorForwardTabulation, 'I', 1);
	try testSingleIntEscSeq(u16, EscSeq.cursorBackwardTabulation, 'Z', 1);

	try testSingleIntEscSeq(u2,  EscSeq.eraseDisplay, 'J', 1);
	try testSingleIntEscSeq(u2,  EscSeq.eraseLine,    'K', 1);
	try testSingleIntEscSeq(u16, EscSeq.eraseChars,   'X', 1);

	try testSingleIntEscSeq(u16, EscSeq.deleteLines, 'M', 1);
	try testSingleIntEscSeq(u16, EscSeq.deleteChars, 'P', 1);

	try testSingleIntEscSeq(u16, EscSeq.scrollUp,   'S', 1);
	try testSingleIntEscSeq(u16, EscSeq.scrollDown, 'T', 1);

	try testSingleIntEscSeq(u16, EscSeq.repeatPreceedingChar, 'b', 1);

	// TODO high & low testing table driven for testing every option, mixed inputs, invalid inputs
	try testEmpty(ResetMode, EscSeq.resetMode, 'h', .{.isHigh = true});
	//try testCorrect(ResetMode, EscSeq.resetMode, 'h', .{.isHigh = true});
	try testIncorrect(ResetMode, EscSeq.resetMode, 'h', .{.isHigh = true});
	try testEmpty(ResetMode, EscSeq.resetMode, 'l', .{.isHigh = false});
	//try testCorrect(ResetMode, EscSeq.resetMode, 'l', .{.isHigh = false});
	try testIncorrect(ResetMode, EscSeq.resetMode, 'l', .{.isHigh = false});
	
	// TODO high & low testing table driven for testing every option, mixed inputs, invalid inputs
	//try testEmpty(PrivateMode, EscSeq.privateMode, 'h', .{.isHigh = true});
	//try testCorrect(PrivateMode, EscSeq.privateMode, 'h', .{.isHigh = true});
	//try testIncorrect(PrivateMode, EscSeq.privateMode, 'h', .{.isHigh = true});
	//try testEmpty(PrivateMode, EscSeq.privateMode, 'l', .{.isHigh = false});
	//try testCorrect(PrivateMode, EscSeq.privateMode, 'l', .{.isHigh = false});
	//try testIncorrect(PrivateMode, EscSeq.privateMode, 'l', .{.isHigh = false});

	// TODO test graphics
	// TODO test Mouse

	try testSingleIntEscSeq(u3, EscSeq.deviceStatusReport, 'n', 5);

	try testSingleIntEscSeq(u3, EscSeq.setCursorStyle, 'q', 1);


	try testVoidEscSeq(EscSeq.saveCursorPosition, 's');
	try testVoidEscSeq(EscSeq.restoreCursorPosition, 'u');
}
