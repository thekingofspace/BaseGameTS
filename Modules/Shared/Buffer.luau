--!strict
--!optimize 2

--[[
	Buffer — expanded buffer tooling.

	This module forwards every unknown index to the built-in `buffer` library
	through __index, so it is a drop-in replacement:

		local Buffer = require(ReplicatedStorage.Shared.Buffer)

		local b = Buffer.create(16)      -- built-in, reached through __index
		Buffer.writeu32(b, 0, 1234)      -- built-in
		b = Buffer.Resize(b, 32)         -- added here

	Built-in members keep their lowercase names; everything added by this module
	is PascalCase, so the two sets can never collide.

	Buffers are fixed-size in Luau. Anything that changes a length (Resize, Grow,
	Slice, Concat, ...) allocates a new buffer and returns it — it cannot mutate
	the original in place. Always use the return value.

	Byte offsets are 0-based, matching the built-in library.
]]

local Buffer = {}

-------------------------------------------------------------------- Types

export type Writer = {
	WriteU8: (self: Writer, value: number) -> Writer,
	WriteU16: (self: Writer, value: number) -> Writer,
	WriteU32: (self: Writer, value: number) -> Writer,
	WriteI8: (self: Writer, value: number) -> Writer,
	WriteI16: (self: Writer, value: number) -> Writer,
	WriteI32: (self: Writer, value: number) -> Writer,
	WriteF32: (self: Writer, value: number) -> Writer,
	WriteF64: (self: Writer, value: number) -> Writer,
	WriteBool: (self: Writer, value: boolean) -> Writer,
	WriteVarUInt: (self: Writer, value: number) -> Writer,
	WriteVarInt: (self: Writer, value: number) -> Writer,
	WriteString: (self: Writer, value: string) -> Writer,
	WriteRaw: (self: Writer, value: string) -> Writer,
	WriteBuffer: (self: Writer, source: buffer, offset: number?, count: number?) -> Writer,
	WriteVector2: (self: Writer, value: Vector2) -> Writer,
	WriteVector3: (self: Writer, value: Vector3) -> Writer,
	WriteCFrame: (self: Writer, value: CFrame) -> Writer,
	WriteColor3: (self: Writer, value: Color3) -> Writer,
	WriteColor3Bytes: (self: Writer, value: Color3) -> Writer,
	WriteUDim2: (self: Writer, value: UDim2) -> Writer,
	WritePacked: (self: Writer, format: string, ...any) -> Writer,
	Pad: (self: Writer, count: number) -> Writer,
	Align: (self: Writer, alignment: number) -> Writer,
	Seek: (self: Writer, position: number) -> Writer,
	Tell: (self: Writer) -> number,
	Length: (self: Writer) -> number,
	Capacity: (self: Writer) -> number,
	Reserve: (self: Writer, extra: number) -> Writer,
	Reset: (self: Writer) -> Writer,
	Build: (self: Writer) -> buffer,
	ToString: (self: Writer) -> string,
}

export type Reader = {
	ReadU8: (self: Reader) -> number,
	ReadU16: (self: Reader) -> number,
	ReadU32: (self: Reader) -> number,
	ReadI8: (self: Reader) -> number,
	ReadI16: (self: Reader) -> number,
	ReadI32: (self: Reader) -> number,
	ReadF32: (self: Reader) -> number,
	ReadF64: (self: Reader) -> number,
	ReadBool: (self: Reader) -> boolean,
	ReadVarUInt: (self: Reader) -> number,
	ReadVarInt: (self: Reader) -> number,
	ReadString: (self: Reader) -> string,
	ReadRaw: (self: Reader, count: number) -> string,
	ReadBuffer: (self: Reader, count: number) -> buffer,
	ReadVector2: (self: Reader) -> Vector2,
	ReadVector3: (self: Reader) -> Vector3,
	ReadCFrame: (self: Reader) -> CFrame,
	ReadColor3: (self: Reader) -> Color3,
	ReadColor3Bytes: (self: Reader) -> Color3,
	ReadUDim2: (self: Reader) -> UDim2,
	ReadPacked: (self: Reader, format: string, size: number) -> ...any,
	Skip: (self: Reader, count: number) -> Reader,
	Align: (self: Reader, alignment: number) -> Reader,
	Seek: (self: Reader, position: number) -> Reader,
	Tell: (self: Reader) -> number,
	Remaining: (self: Reader) -> number,
	IsFinished: (self: Reader) -> boolean,
	Reset: (self: Reader) -> Reader,
	Source: (self: Reader) -> buffer,
}

export type PoolStats = {
	Live: number,
	Pooled: number,
	Hits: number,
	Misses: number,
	Classes: { [number]: number },
}

export type Pool = {
	Get: (self: Pool, size: number) -> buffer,
	Release: (self: Pool, block: buffer) -> boolean,
	Preallocate: (self: Pool, size: number, count: number) -> (),
	Stats: (self: Pool) -> PoolStats,
	Clear: (self: Pool) -> (),
}

export type Arena = {
	Alloc: (self: Arena, size: number, alignment: number?) -> number,
	TryAlloc: (self: Arena, size: number, alignment: number?) -> number?,
	Mark: (self: Arena) -> number,
	Rewind: (self: Arena, mark: number) -> (),
	Reset: (self: Arena) -> (),
	Buffer: (self: Arena) -> buffer,
	Used: (self: Arena) -> number,
	Capacity: (self: Arena) -> number,
	Remaining: (self: Arena) -> number,
}

-------------------------------------------------------------------- Internal helpers

local MIN_POOL_CLASS = 16
local MAX_SAFE_VARINT = 2 ^ 53

local function fail(fname: string, message: string): any
	error(("Buffer.%s: %s"):format(fname, message), 3)
end

local function checkBuffer(value: any, argName: string, fname: string): buffer
	if type(value) ~= "buffer" then
		fail(fname, ("%s must be a buffer, got %s"):format(argName, type(value)))
	end
	return value
end

local function checkSize(value: any, argName: string, fname: string): number
	if type(value) ~= "number" or value ~= value or value < 0 then
		fail(fname, ("%s must be a non-negative number, got %s"):format(argName, tostring(value)))
	end
	return math.floor(value)
end

local function window(b: buffer, offset: number?, count: number?, fname: string): (number, number)
	local len = buffer.len(b)
	local start = if offset ~= nil then math.floor(offset) else 0
	local size = if count ~= nil then math.floor(count) else len - start

	if start < 0 or size < 0 or start + size > len then
		fail(fname, ("range [%d, %d) is outside a buffer of %d bytes"):format(start, start + size, len))
	end

	return start, size
end

local function nextPowerOfTwo(n: number): number
	local size = MIN_POOL_CLASS
	while size < n do
		size *= 2
	end
	return size
end

-------------------------------------------------------------------- Constants

Buffer.Sizes = table.freeze({
	i8 = 1,
	u8 = 1,
	i16 = 2,
	u16 = 2,
	i32 = 4,
	u32 = 4,
	f32 = 4,
	f64 = 8,
	bool = 1,
	Vector2 = 8,
	Vector3 = 12,
	CFrame = 28,
	Color3 = 12,
	Color3Bytes = 3,
	UDim2 = 16,
})

-------------------------------------------------------------------- Creation and sizing

function Buffer.new(size: number): buffer
	return buffer.create(checkSize(size, "size", "new"))
end

function Buffer.From(value: string | buffer | { number }): buffer
	if type(value) == "string" then
		return buffer.fromstring(value)
	elseif type(value) == "buffer" then
		local out = buffer.create(buffer.len(value))
		buffer.copy(out, 0, value, 0)
		return out
	elseif type(value) == "table" then
		local out = buffer.create(#value)
		for index, byte in ipairs(value) do
			buffer.writeu8(out, index - 1, byte)
		end
		return out
	end

	return fail("From", ("cannot build a buffer from a %s"):format(type(value)))
end

function Buffer.Resize(b: buffer, newSize: number): buffer
	checkBuffer(b, "b", "Resize")
	local size = checkSize(newSize, "newSize", "Resize")
	local len = buffer.len(b)

	if size == len then
		return b
	end

	local out = buffer.create(size)
	buffer.copy(out, 0, b, 0, math.min(len, size))
	return out
end

function Buffer.Grow(b: buffer, extra: number): buffer
	checkBuffer(b, "b", "Grow")
	return Buffer.Resize(b, math.max(0, buffer.len(b) + math.floor(extra)))
end

function Buffer.Truncate(b: buffer, size: number): buffer
	checkBuffer(b, "b", "Truncate")
	return Buffer.Resize(b, math.min(buffer.len(b), checkSize(size, "size", "Truncate")))
end

function Buffer.Reserve(b: buffer, needed: number): buffer
	checkBuffer(b, "b", "Reserve")
	local want = checkSize(needed, "needed", "Reserve")
	local len = buffer.len(b)

	if len >= want then
		return b
	end

	return Buffer.Resize(b, math.max(want, math.max(len * 2, MIN_POOL_CLASS)))
end

function Buffer.Clone(b: buffer): buffer
	checkBuffer(b, "b", "Clone")
	local out = buffer.create(buffer.len(b))
	buffer.copy(out, 0, b, 0)
	return out
end

function Buffer.Slice(b: buffer, offset: number?, count: number?): buffer
	checkBuffer(b, "b", "Slice")
	local start, size = window(b, offset, count, "Slice")
	local out = buffer.create(size)
	buffer.copy(out, 0, b, start, size)
	return out
end

function Buffer.Concat(...: buffer): buffer
	local count = select("#", ...)
	local total = 0

	for index = 1, count do
		total += buffer.len(checkBuffer((select(index, ...)), ("argument %d"):format(index), "Concat"))
	end

	local out = buffer.create(total)
	local at = 0

	for index = 1, count do
		local piece = (select(index, ...)) :: buffer
		local size = buffer.len(piece)
		buffer.copy(out, at, piece, 0, size)
		at += size
	end

	return out
end

function Buffer.Join(list: { buffer }, separator: buffer?): buffer
	local gap = if separator ~= nil then buffer.len(separator) else 0
	local total = 0

	for index, piece in ipairs(list) do
		total += buffer.len(checkBuffer(piece, ("list[%d]"):format(index), "Join"))
	end

	if #list > 1 then
		total += gap * (#list - 1)
	end

	local out = buffer.create(total)
	local at = 0

	for index, piece in ipairs(list) do
		if index > 1 and separator ~= nil then
			buffer.copy(out, at, separator, 0, gap)
			at += gap
		end
		local size = buffer.len(piece)
		buffer.copy(out, at, piece, 0, size)
		at += size
	end

	return out
end

function Buffer.Split(b: buffer, chunkSize: number): { buffer }
	checkBuffer(b, "b", "Split")
	local size = checkSize(chunkSize, "chunkSize", "Split")

	if size == 0 then
		fail("Split", "chunkSize must be at least 1")
	end

	local len = buffer.len(b)
	local out = table.create(math.ceil(len / size)) :: { buffer }
	local at = 0

	while at < len do
		local take = math.min(size, len - at)
		local chunk = buffer.create(take)
		buffer.copy(chunk, 0, b, at, take)
		table.insert(out, chunk)
		at += take
	end

	return out
end

function Buffer.Repeat(b: buffer, times: number): buffer
	checkBuffer(b, "b", "Repeat")
	local count = checkSize(times, "times", "Repeat")
	local len = buffer.len(b)
	local out = buffer.create(len * count)

	for index = 0, count - 1 do
		buffer.copy(out, index * len, b, 0, len)
	end

	return out
end

-------------------------------------------------------------------- Inspection

function Buffer.IsBuffer(value: any): boolean
	return type(value) == "buffer"
end

function Buffer.IsEmpty(b: buffer): boolean
	checkBuffer(b, "b", "IsEmpty")
	return buffer.len(b) == 0
end

function Buffer.ToArray(b: buffer, offset: number?, count: number?): { number }
	checkBuffer(b, "b", "ToArray")
	local start, size = window(b, offset, count, "ToArray")
	local out = table.create(size) :: { number }

	for index = 0, size - 1 do
		out[index + 1] = buffer.readu8(b, start + index)
	end

	return out
end

function Buffer.IsZeroed(b: buffer, offset: number?, count: number?): boolean
	checkBuffer(b, "b", "IsZeroed")
	local start, size = window(b, offset, count, "IsZeroed")
	local at = start
	local wordEnd = start + size - (size % 4)

	while at < wordEnd do
		if buffer.readu32(b, at) ~= 0 then
			return false
		end
		at += 4
	end

	while at < start + size do
		if buffer.readu8(b, at) ~= 0 then
			return false
		end
		at += 1
	end

	return true
end

function Buffer.CountByte(b: buffer, byte: number, offset: number?, count: number?): number
	checkBuffer(b, "b", "CountByte")
	local start, size = window(b, offset, count, "CountByte")
	local target = bit32.band(math.floor(byte), 0xFF)
	local total = 0

	for index = start, start + size - 1 do
		if buffer.readu8(b, index) == target then
			total += 1
		end
	end

	return total
end

-------------------------------------------------------------------- Mutation

function Buffer.Clear(b: buffer, offset: number?, count: number?): buffer
	checkBuffer(b, "b", "Clear")
	local start, size = window(b, offset, count, "Clear")
	buffer.fill(b, start, 0, size)
	return b
end

function Buffer.CopyWithin(b: buffer, to: number, from: number, count: number?): buffer
	checkBuffer(b, "b", "CopyWithin")
	local source, size = window(b, from, count, "CopyWithin")
	local dest = math.floor(to)

	if dest < 0 or dest + size > buffer.len(b) then
		fail("CopyWithin", ("destination [%d, %d) is outside a buffer of %d bytes"):format(dest, dest + size, buffer.len(b)))
	end

	if size == 0 or dest == source then
		return b
	end

	local scratch = buffer.create(size)
	buffer.copy(scratch, 0, b, source, size)
	buffer.copy(b, dest, scratch, 0, size)
	return b
end

function Buffer.SwapBytes(b: buffer, first: number, second: number): buffer
	checkBuffer(b, "b", "SwapBytes")
	local len = buffer.len(b)
	local a, c = math.floor(first), math.floor(second)

	if a < 0 or c < 0 or a >= len or c >= len then
		fail("SwapBytes", ("offsets %d and %d must both be inside a buffer of %d bytes"):format(a, c, len))
	end

	local left = buffer.readu8(b, a)
	buffer.writeu8(b, a, buffer.readu8(b, c))
	buffer.writeu8(b, c, left)
	return b
end

function Buffer.Reverse(b: buffer, offset: number?, count: number?): buffer
	checkBuffer(b, "b", "Reverse")
	local start, size = window(b, offset, count, "Reverse")
	local left, right = start, start + size - 1

	while left < right do
		local value = buffer.readu8(b, left)
		buffer.writeu8(b, left, buffer.readu8(b, right))
		buffer.writeu8(b, right, value)
		left += 1
		right -= 1
	end

	return b
end

function Buffer.ByteSwap(b: buffer, width: number, offset: number?, count: number?): buffer
	checkBuffer(b, "b", "ByteSwap")

	if width ~= 2 and width ~= 4 and width ~= 8 then
		fail("ByteSwap", ("width must be 2, 4 or 8, got %s"):format(tostring(width)))
	end

	local start, size = window(b, offset, count, "ByteSwap")

	if size % width ~= 0 then
		fail("ByteSwap", ("range of %d bytes is not a whole number of %d-byte words"):format(size, width))
	end

	for word = start, start + size - 1, width do
		Buffer.Reverse(b, word, width)
	end

	return b
end

-------------------------------------------------------------------- Comparison and search

@native
function Buffer.Equals(a: buffer, b: buffer): boolean
	checkBuffer(a, "a", "Equals")
	checkBuffer(b, "b", "Equals")

	local len = buffer.len(a)
	if len ~= buffer.len(b) then
		return false
	end

	local at = 0
	local wordEnd = len - (len % 4)

	while at < wordEnd do
		if buffer.readu32(a, at) ~= buffer.readu32(b, at) then
			return false
		end
		at += 4
	end

	while at < len do
		if buffer.readu8(a, at) ~= buffer.readu8(b, at) then
			return false
		end
		at += 1
	end

	return true
end

function Buffer.Compare(a: buffer, b: buffer): number
	checkBuffer(a, "a", "Compare")
	checkBuffer(b, "b", "Compare")

	local lenA, lenB = buffer.len(a), buffer.len(b)
	local shared = math.min(lenA, lenB)

	for index = 0, shared - 1 do
		local left, right = buffer.readu8(a, index), buffer.readu8(b, index)
		if left ~= right then
			return if left < right then -1 else 1
		end
	end

	if lenA == lenB then
		return 0
	end

	return if lenA < lenB then -1 else 1
end

function Buffer.SecureEquals(a: buffer, b: buffer): boolean
	checkBuffer(a, "a", "SecureEquals")
	checkBuffer(b, "b", "SecureEquals")

	local len = buffer.len(a)
	if len ~= buffer.len(b) then
		return false
	end

	local diff = 0
	for index = 0, len - 1 do
		diff = bit32.bor(diff, bit32.bxor(buffer.readu8(a, index), buffer.readu8(b, index)))
	end

	return diff == 0
end

@native
function Buffer.Find(haystack: buffer, needle: buffer, init: number?): number?
	checkBuffer(haystack, "haystack", "Find")
	checkBuffer(needle, "needle", "Find")

	local hayLen = buffer.len(haystack)
	local needleLen = buffer.len(needle)
	local start = math.max(0, if init ~= nil then math.floor(init) else 0)

	if needleLen == 0 then
		return if start <= hayLen then start else nil
	end

	if needleLen > hayLen then
		return nil
	end

	local first = buffer.readu8(needle, 0)

	for index = start, hayLen - needleLen do
		if buffer.readu8(haystack, index) == first then
			local matched = true
			for step = 1, needleLen - 1 do
				if buffer.readu8(haystack, index + step) ~= buffer.readu8(needle, step) then
					matched = false
					break
				end
			end
			if matched then
				return index
			end
		end
	end

	return nil
end

function Buffer.FindByte(b: buffer, byte: number, init: number?): number?
	checkBuffer(b, "b", "FindByte")
	local target = bit32.band(math.floor(byte), 0xFF)
	local len = buffer.len(b)

	for index = math.max(0, if init ~= nil then math.floor(init) else 0), len - 1 do
		if buffer.readu8(b, index) == target then
			return index
		end
	end

	return nil
end

function Buffer.StartsWith(b: buffer, prefix: buffer): boolean
	checkBuffer(b, "b", "StartsWith")
	checkBuffer(prefix, "prefix", "StartsWith")

	local len = buffer.len(prefix)
	if len > buffer.len(b) then
		return false
	end

	for index = 0, len - 1 do
		if buffer.readu8(b, index) ~= buffer.readu8(prefix, index) then
			return false
		end
	end

	return true
end

function Buffer.EndsWith(b: buffer, suffix: buffer): boolean
	checkBuffer(b, "b", "EndsWith")
	checkBuffer(suffix, "suffix", "EndsWith")

	local len = buffer.len(suffix)
	local base = buffer.len(b) - len
	if base < 0 then
		return false
	end

	for index = 0, len - 1 do
		if buffer.readu8(b, base + index) ~= buffer.readu8(suffix, index) then
			return false
		end
	end

	return true
end

-------------------------------------------------------------------- Bit-level access

local function bitLocation(b: buffer, bitIndex: number, fname: string): (number, number)
	local index = math.floor(bitIndex)
	local byte = index // 8

	if index < 0 or byte >= buffer.len(b) then
		fail(fname, ("bit %d is outside a buffer of %d bytes"):format(index, buffer.len(b)))
	end

	return byte, index % 8
end

function Buffer.GetBit(b: buffer, bitIndex: number): number
	checkBuffer(b, "b", "GetBit")
	local byte, bit = bitLocation(b, bitIndex, "GetBit")
	return bit32.extract(buffer.readu8(b, byte), bit, 1)
end

function Buffer.TestBit(b: buffer, bitIndex: number): boolean
	return Buffer.GetBit(b, bitIndex) == 1
end

function Buffer.SetBit(b: buffer, bitIndex: number, value: boolean | number): buffer
	checkBuffer(b, "b", "SetBit")
	local byte, bit = bitLocation(b, bitIndex, "SetBit")
	local on = if type(value) == "boolean" then value else value ~= 0
	buffer.writeu8(b, byte, bit32.replace(buffer.readu8(b, byte), if on then 1 else 0, bit, 1))
	return b
end

function Buffer.FlipBit(b: buffer, bitIndex: number): buffer
	checkBuffer(b, "b", "FlipBit")
	local byte, bit = bitLocation(b, bitIndex, "FlipBit")
	buffer.writeu8(b, byte, bit32.bxor(buffer.readu8(b, byte), bit32.lshift(1, bit)))
	return b
end

local popcountTable: { number }? = nil

local function popcounts(): { number }
	local existing = popcountTable
	if existing ~= nil then
		return existing
	end

	local built = table.create(256) :: { number }
	for value = 0, 255 do
		local bits = 0
		local rest = value
		while rest ~= 0 do
			bits += bit32.band(rest, 1)
			rest = bit32.rshift(rest, 1)
		end
		built[value + 1] = bits
	end

	popcountTable = built
	return built
end

@native
function Buffer.PopCount(b: buffer, offset: number?, count: number?): number
	checkBuffer(b, "b", "PopCount")
	local start, size = window(b, offset, count, "PopCount")
	local table_ = popcounts()
	local total = 0

	for index = start, start + size - 1 do
		total += table_[buffer.readu8(b, index) + 1]
	end

	return total
end

local function bitwiseInto(fname: string, op: (number, number) -> number, a: buffer, b: buffer, out: buffer?): buffer
	checkBuffer(a, "a", fname)
	checkBuffer(b, "b", fname)

	local len = math.min(buffer.len(a), buffer.len(b))
	local dest = out or buffer.create(len)

	if buffer.len(dest) < len then
		fail(fname, ("output buffer holds %d bytes but %d are needed"):format(buffer.len(dest), len))
	end

	local at = 0
	local wordEnd = len - (len % 4)

	while at < wordEnd do
		buffer.writeu32(dest, at, op(buffer.readu32(a, at), buffer.readu32(b, at)))
		at += 4
	end

	while at < len do
		buffer.writeu8(dest, at, op(buffer.readu8(a, at), buffer.readu8(b, at)))
		at += 1
	end

	return dest
end

function Buffer.BitAnd(a: buffer, b: buffer, out: buffer?): buffer
	return bitwiseInto("BitAnd", bit32.band, a, b, out)
end

function Buffer.BitOr(a: buffer, b: buffer, out: buffer?): buffer
	return bitwiseInto("BitOr", bit32.bor, a, b, out)
end

function Buffer.BitXor(a: buffer, b: buffer, out: buffer?): buffer
	return bitwiseInto("BitXor", bit32.bxor, a, b, out)
end

function Buffer.BitNot(b: buffer, offset: number?, count: number?): buffer
	checkBuffer(b, "b", "BitNot")
	local start, size = window(b, offset, count, "BitNot")
	local at = start
	local wordEnd = start + size - (size % 4)

	while at < wordEnd do
		buffer.writeu32(b, at, bit32.bnot(buffer.readu32(b, at)))
		at += 4
	end

	while at < start + size do
		buffer.writeu8(b, at, bit32.band(bit32.bnot(buffer.readu8(b, at)), 0xFF))
		at += 1
	end

	return b
end

function Buffer.Swap16(value: number): number
	local n = bit32.band(value, 0xFFFF)
	return bit32.bor(bit32.lshift(bit32.band(n, 0xFF), 8), bit32.rshift(n, 8))
end

function Buffer.Swap32(value: number): number
	return bit32.bor(
		bit32.lshift(bit32.band(value, 0xFF), 24),
		bit32.lshift(bit32.band(bit32.rshift(value, 8), 0xFF), 16),
		bit32.lshift(bit32.band(bit32.rshift(value, 16), 0xFF), 8),
		bit32.band(bit32.rshift(value, 24), 0xFF)
	)
end

-------------------------------------------------------------------- Big-endian primitives

function Buffer.ReadU16BE(b: buffer, offset: number): number
	checkBuffer(b, "b", "ReadU16BE")
	return Buffer.Swap16(buffer.readu16(b, offset))
end

function Buffer.WriteU16BE(b: buffer, offset: number, value: number): ()
	checkBuffer(b, "b", "WriteU16BE")
	buffer.writeu16(b, offset, Buffer.Swap16(value))
end

function Buffer.ReadU32BE(b: buffer, offset: number): number
	checkBuffer(b, "b", "ReadU32BE")
	return Buffer.Swap32(buffer.readu32(b, offset))
end

function Buffer.WriteU32BE(b: buffer, offset: number, value: number): ()
	checkBuffer(b, "b", "WriteU32BE")
	buffer.writeu32(b, offset, Buffer.Swap32(value))
end

-------------------------------------------------------------------- string.pack bridge

function Buffer.WritePacked(b: buffer, offset: number, format: string, ...: any): number
	checkBuffer(b, "b", "WritePacked")
	local packed = string.pack(format, ...)
	local start = window(b, offset, #packed, "WritePacked")
	buffer.writestring(b, start, packed)
	return start + #packed
end

function Buffer.ReadPacked(b: buffer, offset: number, format: string, size: number): ...any
	checkBuffer(b, "b", "ReadPacked")
	local start, count = window(b, offset, size, "ReadPacked")
	local packed = buffer.readstring(b, start, count)
	local values = table.pack(string.unpack(format, packed))
	values[values.n] = start + count
	return table.unpack(values, 1, values.n)
end

-------------------------------------------------------------------- Variable-length integers

function Buffer.VarUIntSize(value: number): number
	local rest = math.floor(math.max(0, value))
	local size = 1

	while rest >= 0x80 do
		rest //= 128
		size += 1
	end

	return size
end

function Buffer.WriteVarUInt(b: buffer, offset: number, value: number): number
	checkBuffer(b, "b", "WriteVarUInt")
	local rest = math.floor(value)

	if rest < 0 then
		fail("WriteVarUInt", ("value must be non-negative, got %s (use WriteVarInt)"):format(tostring(value)))
	end

	local at = math.floor(offset)
	local len = buffer.len(b)

	while rest >= 0x80 do
		if at >= len then
			fail("WriteVarUInt", ("ran past the end of a %d byte buffer"):format(len))
		end
		buffer.writeu8(b, at, bit32.bor(bit32.band(rest, 0x7F), 0x80))
		rest //= 128
		at += 1
	end

	if at >= len then
		fail("WriteVarUInt", ("ran past the end of a %d byte buffer"):format(len))
	end

	buffer.writeu8(b, at, rest)
	return at + 1
end

function Buffer.ReadVarUInt(b: buffer, offset: number): (number, number)
	checkBuffer(b, "b", "ReadVarUInt")
	local at = math.floor(offset)
	local len = buffer.len(b)
	local result = 0
	local scale = 1

	while true do
		if at >= len then
			fail("ReadVarUInt", ("ran past the end of a %d byte buffer"):format(len))
		end

		local byte = buffer.readu8(b, at)
		at += 1
		result += bit32.band(byte, 0x7F) * scale

		if byte < 0x80 then
			break
		end

		scale *= 128
		if scale > MAX_SAFE_VARINT then
			fail("ReadVarUInt", "varint is wider than 53 bits")
		end
	end

	return result, at
end

function Buffer.WriteVarInt(b: buffer, offset: number, value: number): number
	local n = math.floor(value)
	return Buffer.WriteVarUInt(b, offset, if n >= 0 then n * 2 else -n * 2 - 1)
end

function Buffer.ReadVarInt(b: buffer, offset: number): (number, number)
	local raw, at = Buffer.ReadVarUInt(b, offset)
	local value = if raw % 2 == 0 then raw // 2 else -((raw + 1) // 2)
	return value, at
end

-------------------------------------------------------------------- Roblox datatypes

function Buffer.WriteVector2(b: buffer, offset: number, value: Vector2): number
	checkBuffer(b, "b", "WriteVector2")
	local at = window(b, offset, 8, "WriteVector2")
	buffer.writef32(b, at, value.X)
	buffer.writef32(b, at + 4, value.Y)
	return at + 8
end

function Buffer.ReadVector2(b: buffer, offset: number): (Vector2, number)
	checkBuffer(b, "b", "ReadVector2")
	local at = window(b, offset, 8, "ReadVector2")
	return Vector2.new(buffer.readf32(b, at), buffer.readf32(b, at + 4)), at + 8
end

function Buffer.WriteVector3(b: buffer, offset: number, value: Vector3): number
	checkBuffer(b, "b", "WriteVector3")
	local at = window(b, offset, 12, "WriteVector3")
	buffer.writef32(b, at, value.X)
	buffer.writef32(b, at + 4, value.Y)
	buffer.writef32(b, at + 8, value.Z)
	return at + 12
end

function Buffer.ReadVector3(b: buffer, offset: number): (Vector3, number)
	checkBuffer(b, "b", "ReadVector3")
	local at = window(b, offset, 12, "ReadVector3")
	local value = Vector3.new(buffer.readf32(b, at), buffer.readf32(b, at + 4), buffer.readf32(b, at + 8))
	return value, at + 12
end

function Buffer.WriteCFrame(b: buffer, offset: number, value: CFrame): number
	checkBuffer(b, "b", "WriteCFrame")
	local at = window(b, offset, 28, "WriteCFrame")
	local position = value.Position
	local axis, angle = value:ToAxisAngle()

	buffer.writef32(b, at, position.X)
	buffer.writef32(b, at + 4, position.Y)
	buffer.writef32(b, at + 8, position.Z)
	buffer.writef32(b, at + 12, axis.X)
	buffer.writef32(b, at + 16, axis.Y)
	buffer.writef32(b, at + 20, axis.Z)
	buffer.writef32(b, at + 24, angle)

	return at + 28
end

function Buffer.ReadCFrame(b: buffer, offset: number): (CFrame, number)
	checkBuffer(b, "b", "ReadCFrame")
	local at = window(b, offset, 28, "ReadCFrame")
	local position = Vector3.new(buffer.readf32(b, at), buffer.readf32(b, at + 4), buffer.readf32(b, at + 8))
	local axis = Vector3.new(buffer.readf32(b, at + 12), buffer.readf32(b, at + 16), buffer.readf32(b, at + 20))
	local angle = buffer.readf32(b, at + 24)

	if axis.Magnitude < 1e-6 then
		axis = Vector3.xAxis
	end

	return CFrame.fromAxisAngle(axis, angle) + position, at + 28
end

function Buffer.WriteColor3(b: buffer, offset: number, value: Color3): number
	checkBuffer(b, "b", "WriteColor3")
	local at = window(b, offset, 12, "WriteColor3")
	buffer.writef32(b, at, value.R)
	buffer.writef32(b, at + 4, value.G)
	buffer.writef32(b, at + 8, value.B)
	return at + 12
end

function Buffer.ReadColor3(b: buffer, offset: number): (Color3, number)
	checkBuffer(b, "b", "ReadColor3")
	local at = window(b, offset, 12, "ReadColor3")
	local value = Color3.new(buffer.readf32(b, at), buffer.readf32(b, at + 4), buffer.readf32(b, at + 8))
	return value, at + 12
end

function Buffer.WriteColor3Bytes(b: buffer, offset: number, value: Color3): number
	checkBuffer(b, "b", "WriteColor3Bytes")
	local at = window(b, offset, 3, "WriteColor3Bytes")
	buffer.writeu8(b, at, math.clamp(math.round(value.R * 255), 0, 255))
	buffer.writeu8(b, at + 1, math.clamp(math.round(value.G * 255), 0, 255))
	buffer.writeu8(b, at + 2, math.clamp(math.round(value.B * 255), 0, 255))
	return at + 3
end

function Buffer.ReadColor3Bytes(b: buffer, offset: number): (Color3, number)
	checkBuffer(b, "b", "ReadColor3Bytes")
	local at = window(b, offset, 3, "ReadColor3Bytes")
	local value = Color3.fromRGB(buffer.readu8(b, at), buffer.readu8(b, at + 1), buffer.readu8(b, at + 2))
	return value, at + 3
end

function Buffer.WriteUDim2(b: buffer, offset: number, value: UDim2): number
	checkBuffer(b, "b", "WriteUDim2")
	local at = window(b, offset, 16, "WriteUDim2")
	buffer.writef32(b, at, value.X.Scale)
	buffer.writei32(b, at + 4, value.X.Offset)
	buffer.writef32(b, at + 8, value.Y.Scale)
	buffer.writei32(b, at + 12, value.Y.Offset)
	return at + 16
end

function Buffer.ReadUDim2(b: buffer, offset: number): (UDim2, number)
	checkBuffer(b, "b", "ReadUDim2")
	local at = window(b, offset, 16, "ReadUDim2")
	local value = UDim2.new(
		buffer.readf32(b, at),
		buffer.readi32(b, at + 4),
		buffer.readf32(b, at + 8),
		buffer.readi32(b, at + 12)
	)
	return value, at + 16
end

-------------------------------------------------------------------- Encoding

local HEX_BYTES: { string }? = nil

local function hexBytes(): { string }
	local existing = HEX_BYTES
	if existing ~= nil then
		return existing
	end

	local built = table.create(256) :: { string }
	for value = 0, 255 do
		built[value + 1] = string.format("%02x", value)
	end

	HEX_BYTES = built
	return built
end

function Buffer.ToHex(b: buffer, separator: string?): string
	checkBuffer(b, "b", "ToHex")
	local len = buffer.len(b)
	local lookup = hexBytes()
	local parts = table.create(len) :: { string }

	for index = 0, len - 1 do
		parts[index + 1] = lookup[buffer.readu8(b, index) + 1]
	end

	return table.concat(parts, separator or "")
end

function Buffer.FromHex(text: string): buffer
	local cleaned = (text:gsub("[%s:%-]", ""))

	if #cleaned % 2 ~= 0 then
		fail("FromHex", ("expected an even number of hex digits, got %d"):format(#cleaned))
	end

	local out = buffer.create(#cleaned // 2)

	for index = 1, #cleaned, 2 do
		local byte = tonumber(cleaned:sub(index, index + 1), 16)
		if byte == nil then
			return fail("FromHex", ("'%s' is not a hex byte"):format(cleaned:sub(index, index + 1)))
		end
		buffer.writeu8(out, (index - 1) // 2, byte)
	end

	return out
end

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local base64Decode: { [string]: number }? = nil

local function base64Lookup(): { [string]: number }
	local existing = base64Decode
	if existing ~= nil then
		return existing
	end

	local built: { [string]: number } = {}
	for index = 1, #BASE64_ALPHABET do
		built[BASE64_ALPHABET:sub(index, index)] = index - 1
	end

	base64Decode = built
	return built
end

local function base64Group(chunk: number, bytes: number): string
	local symbols = table.create(4) :: { string }

	for slot = 0, 3 do
		if slot <= bytes then
			local index = bit32.extract(chunk, 18 - slot * 6, 6) + 1
			symbols[slot + 1] = BASE64_ALPHABET:sub(index, index)
		else
			symbols[slot + 1] = "="
		end
	end

	return table.concat(symbols)
end

function Buffer.ToBase64(b: buffer): string
	checkBuffer(b, "b", "ToBase64")
	local len = buffer.len(b)
	local parts = table.create(math.ceil(len / 3)) :: { string }
	local at = 0

	while at < len do
		local take = math.min(3, len - at)
		local chunk = bit32.lshift(buffer.readu8(b, at), 16)

		if take > 1 then
			chunk = bit32.bor(chunk, bit32.lshift(buffer.readu8(b, at + 1), 8))
		end
		if take > 2 then
			chunk = bit32.bor(chunk, buffer.readu8(b, at + 2))
		end

		table.insert(parts, base64Group(chunk, take))
		at += take
	end

	return table.concat(parts)
end

function Buffer.FromBase64(text: string): buffer
	local lookup = base64Lookup()
	local symbols = table.create(#text) :: { number }

	for index = 1, #text do
		local character = text:sub(index, index)
		local value = lookup[character]
		if value ~= nil then
			table.insert(symbols, value)
		elseif character ~= "=" and character:match("%s") == nil then
			fail("FromBase64", ("'%s' is not a base64 character"):format(character))
		end
	end

	local out = buffer.create((#symbols * 6) // 8)
	local at = 0
	local index = 1

	while index + 3 <= #symbols do
		local chunk = bit32.bor(
			bit32.lshift(symbols[index], 18),
			bit32.lshift(symbols[index + 1], 12),
			bit32.lshift(symbols[index + 2], 6),
			symbols[index + 3]
		)
		buffer.writeu8(out, at, bit32.extract(chunk, 16, 8))
		buffer.writeu8(out, at + 1, bit32.extract(chunk, 8, 8))
		buffer.writeu8(out, at + 2, bit32.extract(chunk, 0, 8))
		at += 3
		index += 4
	end

	local left = #symbols - index + 1
	if left == 2 then
		buffer.writeu8(out, at, bit32.band(bit32.bor(bit32.lshift(symbols[index], 2), bit32.rshift(symbols[index + 1], 4)), 0xFF))
	elseif left == 3 then
		buffer.writeu8(out, at, bit32.band(bit32.bor(bit32.lshift(symbols[index], 2), bit32.rshift(symbols[index + 1], 4)), 0xFF))
		buffer.writeu8(out, at + 1, bit32.band(bit32.bor(bit32.lshift(symbols[index + 1], 4), bit32.rshift(symbols[index + 2], 2)), 0xFF))
	end

	return out
end

function Buffer.HexDump(b: buffer, bytesPerRow: number?): string
	checkBuffer(b, "b", "HexDump")
	local perRow = math.max(1, math.floor(bytesPerRow or 16))
	local len = buffer.len(b)
	local lookup = hexBytes()
	local rows = table.create(math.ceil(len / perRow)) :: { string }

	for rowStart = 0, len - 1, perRow do
		local hex = table.create(perRow) :: { string }
		local ascii = table.create(perRow) :: { string }

		for column = 0, perRow - 1 do
			local at = rowStart + column
			if at < len then
				local byte = buffer.readu8(b, at)
				table.insert(hex, lookup[byte + 1])
				table.insert(ascii, if byte >= 0x20 and byte < 0x7F then string.char(byte) else ".")
			else
				table.insert(hex, "  ")
			end
		end

		table.insert(rows, ("%08X  %s  |%s|"):format(rowStart, table.concat(hex, " "), table.concat(ascii)))
	end

	if #rows == 0 then
		return "(empty buffer)"
	end

	return table.concat(rows, "\n")
end

-------------------------------------------------------------------- Checksums

local crcTable: { number }? = nil

local function crc32Table(): { number }
	local existing = crcTable
	if existing ~= nil then
		return existing
	end

	local built = table.create(256) :: { number }
	for value = 0, 255 do
		local rest = value
		for _ = 1, 8 do
			if bit32.band(rest, 1) == 1 then
				rest = bit32.bxor(0xEDB88320, bit32.rshift(rest, 1))
			else
				rest = bit32.rshift(rest, 1)
			end
		end
		built[value + 1] = rest
	end

	crcTable = built
	return built
end

@native
function Buffer.CRC32(b: buffer, offset: number?, count: number?): number
	checkBuffer(b, "b", "CRC32")
	local start, size = window(b, offset, count, "CRC32")
	local lookup = crc32Table()
	local crc = 0xFFFFFFFF

	for index = start, start + size - 1 do
		local slot = bit32.band(bit32.bxor(crc, buffer.readu8(b, index)), 0xFF)
		crc = bit32.bxor(lookup[slot + 1], bit32.rshift(crc, 8))
	end

	return bit32.bxor(crc, 0xFFFFFFFF)
end

@native
function Buffer.Adler32(b: buffer, offset: number?, count: number?): number
	checkBuffer(b, "b", "Adler32")
	local start, size = window(b, offset, count, "Adler32")
	local low, high = 1, 0

	for index = start, start + size - 1 do
		low = (low + buffer.readu8(b, index)) % 65521
		high = (high + low) % 65521
	end

	return high * 65536 + low
end

@native
function Buffer.FNV1a32(b: buffer, offset: number?, count: number?): number
	checkBuffer(b, "b", "FNV1a32")
	local start, size = window(b, offset, count, "FNV1a32")
	local hash = 2166136261

	for index = start, start + size - 1 do
		hash = bit32.bxor(hash, buffer.readu8(b, index))
		local low = bit32.band(hash, 0xFFFF) * 16777619
		local high = bit32.rshift(hash, 16) * 16777619
		hash = bit32.band(low + bit32.lshift(high, 16), 0xFFFFFFFF)
	end

	return hash
end

-------------------------------------------------------------------- Writer

local writerMeta = {}
writerMeta.__index = writerMeta

function writerMeta.__len(self: any): number
	return self.used
end

function writerMeta.__tostring(self: any): string
	return ("Buffer.Writer(%d/%d bytes)"):format(self.used, buffer.len(self.blob))
end

local function writerReserve(self: any, extra: number)
	local needed = self.cursor + extra
	local capacity = buffer.len(self.blob)

	if needed <= capacity then
		return
	end

	local grown = buffer.create(math.max(needed, math.max(capacity * 2, MIN_POOL_CLASS)))
	buffer.copy(grown, 0, self.blob, 0, self.used)
	self.blob = grown
end

local function writerAdvance(self: any, size: number)
	self.cursor += size
	if self.cursor > self.used then
		self.used = self.cursor
	end
end

function Buffer.Writer(capacity: number?): Writer
	local self = setmetatable({
		blob = buffer.create(math.max(MIN_POOL_CLASS, math.floor(capacity or 64))),
		cursor = 0,
		used = 0,
	}, writerMeta)

	return self :: any
end

local WRITER_PRIMITIVES: { { name: string, size: number, write: (buffer, number, number) -> () } } = {
	{ name = "WriteU8", size = 1, write = buffer.writeu8 },
	{ name = "WriteU16", size = 2, write = buffer.writeu16 },
	{ name = "WriteU32", size = 4, write = buffer.writeu32 },
	{ name = "WriteI8", size = 1, write = buffer.writei8 },
	{ name = "WriteI16", size = 2, write = buffer.writei16 },
	{ name = "WriteI32", size = 4, write = buffer.writei32 },
	{ name = "WriteF32", size = 4, write = buffer.writef32 },
	{ name = "WriteF64", size = 8, write = buffer.writef64 },
}

for _, entry in ipairs(WRITER_PRIMITIVES) do
	local size, write = entry.size, entry.write
	writerMeta[entry.name] = function(self: any, value: number): any
		writerReserve(self, size)
		write(self.blob, self.cursor, value)
		writerAdvance(self, size)
		return self
	end
end

function writerMeta.WriteBool(self: any, value: boolean): any
	writerReserve(self, 1)
	buffer.writeu8(self.blob, self.cursor, if value then 1 else 0)
	writerAdvance(self, 1)
	return self
end

function writerMeta.WriteVarUInt(self: any, value: number): any
	writerReserve(self, 8)
	local at = Buffer.WriteVarUInt(self.blob, self.cursor, value)
	writerAdvance(self, at - self.cursor)
	return self
end

function writerMeta.WriteVarInt(self: any, value: number): any
	local n = math.floor(value)
	return writerMeta.WriteVarUInt(self, if n >= 0 then n * 2 else -n * 2 - 1)
end

function writerMeta.WriteRaw(self: any, value: string): any
	writerReserve(self, #value)
	buffer.writestring(self.blob, self.cursor, value)
	writerAdvance(self, #value)
	return self
end

function writerMeta.WriteString(self: any, value: string): any
	writerMeta.WriteVarUInt(self, #value)
	return writerMeta.WriteRaw(self, value)
end

function writerMeta.WriteBuffer(self: any, source: buffer, offset: number?, count: number?): any
	checkBuffer(source, "source", "Writer:WriteBuffer")
	local start, size = window(source, offset, count, "Writer:WriteBuffer")
	writerReserve(self, size)
	buffer.copy(self.blob, self.cursor, source, start, size)
	writerAdvance(self, size)
	return self
end

local WRITER_DATATYPES: { { name: string, size: number, write: (buffer, number, any) -> number } } = {
	{ name = "WriteVector2", size = 8, write = Buffer.WriteVector2 },
	{ name = "WriteVector3", size = 12, write = Buffer.WriteVector3 },
	{ name = "WriteCFrame", size = 28, write = Buffer.WriteCFrame },
	{ name = "WriteColor3", size = 12, write = Buffer.WriteColor3 },
	{ name = "WriteColor3Bytes", size = 3, write = Buffer.WriteColor3Bytes },
	{ name = "WriteUDim2", size = 16, write = Buffer.WriteUDim2 },
}

for _, entry in ipairs(WRITER_DATATYPES) do
	local size, write = entry.size, entry.write
	writerMeta[entry.name] = function(self: any, value: any): any
		writerReserve(self, size)
		write(self.blob, self.cursor, value)
		writerAdvance(self, size)
		return self
	end
end

function writerMeta.WritePacked(self: any, format: string, ...: any): any
	return writerMeta.WriteRaw(self, string.pack(format, ...))
end

function writerMeta.Pad(self: any, count: number): any
	local size = checkSize(count, "count", "Writer:Pad")
	writerReserve(self, size)
	buffer.fill(self.blob, self.cursor, 0, size)
	writerAdvance(self, size)
	return self
end

function writerMeta.Align(self: any, alignment: number): any
	local step = math.max(1, math.floor(alignment))
	local slack = (step - self.cursor % step) % step
	if slack > 0 then
		writerMeta.Pad(self, slack)
	end
	return self
end

function writerMeta.Seek(self: any, position: number): any
	local at = checkSize(position, "position", "Writer:Seek")
	if at > self.used then
		writerReserve(self, at - self.cursor)
		self.used = at
	end
	self.cursor = at
	return self
end

function writerMeta.Tell(self: any): number
	return self.cursor
end

function writerMeta.Length(self: any): number
	return self.used
end

function writerMeta.Capacity(self: any): number
	return buffer.len(self.blob)
end

function writerMeta.Reserve(self: any, extra: number): any
	writerReserve(self, checkSize(extra, "extra", "Writer:Reserve"))
	return self
end

function writerMeta.Reset(self: any): any
	self.cursor = 0
	self.used = 0
	return self
end

function writerMeta.Build(self: any): buffer
	local out = buffer.create(self.used)
	buffer.copy(out, 0, self.blob, 0, self.used)
	return out
end

function writerMeta.ToString(self: any): string
	return buffer.readstring(self.blob, 0, self.used)
end

-------------------------------------------------------------------- Reader

local readerMeta = {}
readerMeta.__index = readerMeta

function readerMeta.__len(self: any): number
	return buffer.len(self.blob)
end

function readerMeta.__tostring(self: any): string
	return ("Buffer.Reader(%d/%d bytes)"):format(self.cursor, buffer.len(self.blob))
end

local function readerTake(self: any, size: number, fname: string): number
	local at = self.cursor
	if at + size > buffer.len(self.blob) then
		error(
			("Buffer.Reader:%s: needs %d bytes at offset %d but only %d remain")
				:format(fname, size, at, buffer.len(self.blob) - at),
			3
		)
	end
	self.cursor = at + size
	return at
end

function Buffer.Reader(source: buffer | string): Reader
	local blob = if type(source) == "string" then buffer.fromstring(source) else source
	checkBuffer(blob, "source", "Reader")

	local self = setmetatable({
		blob = blob,
		cursor = 0,
	}, readerMeta)

	return self :: any
end

local READER_PRIMITIVES: { { name: string, size: number, read: (buffer, number) -> number } } = {
	{ name = "ReadU8", size = 1, read = buffer.readu8 },
	{ name = "ReadU16", size = 2, read = buffer.readu16 },
	{ name = "ReadU32", size = 4, read = buffer.readu32 },
	{ name = "ReadI8", size = 1, read = buffer.readi8 },
	{ name = "ReadI16", size = 2, read = buffer.readi16 },
	{ name = "ReadI32", size = 4, read = buffer.readi32 },
	{ name = "ReadF32", size = 4, read = buffer.readf32 },
	{ name = "ReadF64", size = 8, read = buffer.readf64 },
}

for _, entry in ipairs(READER_PRIMITIVES) do
	local name, size, read = entry.name, entry.size, entry.read
	readerMeta[name] = function(self: any): number
		return read(self.blob, readerTake(self, size, name))
	end
end

function readerMeta.ReadBool(self: any): boolean
	return buffer.readu8(self.blob, readerTake(self, 1, "ReadBool")) ~= 0
end

function readerMeta.ReadVarUInt(self: any): number
	local value, at = Buffer.ReadVarUInt(self.blob, self.cursor)
	self.cursor = at
	return value
end

function readerMeta.ReadVarInt(self: any): number
	local raw = readerMeta.ReadVarUInt(self)
	return if raw % 2 == 0 then raw // 2 else -((raw + 1) // 2)
end

function readerMeta.ReadRaw(self: any, count: number): string
	local size = checkSize(count, "count", "Reader:ReadRaw")
	return buffer.readstring(self.blob, readerTake(self, size, "ReadRaw"), size)
end

function readerMeta.ReadString(self: any): string
	return readerMeta.ReadRaw(self, readerMeta.ReadVarUInt(self))
end

function readerMeta.ReadBuffer(self: any, count: number): buffer
	local size = checkSize(count, "count", "Reader:ReadBuffer")
	local at = readerTake(self, size, "ReadBuffer")
	local out = buffer.create(size)
	buffer.copy(out, 0, self.blob, at, size)
	return out
end

local READER_DATATYPES: { { name: string, size: number, read: (buffer, number) -> (any, number) } } = {
	{ name = "ReadVector2", size = 8, read = Buffer.ReadVector2 },
	{ name = "ReadVector3", size = 12, read = Buffer.ReadVector3 },
	{ name = "ReadCFrame", size = 28, read = Buffer.ReadCFrame },
	{ name = "ReadColor3", size = 12, read = Buffer.ReadColor3 },
	{ name = "ReadColor3Bytes", size = 3, read = Buffer.ReadColor3Bytes },
	{ name = "ReadUDim2", size = 16, read = Buffer.ReadUDim2 },
}

for _, entry in ipairs(READER_DATATYPES) do
	local name, size, read = entry.name, entry.size, entry.read
	readerMeta[name] = function(self: any): any
		return (read(self.blob, readerTake(self, size, name)))
	end
end

function readerMeta.ReadPacked(self: any, format: string, size: number): ...any
	local count = checkSize(size, "size", "Reader:ReadPacked")
	local at = readerTake(self, count, "ReadPacked")
	local values = table.pack(string.unpack(format, buffer.readstring(self.blob, at, count)))
	return table.unpack(values, 1, values.n - 1)
end

function readerMeta.Skip(self: any, count: number): any
	readerTake(self, checkSize(count, "count", "Reader:Skip"), "Skip")
	return self
end

function readerMeta.Align(self: any, alignment: number): any
	local step = math.max(1, math.floor(alignment))
	local slack = (step - self.cursor % step) % step
	if slack > 0 then
		readerTake(self, slack, "Align")
	end
	return self
end

function readerMeta.Seek(self: any, position: number): any
	local at = checkSize(position, "position", "Reader:Seek")
	if at > buffer.len(self.blob) then
		error(("Buffer.Reader:Seek: %d is past the end of a %d byte buffer"):format(at, buffer.len(self.blob)), 2)
	end
	self.cursor = at
	return self
end

function readerMeta.Tell(self: any): number
	return self.cursor
end

function readerMeta.Remaining(self: any): number
	return buffer.len(self.blob) - self.cursor
end

function readerMeta.IsFinished(self: any): boolean
	return self.cursor >= buffer.len(self.blob)
end

function readerMeta.Reset(self: any): any
	self.cursor = 0
	return self
end

function readerMeta.Source(self: any): buffer
	return self.blob
end

-------------------------------------------------------------------- Pool

local poolMeta = {}
poolMeta.__index = poolMeta

function poolMeta.__tostring(self: any): string
	return ("Buffer.Pool(%d pooled, %d live)"):format(self.pooled, self.live)
end

function Buffer.Pool(maxPerClass: number?): Pool
	local self = setmetatable({
		classes = {} :: { [number]: { buffer } },
		maxPerClass = math.max(1, math.floor(maxPerClass or 32)),
		live = 0,
		pooled = 0,
		hits = 0,
		misses = 0,
	}, poolMeta)

	return self :: any
end

function poolMeta.Get(self: any, size: number): buffer
	local want = nextPowerOfTwo(checkSize(size, "size", "Pool:Get"))
	local stack = self.classes[want]

	self.live += 1

	if stack ~= nil and #stack > 0 then
		local block = table.remove(stack) :: buffer
		self.pooled -= 1
		self.hits += 1
		return block
	end

	self.misses += 1
	return buffer.create(want)
end

function poolMeta.Release(self: any, block: buffer): boolean
	checkBuffer(block, "block", "Pool:Release")

	local size = buffer.len(block)
	if size < MIN_POOL_CLASS or bit32.band(size, size - 1) ~= 0 then
		return false
	end

	self.live -= 1

	local stack = self.classes[size]
	if stack == nil then
		stack = {}
		self.classes[size] = stack
	end

	if #stack >= self.maxPerClass then
		return false
	end

	table.insert(stack, block)
	self.pooled += 1
	return true
end

function poolMeta.Preallocate(self: any, size: number, count: number): ()
	local want = nextPowerOfTwo(checkSize(size, "size", "Pool:Preallocate"))
	local stack = self.classes[want]

	if stack == nil then
		stack = {}
		self.classes[want] = stack
	end

	for _ = 1, checkSize(count, "count", "Pool:Preallocate") do
		if #stack >= self.maxPerClass then
			break
		end
		table.insert(stack, buffer.create(want))
		self.pooled += 1
	end
end

function poolMeta.Stats(self: any): PoolStats
	local classes: { [number]: number } = {}
	for size, stack in pairs(self.classes) do
		classes[size] = #stack
	end

	return {
		Live = self.live,
		Pooled = self.pooled,
		Hits = self.hits,
		Misses = self.misses,
		Classes = classes,
	}
end

function poolMeta.Clear(self: any): ()
	table.clear(self.classes)
	self.pooled = 0
end

-------------------------------------------------------------------- Arena

local arenaMeta = {}
arenaMeta.__index = arenaMeta

function arenaMeta.__tostring(self: any): string
	return ("Buffer.Arena(%d/%d bytes)"):format(self.cursor, buffer.len(self.blob))
end

function Buffer.Arena(capacity: number, growable: boolean?): Arena
	local self = setmetatable({
		blob = buffer.create(math.max(MIN_POOL_CLASS, checkSize(capacity, "capacity", "Arena"))),
		cursor = 0,
		growable = growable ~= false,
	}, arenaMeta)

	return self :: any
end

local function arenaPlace(self: any, size: number, alignment: number?): number?
	local step = math.max(1, math.floor(alignment or 1))
	local at = self.cursor + (step - self.cursor % step) % step
	local needed = at + size

	if needed > buffer.len(self.blob) then
		if not self.growable then
			return nil
		end

		local grown = buffer.create(math.max(needed, buffer.len(self.blob) * 2))
		buffer.copy(grown, 0, self.blob, 0, self.cursor)
		self.blob = grown
	end

	self.cursor = needed
	return at
end

function arenaMeta.Alloc(self: any, size: number, alignment: number?): number
	local at = arenaPlace(self, checkSize(size, "size", "Arena:Alloc"), alignment)

	if at == nil then
		error(
			("Buffer.Arena:Alloc: %d bytes will not fit — %d of %d already used and the arena is not growable")
				:format(size, self.cursor, buffer.len(self.blob)),
			2
		)
	end

	return at
end

function arenaMeta.TryAlloc(self: any, size: number, alignment: number?): number?
	return arenaPlace(self, checkSize(size, "size", "Arena:TryAlloc"), alignment)
end

function arenaMeta.Mark(self: any): number
	return self.cursor
end

function arenaMeta.Rewind(self: any, mark: number): ()
	local at = checkSize(mark, "mark", "Arena:Rewind")
	if at > self.cursor then
		error(("Buffer.Arena:Rewind: mark %d is ahead of the cursor at %d"):format(at, self.cursor), 2)
	end
	self.cursor = at
end

function arenaMeta.Reset(self: any): ()
	self.cursor = 0
end

function arenaMeta.Buffer(self: any): buffer
	return self.blob
end

function arenaMeta.Used(self: any): number
	return self.cursor
end

function arenaMeta.Capacity(self: any): number
	return buffer.len(self.blob)
end

function arenaMeta.Remaining(self: any): number
	return buffer.len(self.blob) - self.cursor
end

-------------------------------------------------------------------- Module wiring

export type BufferModule = typeof(Buffer) & typeof(buffer)

return (
	setmetatable(Buffer, {
		__index = buffer,
		__call = function(_, size: number): buffer
			return buffer.create(size)
		end,
		__metatable = "The Buffer metatable is locked",
	}) :: any
) :: BufferModule
