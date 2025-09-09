const std = @import("std");

// escSeq
pub const CursorStyle = @import("./escSeq/singularArg.zig").CursorStyle;
pub const DeviceStatusReport = @import("./escSeq/singularArg.zig").DeviceStatusReport;
pub const EraseDisplay = @import("./escSeq/singularArg.zig").EraseDisplay;
pub const EraseLine = @import("./escSeq/singularArg.zig").EraseLine;
pub const EscSeq = @import("./escSeq/escSeq.zig").EscSeq;
pub const FnKey = @import("./escSeq/fnKey.zig").FnKey;
pub const graphics = @import("./escSeq/graphics.zig");
pub const mouse = @import("./escSeq/mouse.zig");
pub const NavKey = @import("./escSeq/singularArg.zig").NavKey;
pub const PrivateMode = @import("./escSeq/_genHighLow.zig").PrivateMode;
pub const SetResetMode = @import("./escSeq/_genHighLow.zig").SetResetMode;

// input
pub const input = @import("./input/input.zig");

// tui
pub const tui = .{
    .alignment  = @import("./tui/alignment.zig"),
    .animations = @import("./tui/animations.zig"),
    .bounds     = @import("./tui/bounds.zig"),
    .input      = @import("./tui/input.zig"),
    .menu       = @import("./tui/menu.zig"),
    .options    = @import("./tui/options.zig"),
    .sigwinch   = @import("./tui/sigwinch.zig"),
    .termios    = @import("./tui/termios.zig"),
    .text       = @import("./tui/text.zig"),
    .widgets    = @import("./tui/widgets.zig"),
};

test {
    std.testing.refAllDecls(@This());
}
