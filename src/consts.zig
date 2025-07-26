pub const ESC: u8 = 27;
pub const CSI: [2]u8 = .{ESC, '['};
pub const u16MaxStrLen: usize = 5;
pub const u64MaxStrLen: usize = 20;
pub const ASCIIIntOffset: u8 = 48;
pub const separator: u8 = ';';
// only up to u16 is necessary for incantations
pub const UInt1To16 = [16]type{u1,u2,u3,u4,u5,u6,u7,u8,u9,u10,u11,u12,u13,u14,u15,u16};
