const std = @import("std");
const stdout = std.io.getStdOut().writer();
const assert = std.debug.assert;

const EraseDisplay = @import("singularArg.zig").EraseDisplay;
const EraseLine = @import("singularArg.zig").EraseLine;
const CursorStyle = @import("singularArg.zig").CursorStyle;
const DeviceStatusReport = @import("singularArg.zig").DeviceStatusReport;
const SetResetMode = @import("_genIncantations.zig").SetResetMode;
const PrivateMode = @import("_genIncantations.zig").PrivateMode;

// all unsigned ints have a default value of 1
pub const EscSeq = union(enum) {
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
	moveCursorAbs: struct{u16, u16},


	// I(?x) - Cursor Forward Tabulation x (default 1) tab stops
	cursorForwardTabulation: u16,
	// Z(?x) - cursor backward tabulation x (default 1) tab stops
	cursorBackwardTabulation: u16,


	// TODO vt220 "ESC[?xJ" variant?
	// J(?x)
	eraseDisplay: EraseDisplay,
	// TODO vt220 "ESC[?xK" variant?
	// K(?x)
	eraseLine: EraseLine,


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


	// "{h/l}(...x)"
	setResetMode: SetResetMode,
	// "{h/l}(?, ...x)"
	privateMode: PrivateMode,
	// TODO i dont see any results from this and there were no changes when trying reported x values
	//// "\x1b[={x}{h/l}" -> (un)set screen mode
	//screenMode: ScreenMode,


	// m(...x) -> sets graphics dependant upon x (default 0)
	//graphics: Graphics,


	// n(x)
	deviceStatusReport: DeviceStatusReport,


	// " q"(?x)
	setCursorStyle: CursorStyle,


	// s() -> save cursor position
	saveCursorPosition: void,
	// u() -> restores the cursor to the last saved position
	restoreCursorPosition: void,
};
