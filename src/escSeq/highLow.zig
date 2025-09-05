const std = @import("std");
const expect = std.testing.expect;
const consts = @import("consts.zig");
const VariadicArgs = @import("variadicArgs.zig");
const SetResetMode = @import("_genHighLow.zig").SetResetMode;
const PrivateMode = @import("_genHighLow.zig").PrivateMode;

fn swapArgOrder(comptime Spec: type, comptime Struct: type, comptime sizeOf: usize, in: [sizeOf]u8, len: usize) ![sizeOf]u8 {
	const specTagType = @typeInfo(Spec).@"enum".tag_type;
	var out = in;
	const start = if (Struct.postCSIChar != null) 3 else 2;
	var it = VariadicArgs.init(in[start..len-1]);
	const first = (try it.next(specTagType)).?;
	const second = (try it.next(specTagType)).?;

	var index: usize = start;
	index += (try std.fmt.bufPrint(out[index..], "{d}", .{second})).len;
	out[index] = ';';
	index += 1;
	index += (try std.fmt.bufPrint(out[index..], "{d}", .{first})).len;

	try expect((try it.next(specTagType)) == null);

	return out;
}

// struct (src) -> print (bytes) -> parse (out) -> print (outBytes)
// ensures there is no data loss between conversions for all valid values
fn parsePrint(comptime Struct: type, src: Struct) !void {
	const bytes, const len = src.print();
				
	const out = try Struct.parse(bytes[0..len]);
	const outBytes, const outLen = out.print();

	try expect(src == out);
	try expect(len == outLen);
	try expect(std.mem.eql(u8, &bytes, &outBytes));
}

// TODO have this take in isHigh as an arg to easily test both without needing to implement it in each sub-test
fn testFn(comptime Spec: type, comptime Struct: type) !void {
	const specBackingType = @typeInfo(Spec).@"enum".tag_type;

	// every field parses and prints
	inline for (std.meta.fields(Spec)) |field| {
		for ([2]bool{true, false}) |isHigh| {
			var src: Struct = .{.isHigh = isHigh};
			@field(src, field.name) = true;

			try parsePrint(Struct, src);
		}
	}

	// multiple:
	//// tests that two arguments are valid
	//// tests that order does not affect the output (also makes the last test combinations instead of permutations)
	//// tests all combinations for:
	////// an increase in value when setting additional properties to true
	////// uniqueness
	////// parsePrint
	{
		const backingType = @typeInfo(Struct).@"struct".backing_integer.?;
		// two are valid
		const one = std.meta.fields(Spec)[0];
		const two = std.meta.fields(Spec)[1];

		var srcOne: Struct = .{.isHigh = false};
		@field(srcOne, one.name) = true;
		
		var srcTwo: Struct = .{.isHigh = false};
		@field(srcTwo, two.name) = true;

		var srcBoth: Struct = .{.isHigh = false};
		@field(srcBoth, one.name) = true;
		@field(srcBoth, two.name) = true;

		const oneBits: backingType = @bitCast(srcOne);
		const twoBits: backingType = @bitCast(srcTwo);
		const bothBits: backingType = @bitCast(srcBoth);

		try expect(oneBits != twoBits and oneBits != bothBits and twoBits != bothBits);
		try expect(bothBits > oneBits and bothBits > twoBits);
		try expect(bothBits == oneBits | twoBits and bothBits ^ oneBits ^ twoBits == 0);

		try parsePrint(Struct, srcBoth);

		// order doesn't matter
		const outBytes, const outLen = srcBoth.print();
		const swap = try swapArgOrder(Spec, Struct, @sizeOf(@TypeOf(outBytes)), outBytes, outLen);
		try expect(!std.mem.eql(u8, &outBytes, &swap));

		try parsePrint(Struct, try Struct.parse(swap[0..outLen]));

		// test combinations by iterating and making each true one at a time
		const totalCombinations = (std.meta.fields(Spec).len + 1) * @round(@as(f32, @floatFromInt(std.meta.fields(Spec).len)) / 2);
		var combinationBits: [totalCombinations]backingType = @splat(0);
		var index: usize = 0;
		@setEvalBranchQuota(5000);
		inline for (std.meta.fields(Spec), 1..) |start, i| {
			var multiple: Struct = .{.isHigh = false};
			@field(multiple, start.name) = true;

			inline for (std.meta.fields(Spec)[i..]) |proceeding| {
				const lastBits: backingType = @bitCast(multiple);
				@field(multiple, proceeding.name) = true;

				const currBits: backingType = @bitCast(multiple);

				try expect(lastBits != currBits);
				try expect(currBits > lastBits);
				try expect(std.mem.indexOfScalar(backingType, &combinationBits, currBits) == null);
				try parsePrint(Struct, multiple);

				combinationBits[index] = currBits;
				index += 1;
			}
		}
	}

	// InsufficientLen
	// checks all lens less than min len and returns InsufficientLen
	{
		var buf: [Struct.minLen]u8 = undefined;
		for (0..Struct.minLen) |i| try expect(Struct.parse(buf[0..i]) == error.InsufficientLen);
	}

	// IncorrectFormat
	// checks that it will return IncorrectFormat if any format char is incorrect
	{
		const emptyStruct, const emptyLen = Struct.print(Struct{.isHigh = true});
		for (0..emptyLen) |i| {
			var copy = emptyStruct;
			copy[i] = copy[i] +% 1;
			try expect(Struct.parse(&copy) == error.IncorrectFormat);
		}
	}

	// InvalidInt
	//// unknown ints are ignored
	//// numbers out of range are ignored
	//// empty are valid and ignored
	//// non-numeric chars cause an error
	// TODO tests these ints before, inbetween, and after valid ints
	{
		// if this expect fails then the buffer likely will not be large enough
		try expect(std.math.maxInt(specBackingType) <= std.math.maxInt(u16));
		var buf: [consts.u16MaxStrLen + Struct.minLen]u8 = undefined;
		const fmt = consts.CSI ++ (if (Struct.postCSIChar) |val| [1]u8{val} else [0]u8{}) ++ "{d}h";
		
		// unknown ints are ignored
		for (0..std.math.maxInt(specBackingType)+1) |i| {
			// number must not be a valid Spec enum val
			if (std.meta.intToEnum(Spec, i) != std.meta.IntToEnumError.InvalidEnumTag) continue;

			const str = std.fmt.bufPrint(&buf, fmt, .{i}) catch unreachable;
			try expect(Struct.parse(str) == error.NoValidArguments);
		}

		// numbers out of range are ignored
		for (std.math.maxInt(specBackingType)+1..std.math.maxInt(u16)+1) |i| {
			// number must not be a valid Spec enum val
			try expect(std.meta.intToEnum(Spec, i) == std.meta.IntToEnumError.InvalidEnumTag);

			const str = std.fmt.bufPrint(&buf, fmt, .{i}) catch unreachable;
			try expect(Struct.parse(str) == error.NoValidArguments);
		}

		// empty are valid and ignored
		try expect(Struct.parse(consts.CSI ++ (if (Struct.postCSIChar) |val| [1]u8{val} else [0]u8{}) ++ ";;h") == error.NoValidArguments);

		// non-numeric chars cause an error
		const charFmt = consts.CSI ++ (if (Struct.postCSIChar) |val| [1]u8{val} else [0]u8{}) ++ "{c}h";
		for (0..std.math.maxInt(u8)+1) |i| {
			// ignore 0-9
			if (i >= 48 and i <= 57) continue;
			// ignore ;
			if (i == ';') continue;

			const str = std.fmt.bufPrint(&buf, charFmt, .{@as(u8, @truncate(i))}) catch unreachable;
			try expect(Struct.parse(str) == error.InvalidCharacter);
		}
	}

	// TODO No valid arguments
	//// empty, unknown, and out of range ints in any combination should return this error
}

test "HighLow" {
	const incantationSpec = @import("incantationSpec.zig");
	const SetResetModeSpec = incantationSpec.SetResetMode;
	const PrivateModeSpec = incantationSpec.PrivateMode;

	try testFn(SetResetModeSpec, SetResetMode);
	try testFn(PrivateModeSpec, PrivateMode);
}
