--!strict

const Level = require(script.Parent.Level)
const Types = require(script.Parent.Types)

const Console = require(script.Console)
const Memory = require(script.Memory)

const Sinks = {}

Sinks.ConsoleModule = Console
Sinks.MemoryModule = Memory

export type MemorySink = Memory.MemorySink
export type Query = Memory.Query
export type Frequency = Memory.Frequency

function Sinks.Console(options:Types.ConsoleOptions?):Types.Sink
    return Console.new(options)
end

function Sinks.Memory(capacity:number?, level:(string | number)?):MemorySink
    return Memory.new(capacity, level)
end

function Sinks.Callback(name:string, callback:(entry:Types.Entry) -> (), level:(string | number)?):Types.Sink
    return {
        Name = name,
        Level = Level.Resolve(level) or Level.TRACE,
        Enabled = true,
        Write = function(_self, entry)
            callback(entry)
        end,
    }::any
end

function Sinks.Filtered(sink:Types.Sink, predicate:(entry:Types.Entry) -> boolean):Types.Sink
    return {
        Name = `{sink.Name}:filtered`,
        Level = sink.Level,
        Enabled = sink.Enabled,
        Filter = function(_self, entry)
            return predicate(entry)
        end,
        Write = function(_self, entry)
            sink:Write(entry)
        end,
        Flush = function(_self)
            const flush = sink.Flush
            if flush then
                flush(sink)
            end
        end,
        Close = function(_self)
            const close = sink.Close
            if close then
                close(sink)
            end
        end,
    }::any
end

return Sinks
