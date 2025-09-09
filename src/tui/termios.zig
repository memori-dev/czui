const std = @import("std");

const posix = std.posix;
const linux = std.os.linux;

// https://ziglang.org/documentation/master/std/#std.os.linux.termios
// https://ziglang.org/documentation/master/std/#std.os.linux.tc_lflag_t
pub fn icanonSet(val: bool) void {
	var term: linux.termios = undefined;
	_ = linux.tcgetattr(1, &term);
	term.lflag.ICANON = val;
	_ = linux.tcsetattr(1, posix.TCSA.NOW, &term);
}

pub fn echoSet(val: bool) void {
	var term: linux.termios = undefined;
	_ = linux.tcgetattr(1, &term);
	term.lflag.ECHO = val;
	_ = linux.tcsetattr(1, posix.TCSA.NOW, &term);
}
