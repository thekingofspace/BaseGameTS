--!strict

const Ambient = require(script.Ambient)
const Config = require(script.Config)
const Faults = require(script.Fault)
const Level = require(script.Level)
const LoggerModule = require(script.Logger)
const Metrics = require(script.Metrics)
const Ring = require(script.Ring)
const Serialize = require(script.Serialize)
const SinkRegistry = require(script.Sinks)
const Stack = require(script.Trace)
const Types = require(script.Types)
const Guard = require(script.Guard)

export type Logger = Types.Logger
export type Entry = Types.Entry
export type Fault = Types.Fault
export type Sink = Types.Sink
export type Hook = Types.Hook
export type SpanHandle = Types.SpanHandle
export type Breadcrumb = Types.Breadcrumb
export type Config = Types.Config
export type Attempt = Faults.Attempt
export type RetryOptions = Faults.RetryOptions
export type MemorySink = SinkRegistry.MemorySink
export type Query = SinkRegistry.Query

const Blackbox = {}

Blackbox.Level = Level
Blackbox.Sinks = SinkRegistry
Blackbox.Metrics = Metrics
Blackbox.Serialize = Serialize
Blackbox.Stack = Stack
Blackbox.Ambient = Ambient
Blackbox.Guard = Guard
Blackbox.Ring = Ring
Blackbox.Faults = Faults

Blackbox.History = LoggerModule.History
Blackbox.Root = LoggerModule.Root::Types.Logger

function Blackbox.Get(path:string?):Types.Logger
    return LoggerModule.Get(path)
end

function Blackbox.Configure(options:Types.Config)
    Config.Configure(options)
end

function Blackbox.SetLevel(level:string | number)
    Config.Configure({ Level = level })
end

function Blackbox.EffectiveLevel():number
    return Config.State.Level
end

function Blackbox.Trace(message:string, fields:{[string]:any}?)
    Blackbox.Root:Trace(message, fields)
end

function Blackbox.Debug(message:string, fields:{[string]:any}?)
    Blackbox.Root:Debug(message, fields)
end

function Blackbox.Info(message:string, fields:{[string]:any}?)
    Blackbox.Root:Info(message, fields)
end

function Blackbox.Warn(message:string, fields:{[string]:any}?)
    Blackbox.Root:Warn(message, fields)
end

function Blackbox.Error(message:string, fields:{[string]:any}?)
    Blackbox.Root:Error(message, fields)
end

function Blackbox.Fatal(message:string, fields:{[string]:any}?)
    Blackbox.Root:Fatal(message, fields)
end

function Blackbox.Exception(err:any, message:string?, fields:{[string]:any}?):Types.Fault
    return Blackbox.Root:Exception(err, message, fields)
end

function Blackbox.Breadcrumb(message:string, category:string?, fields:{[string]:any}?)
    Blackbox.Root:Breadcrumb(message, category, fields)
end

function Blackbox.Span(name:string, fields:{[string]:any}?):Types.SpanHandle
    return Blackbox.Root:Span(name, fields)
end

function Blackbox.Scope(name:string, fn:(...any) -> ...any, ...:any):...any
    return Blackbox.Root:Scope(name, fn, ...)
end

function Blackbox.Fault(kind:string, message:string?, details:{[string]:any}?):Types.Fault
    return Faults.new(kind, message, details, 1)
end

Blackbox.Throw = Faults.Throw
Blackbox.Coerce = Faults.Coerce
Blackbox.IsFault = Faults.IsFault

Blackbox.Try = Faults.Try
Blackbox.Retry = Faults.Retry
Blackbox.Assert = Faults.Assert
Blackbox.Expect = Faults.Expect
Blackbox.Protect = Faults.Protect

Blackbox.Spawn = Guard.Spawn
Blackbox.Defer = Guard.Defer
Blackbox.Delay = Guard.Delay
Blackbox.Connect = Guard.Connect
Blackbox.Wrap = Guard.Wrap

function Blackbox.Query(query:SinkRegistry.Query?):{Types.Entry}
    return LoggerModule.History:Query(query)
end

function Blackbox.Top(limit:number?)
    return LoggerModule.History:Top(limit)
end

function Blackbox.Dump(options:Guard.DumpOptions?):string
    return Guard.Dump(options)
end

function Blackbox.Status():string
    return Guard.Status()
end

function Blackbox.Snapshot():Guard.Snapshot
    return Guard.Snapshot()
end

function Blackbox.Flush()
    Blackbox.Root:Flush()
end

Blackbox.OnFatal = LoggerModule.OnFatal

function Blackbox.Clear()
    LoggerModule.History:Clear()
    LoggerModule.Breadcrumbs:Clear()
    LoggerModule.Throttler:Reset()
end

local started = false

export type StartOptions = Types.Config & {
    Sinks:{Types.Sink}?,
    NoConsole:boolean?,
    NoGuard:boolean?,
    NoBindToClose:boolean?,
}

function Blackbox.Start(options:StartOptions?):Types.Logger
    const settings:StartOptions = options or {}

    if next(settings::any) ~= nil then
        Config.Configure(settings::Types.Config)
    end

    if started then
        return Blackbox.Root
    end
    started = true

    if not settings.NoConsole then
        Blackbox.Root:AddSink(SinkRegistry.Console(settings.Console))
    end
    if settings.Sinks then
        for _, sink in ipairs(settings.Sinks) do
            Blackbox.Root:AddSink(sink)
        end
    end

    if not settings.NoGuard then
        Guard.Install(Blackbox.Get("Engine"))
    end
    if not settings.NoBindToClose then
        Guard.BindToClose(Blackbox.Get("Engine"))
    end

    return Blackbox.Root
end

Blackbox.Start()

return Blackbox
