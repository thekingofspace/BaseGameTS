--!strict

const Ring = {}
Ring.__index = Ring

export type Ring<T> = {
    Capacity:number,
    Push:(self:Ring<T>, value:T) -> (),
    Snapshot:(self:Ring<T>, limit:number?) -> {T},
    Recent:(self:Ring<T>, limit:number?) -> {T},
    Count:(self:Ring<T>) -> number,
    Dropped:(self:Ring<T>) -> number,
    Clear:(self:Ring<T>) -> (),
    Resize:(self:Ring<T>, capacity:number) -> (),
    Each:(self:Ring<T>, visit:(value:T, index:number) -> boolean?) -> (),
}

type RingObject = {
    Capacity:number,
    _items:{any},
    _head:number,
    _size:number,
    _dropped:number,
}

function Ring.new<T>(capacity:number):Ring<T>
    if type(capacity) ~= "number" or capacity < 1 then
        error("Blackbox: a ring needs a capacity of at least 1", 2)
    end

    const self = setmetatable({
        Capacity = math.floor(capacity),
        _items = table.create(math.floor(capacity)),
        _head = 1,
        _size = 0,
        _dropped = 0,
    }, Ring)

    return (self::any)::Ring<T>
end

function Ring.Push(self:RingObject, value:any)
    if self._size == self.Capacity then
        self._dropped += 1
    else
        self._size += 1
    end

    self._items[self._head] = value
    self._head += 1
    if self._head > self.Capacity then
        self._head = 1
    end
end

const function tail(self:RingObject):number
    if self._size < self.Capacity then
        return 1
    end
    return self._head
end

function Ring.Snapshot(self:RingObject, limit:number?):{any}
    const wanted = math.min(limit or self._size, self._size)
    const out = table.create(wanted)
    if wanted == 0 then
        return out
    end

    local index = (tail(self) + (self._size - wanted) - 1) % self.Capacity + 1
    for _ = 1, wanted do
        table.insert(out, self._items[index])
        index += 1
        if index > self.Capacity then
            index = 1
        end
    end

    return out
end

function Ring.Recent(self:RingObject, limit:number?):{any}
    const ordered = Ring.Snapshot(self, limit)
    const out = table.create(#ordered)
    for index = #ordered, 1, -1 do
        table.insert(out, ordered[index])
    end
    return out
end

function Ring.Each(self:RingObject, visit:(value:any, index:number) -> boolean?)
    if self._size == 0 then
        return
    end

    local index = tail(self)
    for position = 1, self._size do
        if visit(self._items[index], position) == false then
            return
        end
        index += 1
        if index > self.Capacity then
            index = 1
        end
    end
end

function Ring.Count(self:RingObject):number
    return self._size
end

function Ring.Dropped(self:RingObject):number
    return self._dropped
end

function Ring.Clear(self:RingObject)
    table.clear(self._items)
    self._head = 1
    self._size = 0
    self._dropped = 0
end

function Ring.Resize(self:RingObject, capacity:number)
    if type(capacity) ~= "number" or capacity < 1 then
        error("Blackbox: a ring needs a capacity of at least 1", 2)
    end

    const target = math.floor(capacity)
    if target == self.Capacity then
        return
    end

    const kept = Ring.Snapshot(self, target)
    const dropped = self._dropped + math.max(0, self._size - target)

    self.Capacity = target
    self._items = table.create(target)
    self._head = 1
    self._size = 0
    self._dropped = 0

    for _, value in ipairs(kept) do
        Ring.Push(self, value)
    end
    self._dropped = dropped
end

return Ring
