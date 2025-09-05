const std = @import("std");

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
pub const alignment = @import("./tui/alignment.zig");
pub const animations = @import("./tui/animations.zig");
pub const bounds = @import("./tui/bounds.zig");
pub const menu = @import("./tui/menu.zig");
pub const options = @import("./tui/options.zig");
pub const sigwinch = @import("./tui/sigwinch.zig");
pub const text = @import("./tui/text.zig");
pub const widgets = @import("./tui/widgets.zig");

test {
    std.testing.refAllDecls(@This());
}
