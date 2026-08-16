--!strict

const LogService = game:GetService("LogService")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")
const ScriptContext = game:GetService("ScriptContext")
const Stats = game:GetService("Stats")

const Ambient = require(script.Parent.Ambient)
const Config = require(script.Parent.Config)
const Fault = require(script.Parent.Fault)
const Level = require(script.Parent.Level)
const Logger = require(script.Parent.Logger)
const Metrics = require(script.Parent.Metrics)
const Serialize = require(script.Parent.Serialize)
const Sinks = require(script.Parent.Sinks)
const Trace = require(script.Parent.Trace)
const Types = require(script.Parent.Types)

const State = Config.State
const IS_SERVER = RunService:IsServer()
const STARTED = os.clock()

const Guard = {}

local handling = false

const Connections:{RBXScriptConnection} = {}
local installed = false

export type Snapshot = {
    Context:string,
    PlaceId:number,
    PlaceVersion:number,
    JobId:string,
    Uptime:number,
    Players:number,
    MemoryMb:number?,
    Fps:number?,
}

function Guard.Snapshot():Snapshot
    const snapshot:Snapshot = {
        Context = if IS_SERVER then "Server" else "Client",
        PlaceId = game.PlaceId,
        PlaceVersion = game.PlaceVersion,
        JobId = game.JobId,
        Uptime = os.clock() - STARTED,
        Players = #Players:GetPlayers(),
    }

    pcall(function()
        snapshot.MemoryMb = Stats:GetTotalMemoryUsageMb()
    end)
    pcall(function()
        snapshot.Fps = math.round(workspace:GetRealPhysicsFPS())
    end)

    return snapshot
end

export type DumpOptions = {
    Entries:number?,
    Level:(string | number)?,
    Metrics:boolean?,
}

function Guard.Dump(options:DumpOptions?):string
    const settings:DumpOptions = options or {}
    const snapshot = Guard.Snapshot()

    const lines = {
        "──────────────── Blackbox flight recorder ────────────────",
        string.format(
            "%s | place %d v%d | job %s | up %.1fs | %d players%s",
            snapshot.Context, snapshot.PlaceId, snapshot.PlaceVersion,
            if snapshot.JobId ~= "" then snapshot.JobId else "<studio>",
            snapshot.Uptime, snapshot.Players,
            if snapshot.MemoryMb then string.format(" | %.1f MB", snapshot.MemoryMb) else ""
        ),
    }

    const path = Ambient.Path()
    if path then
        table.insert(lines, `open spans: {path}`)
    end

    const top = Logger.History:Top(5)
    if #top > 0 then
        table.insert(lines, "")
        table.insert(lines, "most frequent:")
        for _, row in ipairs(top) do
            table.insert(lines, `  x{row.Count} [{row.Level}] {row.Message}`)
        end
    end

    if settings.Metrics ~= false then
        table.insert(lines, "")
        table.insert(lines, Metrics.Format())
    end

    table.insert(lines, "")
    table.insert(lines, `recent entries (newest last):`)
    table.insert(lines, Logger.History:Dump({
        Limit = settings.Entries or 40,
        Level = settings.Level,
    }))
    table.insert(lines, "──────────────────────────────────────────────────────────")

    return table.concat(lines, "\n")
end

const function onScriptError(log:any, message:string, stack:string, source:Instance?)
    if handling then
        return
    end
    handling = true

    const trace = Trace.FromTraceback(stack)
    const fault = Fault.Coerce(message, 0, "Unhandled");
    (fault::any).Trace = trace;
    (fault::any).Fingerprint = Trace.Fingerprint(fault.Message, trace, "Unhandled")

    if source then
        fault:Detail("Script", source:GetFullName())
    end

    log:Exception(fault, `unhandled error: {fault.Message}`)
    Metrics.Increment("errors.unhandled")

    handling = false
end

const function onOutput(log:any, message:string, kind:Enum.MessageType)
    if handling or Sinks.ConsoleModule.Emitting then
        return
    end
    if Sinks.ConsoleModule.WasEmitted(message) then
        return
    end
    if kind == Enum.MessageType.MessageError then
        return
    end

    const level = if kind == Enum.MessageType.MessageWarning then Level.WARN else Level.DEBUG
    log:Log(level, message, { via = "output" })
end

function Guard.Install(logger:Types.Logger?):boolean
    if installed then
        return false
    end
    installed = true

    const log = (logger or Logger.Get("Engine"))::any

    if State.CaptureGlobalErrors then
        table.insert(Connections, ScriptContext.Error:Connect(function(message:string, stack:string, source:Instance?)
            onScriptError(log, message, stack, source)
        end))
    end

    if State.CaptureOutput then
        table.insert(Connections, LogService.MessageOut:Connect(function(message:string, kind:Enum.MessageType)
            onOutput(log, message, kind)
        end))
    end

    Logger.OnFatal(function(_entry:Types.Entry)
        warn(Guard.Dump())
    end)

    return true
end

function Guard.Uninstall()
    for _, connection in ipairs(Connections) do
        connection:Disconnect()
    end
    table.clear(Connections)
    installed = false
end

const function guarded(log:any, label:string, fn:(...any) -> ...any, captured:any, ...:any)
    Ambient.Adopt(captured)

    const results = table.pack(xpcall(fn, function(err:any):Types.Fault
        return Fault.Coerce(err, 1, "Unhandled")
    end, ...))

    if not results[1] then
        log:Exception(results[2], `{label} failed`)
        Metrics.Increment("errors.unhandled")
    end

    Ambient.Clear()
    return table.unpack(results, 2, results.n)
end

function Guard.Spawn(fn:(...any) -> ...any, ...:any):thread
    const captured = Ambient.Capture()
    const log = Logger.Get("Engine")
    return task.spawn(guarded, log, "spawned thread", fn, captured, ...)
end

function Guard.Defer(fn:(...any) -> ...any, ...:any):thread
    const captured = Ambient.Capture()
    const log = Logger.Get("Engine")
    return task.defer(guarded, log, "deferred thread", fn, captured, ...)
end

function Guard.Delay(seconds:number, fn:(...any) -> ...any, ...:any):thread
    const captured = Ambient.Capture()
    const log = Logger.Get("Engine")
    return task.delay(seconds, guarded, log, "delayed thread", fn, captured, ...)
end

function Guard.Connect(signal:RBXScriptSignal, fn:(...any) -> ...any, name:string?):RBXScriptConnection
    const log = Logger.Get("Engine")
    const label = name or "signal handler"

    return signal:Connect(function(...)
        const results = table.pack(xpcall(fn, function(err:any):Types.Fault
            return Fault.Coerce(err, 1, "Unhandled")
        end, ...))

        if not results[1] then
            log:Exception(results[2], `{label} failed`)
            Metrics.Increment("errors.unhandled")
        end
    end)
end

function Guard.Wrap<A..., R...>(fn:(A...) -> R..., name:string?):(A...) -> ()
    const log = Logger.Get("Engine")
    const label = name or "wrapped call"

    return function(...:any)
        const ok, err = xpcall(fn::any, function(raised:any):Types.Fault
            return Fault.Coerce(raised, 1)
        end, ...)
        if not ok then
            log:Exception(err, `{label} failed`)
        end
    end
end

function Guard.BindToClose(logger:Types.Logger?)
    if not IS_SERVER then
        return
    end

    const log = (logger or Logger.Get("Engine"))::any

    game:BindToClose(function()
        const suppressed = Logger.Throttler:Suppressed()
        log:Info("server closing", {
            uptime = math.round(os.clock() - STARTED),
            entries = Logger.History:Count(),
            suppressed = suppressed,
        })
        log:Flush()
    end)
end

function Guard.Status():string
    const snapshot = Guard.Snapshot()
    return Serialize.Fields({
        context = snapshot.Context,
        uptime = math.round(snapshot.Uptime),
        players = snapshot.Players,
        memoryMb = if snapshot.MemoryMb then math.round(snapshot.MemoryMb) else nil,
        entries = Logger.History:Count(),
        suppressed = Logger.Throttler:Suppressed(),
        errors = Metrics.Counter("log.error") + Metrics.Counter("log.fatal"),
        level = Level.NameOf(State.Level),
    })
end

return Guard
