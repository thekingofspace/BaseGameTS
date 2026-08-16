--!strict

const Level = require(script.Parent.Parent.Level)
const Ring = require(script.Parent.Parent.Ring)
const Types = require(script.Parent.Parent.Types)
const Console = require(script.Parent.Console)

const Memory = {}
Memory.__index = Memory

export type Query = {
    Level:(string | number)?,
    Logger:string?,
    Text:string?,
    Fingerprint:string?,
    TraceId:string?,
    Since:number?,
    Limit:number?,
}

export type Frequency = {
    Fingerprint:string,
    Count:number,
    Message:string,
    Level:string,
}

type Tally = {
    Count:number,
    Message:string,
    Level:string,
}

export type MemorySink = Types.Sink & {
    Query:(self:MemorySink, query:Query?) -> {Types.Entry},
    All:(self:MemorySink) -> {Types.Entry},
    Top:(self:MemorySink, limit:number?) -> {Frequency},
    Dump:(self:MemorySink, query:Query?) -> string,
    Clear:(self:MemorySink) -> (),
    Count:(self:MemorySink) -> number,
    Resize:(self:MemorySink, capacity:number) -> (),
}

const function matches(entry:Types.Entry, query:Query, floor:number?):boolean
    if floor and entry.Level < floor then
        return false
    end
    if query.Logger and string.sub(entry.Logger, 1, #query.Logger) ~= query.Logger then
        return false
    end
    if query.Fingerprint and entry.Fingerprint ~= query.Fingerprint then
        return false
    end
    if query.TraceId and entry.TraceId ~= query.TraceId then
        return false
    end
    if query.Since and entry.Time < query.Since then
        return false
    end
    if query.Text then
        if not string.find(entry.Message:lower(), query.Text:lower(), 1, true) then
            return false
        end
    end
    return true
end

function Memory.Write(self:any, entry:Types.Entry)
    self._ring:Push(entry)

    const seen = self._counts[entry.Fingerprint]
    if seen then
        seen.Count += 1
    else
        self._counts[entry.Fingerprint] = {
            Count = 1,
            Message = entry.Message,
            Level = entry.LevelName,
        }
    end
end

function Memory.Query(self:any, query:Query?):{Types.Entry}
    const filter:Query = query or {}
    const floor = Level.Resolve(filter.Level)
    const limit = filter.Limit or 100

    const out:{Types.Entry} = {}
    for _, entry in ipairs(self._ring:Recent()) do
        if #out >= limit then
            break
        end
        if matches(entry, filter, floor) then
            table.insert(out, entry)
        end
    end

    return out
end

function Memory.All(self:any):{Types.Entry}
    return self._ring:Snapshot()
end

function Memory.Top(self:any, limit:number?):{Frequency}
    const out:{Frequency} = {}
    for fingerprint, record in pairs(self._counts::{[string]:Tally}) do
        table.insert(out, {
            Fingerprint = fingerprint,
            Count = record.Count,
            Message = record.Message,
            Level = record.Level,
        })
    end

    table.sort(out, function(a:Frequency, b:Frequency)
        if a.Count == b.Count then
            return a.Message < b.Message
        end
        return a.Count > b.Count
    end)

    const capped = limit or 10
    while #out > capped do
        table.remove(out)
    end
    return out
end

function Memory.Dump(self:any, query:Query?):string
    const entries = Memory.Query(self, query)
    if #entries == 0 then
        return "<no matching entries>"
    end

    const lines:{string} = {}
    for index = #entries, 1, -1 do
        table.insert(lines, Console.Render(entries[index]))
    end
    return table.concat(lines, "\n")
end

function Memory.Count(self:any):number
    return self._ring:Count()
end

function Memory.Clear(self:any)
    self._ring:Clear()
    table.clear(self._counts)
end

function Memory.Resize(self:any, capacity:number)
    self._ring:Resize(capacity)
end

function Memory.new(capacity:number?, level:(string | number)?):MemorySink
    const self = setmetatable({
        Name = "Memory",
        Level = Level.Resolve(level) or Level.TRACE,
        Enabled = true,
        _ring = Ring.new(capacity or 512),
        _counts = {},
    }, Memory)

    return (self::any)::MemorySink
end

return Memory
