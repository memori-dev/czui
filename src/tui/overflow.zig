pub const TextOverflow = enum {
	pub const charSentinel: []const u8 = "…";
	pub const strSentinel:  []const u8 = "...";
	
	// prints the maximum amount ignoring any overflow
	clip,
	// replaces the end of the text with the sentinel on overflow
	sentinel,
	// prints the maximum amount per line, splitting into multiple on overflow
	wrap,
	// prints entirely, else returns an error
	err,
};

pub const Overflow = enum {
	// prints the maximum amount ignoring any overflow
	clip,
	// replaces the last line with the sentinel on overflow
	sentinel,
	// prints entirely, else returns an error
	err,
};
