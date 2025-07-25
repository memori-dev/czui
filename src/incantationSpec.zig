const std = @import("std");
const assert = std.debug.assert;
const stdout = std.io.getStdOut().writer();

const ESC: u8 = 27;
pub const CSI: [2]u8 = .{ESC, '['};

const specNamePrefix = "Spec";

pub const IntParserIterator = struct {
	const Self = @This();

	it: std.mem.SplitIterator(u8, .sequence),

	pub fn next(self: *Self, comptime T: type) error{InvalidCharacter}!?T {
		while (self.it.next()) |str| {
			if (str.len == 0) continue;

			return std.fmt.parseInt(T, str, 10) catch |err| {
				// only invalid ints will cause an error
				if (err == error.InvalidCharacter) return error.InvalidCharacter
				else continue;
			};
		}
		
		return null;
	}

	pub fn init(bytes: []const u8) !Self {
		if (bytes.len == 0) return error.NoArguments;
		return .{.it = std.mem.splitSequence(u8, bytes, ";")};
	}
};

const Builder = struct {
	const Self = @This();

	allocator: std.mem.Allocator,
	al:        std.ArrayList(u8),
	indent:    u8 = 0,

	fn write(self: *Self, comptime bytes: []const u8) void {
		for (0..self.indent) |_| {
			self.al.append('\t') catch unreachable;
		}
		self.al.appendSlice(bytes) catch unreachable;
		self.al.append('\n') catch unreachable;
	}

	fn print(self: *Self, comptime bytes: []const u8, args: anytype) void {
		for (0..self.indent) |_| {
			self.al.append('\t') catch unreachable;
		}
		self.al.appendSlice(std.fmt.allocPrint(self.allocator, bytes, args) catch unreachable) catch unreachable;
		self.al.append('\n') catch unreachable;
	}

	fn init(allocator: std.mem.Allocator) Self {
		return .{
			.allocator = allocator,
			.al        = std.ArrayList(u8).init(allocator)
		};
	}
};

pub const SetResetMode = enum(u5) {
	const PostCSIChar: ?u8 = null;

	keyboardAction =  2,
	replace        =  4,
	sendReceive    = 12,
	normalLinefeed = 20,
};

pub const PrivateMode = enum(u11) {
	const PostCSIChar: ?u8 = '?';

	applicationCursorKeys = 1,
	designateUSASCII = 2,
	columnMode132 = 3,
	smoothScroll = 4,
	reverseVideo = 5,
	origin = 6,
	autoWrap = 7,
	autoRepeat = 8,
	sendMouseXYOnBtnPress = 9,
	showToolbar = 10,
	startBlinkingCursorATT = 12,
	startBlinkingCursor = 13,
	enableXorBlinkingCursor = 14,
	printFormFeed = 18,
	setPrintExtentToFullScreen = 19,
	showCursor = 25,
	showScrollbar = 30,
	enableFontShiftingFns = 35,
	enterTektronix = 38,
	allow80To132 = 40,
	moreFix = 41,
	enableNationalReplacementCharSets = 42,
	enableGraphicExpandedPrint = 43,
	marginBellOrGraphicPrintColor = 44, // TODO depends
	reverseWraparoundOrGraphicPrintColor = 45,
	startLoggingOrGraphicPrint = 46, // TODO depends
	alternateScreenBufferOrGraphicRotatedPrint = 47, // TODO depends
	applicationKeypad = 66,
	backarrowSendsBackspace = 67,
	leftAndRightMargin = 69,
	sixelDisplay = 80,
	doNotClearScreenOnDECCOLM = 95,
	sendMouseXYOnBtnPressAndRelease = 1000,
	hiliteMouseTracking = 1001,
	cellMotionMouseTracking = 1002,
	allMotionMouseTracking = 1003,
	sendFocusInFocusOut = 1004,
	utf8Mouse = 1005,
	sgrMouseMode = 1006,
	alternateScroll = 1007,
	scrollToBorromOnTTYOutput = 1010,
	scrollToBottomOnKeyPress = 1011,
	fastScroll = 1014,
	urxvtMouse = 1015,
	sgrMousePixel = 1016,
	interpretMetaKey = 1034,
	specialModifiersAltNumlock = 1035,
	sendEscOnMetaKeyModifier = 1036,
	sendDelFromEditKeypadDel = 1037,
	sendEscOnAltKeyModifier = 1039,
	keepSelectionIfNotHighlighted = 1040,
	urgencyWindowManagerHintOnCtrlG = 1042,
	raiseWindowOnCtrlG = 1043,
	reuseMostRecentDataFromClipboard = 1044,
	extendedReverseWraparound = 1045,
	switchingAlternateScreenBuffer = 1046,
	alternateScreenBuffer = 1047,
	saveCursor = 1048,
	saveCursorSwitchClearedAlternateScreenBuffer = 1049,
	terminfoTermcapFnKey = 1050,
	sunFnKey = 1051,
	hpFnKey = 1052,
	scoFnKey = 1053,
	legacyKeyboardEmulation = 1060,
	vt220KeyboardEmulation = 1061,
	readlineMouseBtn1 = 2001,
	readlineMouseBtn2 = 2002,
	readlineMouseBtn3 = 2003,
	bracketedPasteMode = 2004,
	readlineCharQuoting = 2005,
	readlineNewlinePasting = 2006,
};

fn generateHiLo(allocator: std.mem.Allocator, comptime Spec: type) !Builder {
	const specTypeInfo = @typeInfo(Spec).@"enum";
	var out = Builder.init(allocator);

	const fullTypeName = @typeName(Spec);
	const typeName = fullTypeName[std.mem.indexOfScalar(u8, fullTypeName, '.').?+1..];

	var minInputLen: usize = 0;
	inline for (std.meta.fields(Spec)) |field| {
		const input = std.fmt.allocPrint(allocator, "{d}", .{field.value}) catch unreachable;
		if (input.len < minInputLen) minInputLen = input.len;
	}


	// header
	out.print("pub const {s} = packed struct {{", .{typeName});

	// consts
	out.indent = 1;
	out.write("const Self = @This();\n");
	if (Spec.PostCSIChar) |char| {
		out.print("pub const postCSIChar: ?u8    = '{c}';", .{char});
		out.print("pub const minLen: usize = {d};", .{CSI.len + 1 + minInputLen + 1});
	}
	else {
		out.write("pub const postCSIChar: ?u8    = null;");
		out.print("pub const minLen: usize = {d};", .{CSI.len + minInputLen + 1});
	}

	// fields
	out.write("");
	out.write("isHigh: bool,");
	inline for (std.meta.fields(Spec)) |field| {
		out.print("{s}: bool = false, // {d}", .{field.name, field.value});
	}

	// parse
	out.write("");
	out.write("pub fn parse(bytes: []const u8) !Self {");
	out.indent = 2;
	out.write("if (bytes.len < Self.minLen) return error.InsufficientLen;");
	out.write("if (!std.mem.eql(u8, &CSI, bytes[0..2])) return error.IncorrectFormat;");
	if (Spec.PostCSIChar) |val| out.print("if (bytes[2] != '{c}') return error.IncorrectFormat;", .{val});
	out.write("if (bytes[bytes.len-1] != 'h' and bytes[bytes.len-1] != 'l') return error.IncorrectFormat;");
	out.write("");
	out.write("var out = Self{.isHigh=bytes[bytes.len-1] == 'h'};");
	out.write("const unmodified = out;");
	out.print("var it = try IntParserIterator.init(bytes[{d}..bytes.len-1]);", .{if (Spec.PostCSIChar != null) 3 else 2});
	out.print("while (try it.next({s})) |val| {{", .{@typeName(specTypeInfo.tag_type)});
	out.indent = 3;
	out.write("switch (val) {");
	out.indent = 4;
	inline for (std.meta.fields(Spec)) |field| {
		out.print("{d} => out.{s} = true,", .{field.value, field.name});
	}
	out.write("// unknown ints are ignored");
	out.write("else => {},");
	out.indent = 3;
	out.write("}");
	out.indent = 2;
	out.write("}");
	out.write("// every field cannot be false, meaning unset");
	out.write("if (out == unmodified) return error.NoValidArguments;");
	out.write("return out;");
	out.indent = 1;
	out.write("}");

	// print
	// ESC[{?Spec.PostCSIChar}{inputs ';' separated}{h or l}
	var maxInputsLen: usize = 0;
	var inputStrs: [std.meta.fields(Spec).len][]const u8 = undefined;
	inline for (std.meta.fields(Spec), 0..) |field, i| {
		inputStrs[i] = std.fmt.allocPrint(allocator, "{d}", .{field.value}) catch unreachable;
		maxInputsLen += inputStrs[i].len;
	}
	maxInputsLen += std.meta.fields(Spec).len - 1;
	const maxLen: usize = CSI.len + (if (Spec.PostCSIChar != null) 1 else 0)  + maxInputsLen + 1;

	out.write("");
	out.print("pub fn print(self: Self) struct{{[{d}]u8, usize}} {{", .{maxLen});
	out.indent = 2;
	out.print("var out: [{d}]u8 = undefined;", .{maxLen});
	out.write("std.mem.copyForwards(u8, &out, &CSI);");
	if (Spec.PostCSIChar) |val| {
		out.print("out[2] = '{c}';", .{val});
		out.write("var index: usize = 3;");
	} else {
		out.write("var index: usize = 2;");		
	}
	inline for (std.meta.fields(Spec), 0..) |field, i| {
		out.print("if (self.{s}) {{", .{field.name});
		out.print("\tstd.mem.copyForwards(u8, out[index..], \"{s};\");", .{inputStrs[i]});
		out.print("\tindex += {d};", .{inputStrs[i].len+1});
		out.write("}");
	}
	out.write("const endIndex = if (out[index-1] == ';') index else index + 1;");
	out.write("out[endIndex-1] = if (self.isHigh) 'h' else 'l';");
	out.write("return .{out, endIndex};");
	out.indent = 1;
	out.write("}");

	// closing brace
	out.indent = 0;
	out.write("};");

	return out;
}

pub fn main() !void {
	var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
	defer arena.deinit();
	const allocator = arena.allocator();

	var file = try std.fs.cwd().createFile("_genIncantations.zig", .{});
	defer file.close();

	var bw = std.io.bufferedWriter(file.writer());
	const writer = bw.writer();

	try writer.writeAll("const std = @import(\"std\");\n");
	try writer.writeAll("const CSI = @import(\"incantationSpec.zig\").CSI;\n");
	try writer.writeAll("const IntParserIterator = @import(\"incantationSpec.zig\").IntParserIterator;\n");
	try writer.writeAll("\n");
	try writer.writeAll((try generateHiLo(allocator, SetResetMode)).al.items);
	try writer.writeAll("\n");
	try writer.writeAll((try generateHiLo(allocator, PrivateMode)).al.items);

	try bw.flush();
}
