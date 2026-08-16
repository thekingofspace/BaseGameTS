--!strict

local Wire = {}

Wire.PUSH = 0
Wire.CALL = 1
Wire.RESPOND = 2
Wire.AUTH = 3

local FLAG_PROMISE = 0b0000_0100
local FLAG_ARGS = 0b0000_1000
local FLAG_NILS = 0b0001_0000
local FLAG_NIL_LIST = 0b0010_0000

local MAX_ARGUMENTS = 255
local MAX_EVENT = 255

local function maskBytes(count: number): number
	return math.ceil(count / 8)
end

function Wire.pack(
	kind: number,
	event: string,
	promiseId: number?,
	args: { any }?,
	count: number?
): (buffer, { any })
	local total = count or 0
	if total > MAX_ARGUMENTS then
		error("ERR_TOO_MANY_ARGUMENTS | A single message carries at most 255 arguments.", 0)
	end
	if #event > MAX_EVENT then
		error("ERR_EVENT_TOO_LONG | An event name carries at most 255 bytes.", 0)
	end

	local values: { any } = table.create(total)
	local holes = 0

	for index = 1, total do
		local value = if args then args[index] else nil
		if value == nil then
			holes += 1
			values[index] = false
		else
			values[index] = value
		end
	end

	local useList = holes > 0 and holes < maskBytes(total)
	local nilBytes = 0
	if holes > 0 then
		nilBytes = if useList then holes else maskBytes(total)
	end

	local flags = bit32.band(kind, 0b11)
	if promiseId then
		flags = bit32.bor(flags, FLAG_PROMISE)
	end
	if total > 0 then
		flags = bit32.bor(flags, FLAG_ARGS)
	end
	if holes > 0 then
		flags = bit32.bor(flags, FLAG_NILS)
	end
	if useList then
		flags = bit32.bor(flags, FLAG_NIL_LIST)
	end

	local size = 1 + 1 + #event + nilBytes
	if promiseId then
		size += 2
	end

	local meta = buffer.create(size)
	local at = 0

	buffer.writeu8(meta, at, flags)
	at += 1

	buffer.writeu8(meta, at, #event)
	at += 1

	if promiseId then
		buffer.writeu16(meta, at, promiseId)
		at += 2
	end

	if holes > 0 then
		local base = at

		if useList then
			local cursor = base
			for index = 1, total do
				local value = if args then args[index] else nil
				if value == nil then
					buffer.writeu8(meta, cursor, index)
					cursor += 1
				end
			end
		else
			for offset = 0, nilBytes - 1 do
				buffer.writeu8(meta, base + offset, 0)
			end
			for index = 1, total do
				local value = if args then args[index] else nil
				if value == nil then
					local byte = base + math.floor((index - 1) / 8)
					local bit = (index - 1) % 8
					buffer.writeu8(meta, byte, bit32.bor(buffer.readu8(meta, byte), bit32.lshift(1, bit)))
				end
			end
		end

		at += nilBytes
	end

	if #event > 0 then
		buffer.writestring(meta, at, event)
	end

	return meta, values
end

function Wire.unpack(meta: buffer, values: { any }?): (number, string, number?, { any }, number)
	if typeof(meta) ~= "buffer" or buffer.len(meta) < 2 then
		return Wire.PUSH, "", nil, {}, 0
	end

	local at = 0

	local flags = buffer.readu8(meta, at)
	at += 1

	local kind = bit32.band(flags, 0b11)

	local eventLen = buffer.readu8(meta, at)
	at += 1

	local promiseId: number? = nil
	if bit32.band(flags, FLAG_PROMISE) ~= 0 then
		promiseId = buffer.readu16(meta, at)
		at += 2
	end

	local hasArgs = bit32.band(flags, FLAG_ARGS) ~= 0
	local hasNils = bit32.band(flags, FLAG_NILS) ~= 0
	local asList = bit32.band(flags, FLAG_NIL_LIST) ~= 0

	local count = if hasArgs and values then #values else 0

	local base = at
	local listed = 0
	if hasNils then
		if asList then
			listed = buffer.len(meta) - at - eventLen
			at += listed
		else
			at += maskBytes(count)
		end
	end

	local event = if eventLen > 0 then buffer.readstring(meta, at, eventLen) else ""

	local args: { any } = table.create(count)
	if values then
		if not hasNils then
			for index = 1, count do
				args[index] = values[index]
			end
		elseif asList then
			local blank: { [number]: boolean } = {}
			for offset = 0, listed - 1 do
				blank[buffer.readu8(meta, base + offset)] = true
			end
			for index = 1, count do
				if not blank[index] then
					args[index] = values[index]
				end
			end
		else
			for index = 1, count do
				local byte = base + math.floor((index - 1) / 8)
				local bit = (index - 1) % 8
				if bit32.band(buffer.readu8(meta, byte), bit32.lshift(1, bit)) == 0 then
					args[index] = values[index]
				end
			end
		end
	end

	return kind, event, promiseId, args, count
end

return Wire
