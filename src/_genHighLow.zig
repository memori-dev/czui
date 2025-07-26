const std = @import("std");
const consts = @import("consts.zig");
const VariadicArgs = @import("variadicArgs.zig");

pub const SetResetMode = packed struct {
	const Self = @This();

	pub const postCSIChar: ?u8    = null;
	pub const minLen: usize = 3;
	
	isHigh: bool,
	keyboardAction: bool = false, // 2
	replace: bool = false, // 4
	sendReceive: bool = false, // 12
	normalLinefeed: bool = false, // 20
	
	pub fn parse(bytes: []const u8) !Self {
		if (bytes.len < Self.minLen) return error.InsufficientLen;
		if (!std.mem.eql(u8, &consts.CSI, bytes[0..2])) return error.IncorrectFormat;
		if (bytes[bytes.len-1] != 'h' and bytes[bytes.len-1] != 'l') return error.IncorrectFormat;
		
		var out = Self{.isHigh=bytes[bytes.len-1] == 'h'};
		const unmodified = out;
		var it = VariadicArgs.init(bytes[2..bytes.len-1]);
		while (try it.next(u5)) |val| {
			switch (val) {
				2 => out.keyboardAction = true,
				4 => out.replace = true,
				12 => out.sendReceive = true,
				20 => out.normalLinefeed = true,
				// unknown ints are ignored
				else => {},
			}
		}
		// every field cannot be false, meaning unset
		if (out == unmodified) return error.NoValidArguments;
		return out;
	}
	
	pub fn print(self: Self) struct{[12]u8, usize} {
		var out: [12]u8 = undefined;
		std.mem.copyForwards(u8, &out, &consts.CSI);
		var index: usize = 2;
		if (self.keyboardAction) {
			std.mem.copyForwards(u8, out[index..], "2;");
			index += 2;
		}
		if (self.replace) {
			std.mem.copyForwards(u8, out[index..], "4;");
			index += 2;
		}
		if (self.sendReceive) {
			std.mem.copyForwards(u8, out[index..], "12;");
			index += 3;
		}
		if (self.normalLinefeed) {
			std.mem.copyForwards(u8, out[index..], "20;");
			index += 3;
		}
		const endIndex = if (out[index-1] == ';') index else index + 1;
		out[endIndex-1] = if (self.isHigh) 'h' else 'l';
		return .{out, endIndex};
	}
};

pub const PrivateMode = packed struct {
	const Self = @This();

	pub const postCSIChar: ?u8    = '?';
	pub const minLen: usize = 4;
	
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
	marginBellOrGraphicPrintColor: bool = false, // 44
	reverseWraparoundOrGraphicPrintColor: bool = false, // 45
	startLoggingOrGraphicPrint: bool = false, // 46
	alternateScreenBufferOrGraphicRotatedPrint: bool = false, // 47
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
	
	pub fn parse(bytes: []const u8) !Self {
		if (bytes.len < Self.minLen) return error.InsufficientLen;
		if (!std.mem.eql(u8, &consts.CSI, bytes[0..2])) return error.IncorrectFormat;
		if (bytes[2] != '?') return error.IncorrectFormat;
		if (bytes[bytes.len-1] != 'h' and bytes[bytes.len-1] != 'l') return error.IncorrectFormat;
		
		var out = Self{.isHigh=bytes[bytes.len-1] == 'h'};
		const unmodified = out;
		var it = VariadicArgs.init(bytes[3..bytes.len-1]);
		while (try it.next(u11)) |val| {
			switch (val) {
				1 => out.applicationCursorKeys = true,
				2 => out.designateUSASCII = true,
				3 => out.columnMode132 = true,
				4 => out.smoothScroll = true,
				5 => out.reverseVideo = true,
				6 => out.origin = true,
				7 => out.autoWrap = true,
				8 => out.autoRepeat = true,
				9 => out.sendMouseXYOnBtnPress = true,
				10 => out.showToolbar = true,
				12 => out.startBlinkingCursorATT = true,
				13 => out.startBlinkingCursor = true,
				14 => out.enableXorBlinkingCursor = true,
				18 => out.printFormFeed = true,
				19 => out.setPrintExtentToFullScreen = true,
				25 => out.showCursor = true,
				30 => out.showScrollbar = true,
				35 => out.enableFontShiftingFns = true,
				38 => out.enterTektronix = true,
				40 => out.allow80To132 = true,
				41 => out.moreFix = true,
				42 => out.enableNationalReplacementCharSets = true,
				43 => out.enableGraphicExpandedPrint = true,
				44 => out.marginBellOrGraphicPrintColor = true,
				45 => out.reverseWraparoundOrGraphicPrintColor = true,
				46 => out.startLoggingOrGraphicPrint = true,
				47 => out.alternateScreenBufferOrGraphicRotatedPrint = true,
				66 => out.applicationKeypad = true,
				67 => out.backarrowSendsBackspace = true,
				69 => out.leftAndRightMargin = true,
				80 => out.sixelDisplay = true,
				95 => out.doNotClearScreenOnDECCOLM = true,
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
				// unknown ints are ignored
				else => {},
			}
		}
		// every field cannot be false, meaning unset
		if (out == unmodified) return error.NoValidArguments;
		return out;
	}
	
	pub fn print(self: Self) struct{[285]u8, usize} {
		var out: [285]u8 = undefined;
		std.mem.copyForwards(u8, &out, &consts.CSI);
		out[2] = '?';
		var index: usize = 3;
		if (self.applicationCursorKeys) {
			std.mem.copyForwards(u8, out[index..], "1;");
			index += 2;
		}
		if (self.designateUSASCII) {
			std.mem.copyForwards(u8, out[index..], "2;");
			index += 2;
		}
		if (self.columnMode132) {
			std.mem.copyForwards(u8, out[index..], "3;");
			index += 2;
		}
		if (self.smoothScroll) {
			std.mem.copyForwards(u8, out[index..], "4;");
			index += 2;
		}
		if (self.reverseVideo) {
			std.mem.copyForwards(u8, out[index..], "5;");
			index += 2;
		}
		if (self.origin) {
			std.mem.copyForwards(u8, out[index..], "6;");
			index += 2;
		}
		if (self.autoWrap) {
			std.mem.copyForwards(u8, out[index..], "7;");
			index += 2;
		}
		if (self.autoRepeat) {
			std.mem.copyForwards(u8, out[index..], "8;");
			index += 2;
		}
		if (self.sendMouseXYOnBtnPress) {
			std.mem.copyForwards(u8, out[index..], "9;");
			index += 2;
		}
		if (self.showToolbar) {
			std.mem.copyForwards(u8, out[index..], "10;");
			index += 3;
		}
		if (self.startBlinkingCursorATT) {
			std.mem.copyForwards(u8, out[index..], "12;");
			index += 3;
		}
		if (self.startBlinkingCursor) {
			std.mem.copyForwards(u8, out[index..], "13;");
			index += 3;
		}
		if (self.enableXorBlinkingCursor) {
			std.mem.copyForwards(u8, out[index..], "14;");
			index += 3;
		}
		if (self.printFormFeed) {
			std.mem.copyForwards(u8, out[index..], "18;");
			index += 3;
		}
		if (self.setPrintExtentToFullScreen) {
			std.mem.copyForwards(u8, out[index..], "19;");
			index += 3;
		}
		if (self.showCursor) {
			std.mem.copyForwards(u8, out[index..], "25;");
			index += 3;
		}
		if (self.showScrollbar) {
			std.mem.copyForwards(u8, out[index..], "30;");
			index += 3;
		}
		if (self.enableFontShiftingFns) {
			std.mem.copyForwards(u8, out[index..], "35;");
			index += 3;
		}
		if (self.enterTektronix) {
			std.mem.copyForwards(u8, out[index..], "38;");
			index += 3;
		}
		if (self.allow80To132) {
			std.mem.copyForwards(u8, out[index..], "40;");
			index += 3;
		}
		if (self.moreFix) {
			std.mem.copyForwards(u8, out[index..], "41;");
			index += 3;
		}
		if (self.enableNationalReplacementCharSets) {
			std.mem.copyForwards(u8, out[index..], "42;");
			index += 3;
		}
		if (self.enableGraphicExpandedPrint) {
			std.mem.copyForwards(u8, out[index..], "43;");
			index += 3;
		}
		if (self.marginBellOrGraphicPrintColor) {
			std.mem.copyForwards(u8, out[index..], "44;");
			index += 3;
		}
		if (self.reverseWraparoundOrGraphicPrintColor) {
			std.mem.copyForwards(u8, out[index..], "45;");
			index += 3;
		}
		if (self.startLoggingOrGraphicPrint) {
			std.mem.copyForwards(u8, out[index..], "46;");
			index += 3;
		}
		if (self.alternateScreenBufferOrGraphicRotatedPrint) {
			std.mem.copyForwards(u8, out[index..], "47;");
			index += 3;
		}
		if (self.applicationKeypad) {
			std.mem.copyForwards(u8, out[index..], "66;");
			index += 3;
		}
		if (self.backarrowSendsBackspace) {
			std.mem.copyForwards(u8, out[index..], "67;");
			index += 3;
		}
		if (self.leftAndRightMargin) {
			std.mem.copyForwards(u8, out[index..], "69;");
			index += 3;
		}
		if (self.sixelDisplay) {
			std.mem.copyForwards(u8, out[index..], "80;");
			index += 3;
		}
		if (self.doNotClearScreenOnDECCOLM) {
			std.mem.copyForwards(u8, out[index..], "95;");
			index += 3;
		}
		if (self.sendMouseXYOnBtnPressAndRelease) {
			std.mem.copyForwards(u8, out[index..], "1000;");
			index += 5;
		}
		if (self.hiliteMouseTracking) {
			std.mem.copyForwards(u8, out[index..], "1001;");
			index += 5;
		}
		if (self.cellMotionMouseTracking) {
			std.mem.copyForwards(u8, out[index..], "1002;");
			index += 5;
		}
		if (self.allMotionMouseTracking) {
			std.mem.copyForwards(u8, out[index..], "1003;");
			index += 5;
		}
		if (self.sendFocusInFocusOut) {
			std.mem.copyForwards(u8, out[index..], "1004;");
			index += 5;
		}
		if (self.utf8Mouse) {
			std.mem.copyForwards(u8, out[index..], "1005;");
			index += 5;
		}
		if (self.sgrMouseMode) {
			std.mem.copyForwards(u8, out[index..], "1006;");
			index += 5;
		}
		if (self.alternateScroll) {
			std.mem.copyForwards(u8, out[index..], "1007;");
			index += 5;
		}
		if (self.scrollToBorromOnTTYOutput) {
			std.mem.copyForwards(u8, out[index..], "1010;");
			index += 5;
		}
		if (self.scrollToBottomOnKeyPress) {
			std.mem.copyForwards(u8, out[index..], "1011;");
			index += 5;
		}
		if (self.fastScroll) {
			std.mem.copyForwards(u8, out[index..], "1014;");
			index += 5;
		}
		if (self.urxvtMouse) {
			std.mem.copyForwards(u8, out[index..], "1015;");
			index += 5;
		}
		if (self.sgrMousePixel) {
			std.mem.copyForwards(u8, out[index..], "1016;");
			index += 5;
		}
		if (self.interpretMetaKey) {
			std.mem.copyForwards(u8, out[index..], "1034;");
			index += 5;
		}
		if (self.specialModifiersAltNumlock) {
			std.mem.copyForwards(u8, out[index..], "1035;");
			index += 5;
		}
		if (self.sendEscOnMetaKeyModifier) {
			std.mem.copyForwards(u8, out[index..], "1036;");
			index += 5;
		}
		if (self.sendDelFromEditKeypadDel) {
			std.mem.copyForwards(u8, out[index..], "1037;");
			index += 5;
		}
		if (self.sendEscOnAltKeyModifier) {
			std.mem.copyForwards(u8, out[index..], "1039;");
			index += 5;
		}
		if (self.keepSelectionIfNotHighlighted) {
			std.mem.copyForwards(u8, out[index..], "1040;");
			index += 5;
		}
		if (self.urgencyWindowManagerHintOnCtrlG) {
			std.mem.copyForwards(u8, out[index..], "1042;");
			index += 5;
		}
		if (self.raiseWindowOnCtrlG) {
			std.mem.copyForwards(u8, out[index..], "1043;");
			index += 5;
		}
		if (self.reuseMostRecentDataFromClipboard) {
			std.mem.copyForwards(u8, out[index..], "1044;");
			index += 5;
		}
		if (self.extendedReverseWraparound) {
			std.mem.copyForwards(u8, out[index..], "1045;");
			index += 5;
		}
		if (self.switchingAlternateScreenBuffer) {
			std.mem.copyForwards(u8, out[index..], "1046;");
			index += 5;
		}
		if (self.alternateScreenBuffer) {
			std.mem.copyForwards(u8, out[index..], "1047;");
			index += 5;
		}
		if (self.saveCursor) {
			std.mem.copyForwards(u8, out[index..], "1048;");
			index += 5;
		}
		if (self.saveCursorSwitchClearedAlternateScreenBuffer) {
			std.mem.copyForwards(u8, out[index..], "1049;");
			index += 5;
		}
		if (self.terminfoTermcapFnKey) {
			std.mem.copyForwards(u8, out[index..], "1050;");
			index += 5;
		}
		if (self.sunFnKey) {
			std.mem.copyForwards(u8, out[index..], "1051;");
			index += 5;
		}
		if (self.hpFnKey) {
			std.mem.copyForwards(u8, out[index..], "1052;");
			index += 5;
		}
		if (self.scoFnKey) {
			std.mem.copyForwards(u8, out[index..], "1053;");
			index += 5;
		}
		if (self.legacyKeyboardEmulation) {
			std.mem.copyForwards(u8, out[index..], "1060;");
			index += 5;
		}
		if (self.vt220KeyboardEmulation) {
			std.mem.copyForwards(u8, out[index..], "1061;");
			index += 5;
		}
		if (self.readlineMouseBtn1) {
			std.mem.copyForwards(u8, out[index..], "2001;");
			index += 5;
		}
		if (self.readlineMouseBtn2) {
			std.mem.copyForwards(u8, out[index..], "2002;");
			index += 5;
		}
		if (self.readlineMouseBtn3) {
			std.mem.copyForwards(u8, out[index..], "2003;");
			index += 5;
		}
		if (self.bracketedPasteMode) {
			std.mem.copyForwards(u8, out[index..], "2004;");
			index += 5;
		}
		if (self.readlineCharQuoting) {
			std.mem.copyForwards(u8, out[index..], "2005;");
			index += 5;
		}
		if (self.readlineNewlinePasting) {
			std.mem.copyForwards(u8, out[index..], "2006;");
			index += 5;
		}
		const endIndex = if (out[index-1] == ';') index else index + 1;
		out[endIndex-1] = if (self.isHigh) 'h' else 'l';
		return .{out, endIndex};
	}
};
