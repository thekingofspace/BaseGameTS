const module = {}

export type DebounceCategory = {
    Check:(self:DebounceCategory, ...any) -> boolean,
    Clear:(self:DebounceCategory, ...any) -> (),
    Set:(self:DebounceCategory, number, ...any) -> (),
    Destroy:(self:DebounceCategory) -> (),
}

export type Debounce = {
    Create:(self:Debounce) -> DebounceCategory,
    Destroy:(self:Debounce) -> ()
}

const function now(): number
    return os.clock()
end

const function mixByte(hash:number, byte:number): number
    hash = bit32.band(hash + byte, 0xFFFFFFFF)
    hash = bit32.band(hash + bit32.lshift(hash, 10), 0xFFFFFFFF)
    return bit32.bxor(hash, bit32.rshift(hash, 6))
end

const function avalanche(hash:number): number
    hash = bit32.band(hash + bit32.lshift(hash, 3), 0xFFFFFFFF)
    hash = bit32.bxor(hash, bit32.rshift(hash, 11))
    return bit32.band(hash + bit32.lshift(hash, 15), 0xFFFFFFFF)
end

const SEED_A = 0x9E3779B9
const SEED_B = 0x85EBCA6B

const TAG_INSTANCE = 1
const TAG_STRING = 2
const TAG_NUMBER = 3
const TAG_BOOLEAN = 4
const TAG_NIL = 5
const TAG_OTHER = 6

const function feed(a:number, b:number, byte:number): (number, number)
    return mixByte(a, byte), mixByte(b, byte + 131)
end

const function feedString(a:number, b:number, text:string): (number, number)
    a, b = feed(a, b, bit32.band(#text, 0xFF))

    for index = 1, #text do
        a, b = feed(a, b, string.byte(text, index))
    end

    return a, b
end

type Feeder = (a:number, b:number, value:any) -> (number, number)

const function feedOther(a:number, b:number, value:any): (number, number)
    a, b = feed(a, b, TAG_OTHER)
    a, b = feedString(a, b, typeof(value))
    return feedString(a, b, tostring(value))
end

const FEEDERS: {[string]:Feeder} = {
    Instance = function(a, b, value)
        a, b = feed(a, b, TAG_INSTANCE)
        a, b = feedString(a, b, value.ClassName)
        return feedString(a, b, value.Name)
    end,

    string = function(a, b, value)
        a, b = feed(a, b, TAG_STRING)
        return feedString(a, b, value)
    end,

    number = function(a, b, value)
        a, b = feed(a, b, TAG_NUMBER)
        return feedString(a, b, string.pack("<d", value))
    end,

    boolean = function(a, b, value)
        a, b = feed(a, b, TAG_BOOLEAN)
        return feed(a, b, value and 1 or 0)
    end,

    ["nil"] = function(a, b)
        return feed(a, b, TAG_NIL)
    end,
}

const function feedValue(a:number, b:number, value:any): (number, number)
    local feeder = FEEDERS[typeof(value)] or feedOther
    return feeder(a, b, value)
end

const function hashKey(...:any): number
    local a, b = SEED_A, SEED_B

    for index = 1, select("#", ...) do
        a, b = feedValue(a, b, (select(index, ...)))
    end

    return avalanche(a) * 0x100000 + bit32.band(avalanche(b), 0xFFFFF)
end

const category_meta = {}
category_meta.__index = category_meta

function category_meta:Check(...:any): boolean
    assert(not self.destroyed, "cannot use a destroyed DebounceCategory")

    local key = hashKey(...)
    local readyAt = self.entries[key]

    if readyAt == nil then
        return true
    end

    if now() >= readyAt then
        self.entries[key] = nil
        return true
    end

    return false
end

function category_meta:Set(duration:number, ...:any)
    assert(not self.destroyed, "cannot use a destroyed DebounceCategory")

    if typeof(duration) ~= "number" then
        error("duration must be a number, got " .. typeof(duration), 2)
    end

    local key = hashKey(...)

    if duration <= 0 then
        self.entries[key] = nil
        return
    end

    self.entries[key] = now() + duration
end

function category_meta:Clear(...:any)
    assert(not self.destroyed, "cannot use a destroyed DebounceCategory")

    if select("#", ...) == 0 then
        table.clear(self.entries)
        return
    end

    self.entries[hashKey(...)] = nil
end

function category_meta:Destroy()
    if self.destroyed then
        return
    end

    self.destroyed = true
    table.clear(self.entries)

    const owner = self.owner

    if owner then
        const index = table.find(owner.categories, self)

        if index then
            table.remove(owner.categories, index)
        end

        self.owner = nil
    end
end

local debounce_meta = {}
debounce_meta.__index = debounce_meta

function debounce_meta:Create(): DebounceCategory
    assert(not self.destroyed, "cannot create a category on a destroyed Debounce")

    local category = setmetatable({
        entries = {},
        destroyed = false,
        owner = self
    }, category_meta)

    table.insert(self.categories, category)

    return category :: any
end

function debounce_meta:Destroy()
    if self.destroyed then
        return
    end

    self.destroyed = true

    for _, category in ipairs(self.categories) do
        category.destroyed = true
        category.owner = nil
        table.clear(category.entries)
    end

    table.clear(self.categories)
end

function module.new(): Debounce
    local self = setmetatable({
        categories = {},
        destroyed = false
    }, debounce_meta)

    return self :: any
end

return module
