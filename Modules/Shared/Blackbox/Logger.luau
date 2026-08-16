--!strict

const RunService = game:GetService("RunService")

const Ambient = require(script.Parent.Ambient)
const Config = require(script.Parent.Config)
const Fault = require(script.Parent.Fault)
const Level = require(script.Parent.Level)
const Metrics = require(script.Parent.Metrics)
const Ring = require(script.Parent.Ring)
const Sinks = require(script.Parent.Sinks)
const Throttle = require(script.Parent.Throttle)
const Trace = require(script.Parent.Trace)
const Types = require(script.Parent.Types)

const State = Config.State
const CONTEXT:"Server" | "Client" = if RunService:IsServer() then "Server" else "Client"

const Logger = {}
Logger.__index = Logger

const Throttler = Throttle.new()
const Breadcrumbs = (Ring.new(State.BreadcrumbLimit)::any)::Ring.Ring<Types.Breadcrumb>
const History = Sinks.Memory(State.HistoryLimit, Level.TRACE)

const Registry:{[string]:any} = {}
const FatalHandlers:{(entry:Types.Entry) -> ()} = {}

const SinkFailures:{[Types.Sink]:number} = setmetatable({}, { __mode = "k" })::any
const SINK_FAILURE_LIMIT = 5

Logger.History = History
Logger.Breadcrumbs = Breadcrumbs
Logger.Throttler = Throttler
Logger.Registry = Registry

Config.OnChanged(function(state)
    Breadcrumbs:Resize(state.BreadcrumbLimit)
    History:Resize(state.HistoryLimit)
end)

const function effectiveLevel(self:any):number
    local node = self
    while node do
        if node.Level ~= nil then
            return node.Level
        end
        node = node._parent
    end
    return State.Level
end

const function mergeFields(self:any, fields:{[string]:any}?):{[string]:any}?
    const ambient = Ambient.Fields()
    const hasTags = next(State.Tags) ~= nil

    local chain:{any}? = nil
    local node = self
    while node do
        if node._fields then
            chain = chain or {}
            table.insert(chain::{any}, node._fields)
        end
        node = node._parent
    end

    if chain == nil and ambient == nil and fields == nil and not hasTags then
        return nil
    end

    const merged:{[string]:any} = {}

    for key, value in pairs(State.Tags) do
        merged[key] = value
    end
    if chain then
        for index = #chain, 1, -1 do
            for key, value in pairs(chain[index]) do
                merged[key] = value
            end
        end
    end
    if ambient then
        for key, value in pairs(ambient) do
            merged[key] = value
        end
    end
    if fields then
        for key, value in pairs(fields) do
            merged[key] = value
        end
    end

    return merged
end

const function collectSinks(self:any):{Types.Sink}
    const out:{Types.Sink} = {}
    const seen:{[Types.Sink]:boolean} = {}

    local node = self
    while node do
        for _, sink in ipairs(node._sinks::{Types.Sink}) do
            if not seen[sink] then
                seen[sink] = true
                table.insert(out, sink)
            end
        end
        node = node._parent
    end

    return out
end

const function writeSinks(self:any, entry:Types.Entry)
    for _, sink in ipairs(collectSinks(self)) do
        if not sink.Enabled or entry.Level < sink.Level then
            continue
        end
        const filter = sink.Filter
        if filter and not filter(sink, entry) then
            continue
        end

        const ok, err = pcall(sink.Write::any, sink, entry)
        if ok then
            SinkFailures[sink] = nil
        else
            const count = (SinkFailures[sink] or 0) + 1
            SinkFailures[sink] = count
            if count >= SINK_FAILURE_LIMIT then
                sink.Enabled = false
                warn(`[Blackbox] sink '{sink.Name}' failed {count} times in a row and has been disabled: {tostring(err)}`)
            end
        end
    end
end

const function runHooks(self:any, entry:Types.Entry):boolean
    local node = self
    while node do
        for _, hook in ipairs(node._hooks::{Types.Hook}) do
            const ok, verdict = pcall(hook, entry)
            if ok and verdict == false then
                return false
            end
        end
        node = node._parent
    end
    return true
end

const function onFatal(entry:Types.Entry)
    for _, sink in ipairs(collectSinks(Logger.Root)) do
        if sink.Flush then
            pcall(sink.Flush, sink)
        end
    end

    for _, handler in ipairs(FatalHandlers) do
        task.spawn(function()
            const ok, err = pcall(handler::any, entry)
            if not ok then
                warn(`[Blackbox] a fatal handler failed: {tostring(err)}`)
            end
        end)
    end
end

const function dispatch(self:any, level:number, message:string, fields:{[string]:any}?, fault:Types.Fault?, skip:number)
    if self._destroyed then
        return
    end
    if level < effectiveLevel(self) then
        return
    end

    const merged = mergeFields(self, fields)
    const frame = Ambient.Current()

    local trace:Types.Trace? = if fault then fault.Trace else nil
    if trace == nil and level >= State.TraceLevel then
        trace = Trace.Capture(2 + skip)
    end

    const entry:Types.Entry = {
        Level = level,
        LevelName = Level.NameOf(level),
        Logger = self.Name,
        Message = message,
        Fields = merged,
        Fault = fault,
        Trace = trace,
        Breadcrumbs = nil,
        Time = os.time(),
        Clock = os.clock(),
        Fingerprint = if fault then fault.Fingerprint else Trace.Fingerprint(message, trace, self.Name),
        TraceId = if frame then frame.TraceId else nil,
        SpanId = if frame then frame.SpanId else nil,
        Span = if frame then frame.Name else nil,
        Context = CONTEXT,
        Count = 1,
    }

    History:Write(entry)
    Metrics.Increment(`log.{entry.LevelName:lower()}`)

    if not runHooks(self, entry) then
        return
    end
    if not Throttler:Admit(entry) then
        return
    end

    if level >= State.BreadcrumbLevel and Breadcrumbs:Count() > 0 then
        entry.Breadcrumbs = Breadcrumbs:Snapshot()
    end

    writeSinks(self, entry)

    if level >= Level.FATAL then
        onFatal(entry)
    end
end

function Logger.Log(self:any, level:string | number, message:string, fields:{[string]:any}?)
    dispatch(self, Level.Expect(level, "Logger:Log"), tostring(message), fields, nil, 1)
end

function Logger.Trace(self:any, message:string, fields:{[string]:any}?)
    dispatch(self, Level.TRACE, tostring(message), fields, nil, 1)
end

function Logger.Debug(self:any, message:string, fields:{[string]:any}?)
    dispatch(self, Level.DEBUG, tostring(message), fields, nil, 1)
end

function Logger.Info(self:any, message:string, fields:{[string]:any}?)
    dispatch(self, Level.INFO, tostring(message), fields, nil, 1)
end

function Logger.Warn(self:any, message:string, fields:{[string]:any}?)
    dispatch(self, Level.WARN, tostring(message), fields, nil, 1)
end

function Logger.Error(self:any, message:string, fields:{[string]:any}?)
    dispatch(self, Level.ERROR, tostring(message), fields, nil, 1)
end

function Logger.Fatal(self:any, message:string, fields:{[string]:any}?)
    dispatch(self, Level.FATAL, tostring(message), fields, nil, 1)
end

function Logger.Exception(self:any, err:any, message:string?, fields:{[string]:any}?):Types.Fault
    const fault = Fault.Coerce(err, 1)
    const level = if fault.Retryable then Level.WARN else Level.ERROR
    dispatch(self, level, message or fault.Message, fields, fault, 1)
    return fault
end

function Logger.Ensure(self:any, condition:any, message:string, fields:{[string]:any}?):boolean
    if condition then
        return true
    end
    dispatch(self, Level.ERROR, message, fields, nil, 1)
    return false
end

function Logger.IsEnabled(self:any, level:string | number):boolean
    const resolved = Level.Resolve(level)
    if resolved then
        return resolved >= effectiveLevel(self)
    end
    return false
end

function Logger.EffectiveLevel(self:any):number
    return effectiveLevel(self)
end

function Logger.SetLevel(self:any, level:(string | number)?):any
    if level == nil then
        self.Level = nil
    else
        self.Level = Level.Expect(level, "Logger:SetLevel")
    end
    return self
end

const function build(name:string, parent:any?, fields:{[string]:any}?, registered:boolean):any
    const self = setmetatable({
        Name = name,
        Level = nil,
        _parent = parent,
        _fields = fields,
        _sinks = {},
        _hooks = {},
        _destroyed = false,
    }, Logger)

    if registered then
        Registry[name] = self
    end
    return self
end

function Logger.Child(self:any, name:string, fields:{[string]:any}?):any
    if type(name) ~= "string" or name == "" then
        error("Blackbox: a child logger needs a non-empty name", 2)
    end

    const full = if self.Name == "" then name else `{self.Name}.{name}`
    const existing = Registry[full]
    if existing and not existing._destroyed then
        if fields then
            existing._fields = existing._fields or {}
            for key, value in pairs(fields) do
                existing._fields[key] = value
            end
        end
        return existing
    end

    return build(full, self, fields, true)
end

function Logger.With(self:any, fields:{[string]:any}):any
    return build(self.Name, self, fields, false)
end

function Logger.AddSink(self:any, sink:Types.Sink):Types.Sink
    if type(sink) ~= "table" or type(sink.Write) ~= "function" then
        error("Blackbox: a sink needs a Write method", 2)
    end
    if sink.Level == nil then
        sink.Level = Level.TRACE
    end
    if sink.Enabled == nil then
        sink.Enabled = true
    end

    table.insert(self._sinks, sink)
    return sink
end

function Logger.RemoveSink(self:any, sink:Types.Sink | string):boolean
    for index, candidate in ipairs(self._sinks) do
        if candidate == sink or candidate.Name == sink then
            const removed = table.remove(self._sinks, index)
            if removed and removed.Close then
                pcall(removed.Close, removed)
            end
            return true
        end
    end
    return false
end

function Logger.Use(self:any, hook:Types.Hook):() -> ()
    table.insert(self._hooks, hook)
    return function()
        const index = table.find(self._hooks, hook)
        if index then
            table.remove(self._hooks, index)
        end
    end
end

function Logger.Breadcrumb(self:any, message:string, category:string?, fields:{[string]:any}?)
    Breadcrumbs:Push({
        Message = message,
        Category = category or self.Name,
        Fields = fields,
        Clock = os.clock(),
    })
end

const Span = {}
Span.__index = Span

function Span.Annotate(self:any, fields:{[string]:any})
    Ambient.Annotate(fields)
    for key, value in pairs(fields) do
        self._fields[key] = value
    end
end

function Span.Stop(self:any, fields:{[string]:any}?):number
    if self._stopped then
        return self._elapsed
    end
    self._stopped = true
    self._elapsed = self._watch:Stop()

    Ambient.Pop(self._frame)

    if fields then
        for key, value in pairs(fields) do
            self._fields[key] = value
        end
    end
    self._fields.ms = math.round(self._elapsed * 1000 * 100) / 100

    dispatch(self._logger, Level.DEBUG, `span '{self.Name}' finished`, self._fields, nil, 1)
    return self._elapsed
end

function Logger.Span(self:any, name:string, fields:{[string]:any}?):Types.SpanHandle
    const frame = Ambient.Push(name, fields)

    return (setmetatable({
        Id = frame.SpanId,
        Name = name,
        TraceId = frame.TraceId,
        _logger = self,
        _frame = frame,
        _fields = {},
        _watch = Metrics.Start(`span.{name}`),
        _stopped = false,
        _elapsed = 0,
    }, Span)::any)::Types.SpanHandle
end

function Logger.Scope(self:any, name:string, fn:(...any) -> ...any, ...:any):...any
    const span = Logger.Span(self, name)
    const results = table.pack(xpcall(fn, function(err:any):Types.Fault
        return Fault.Coerce(err, 1)
    end, ...))

    if results[1] then
        span:Stop({ ok = true })
        return table.unpack(results, 2, results.n)
    end

    const fault = results[2]::Types.Fault
    dispatch(self, Level.ERROR, `span '{name}' failed`, { ok = false }, fault, 1)
    span:Stop({ ok = false, fault = fault.Kind })
    fault:Throw()
    return
end

function Logger.Time(self:any, name:string, fn:(...any) -> ...any, ...:any):...any
    const watch = Metrics.Start(`time.{name}`)
    const results = table.pack(pcall(fn, ...))
    const elapsed = watch:Stop()

    if not results[1] then
        dispatch(self, Level.ERROR, `'{name}' failed after {math.round(elapsed * 1000)}ms`, nil,
            Fault.Coerce(results[2], 1), 1)
        error(results[2], 0)
    end

    dispatch(self, Level.DEBUG, `'{name}' took {math.round(elapsed * 1000 * 100) / 100}ms`, nil, nil, 1)
    return table.unpack(results, 2, results.n)
end

function Logger.Flush(self:any)
    for _, sink in ipairs(collectSinks(self)) do
        if sink.Flush then
            pcall(sink.Flush, sink)
        end
    end
end

function Logger.Destroy(self:any)
    if self._destroyed then
        return
    end
    self._destroyed = true

    for _, sink in ipairs(self._sinks::{Types.Sink}) do
        const close = sink.Close
        if close then
            pcall(close, sink)
        end
    end
    table.clear(self._sinks)
    table.clear(self._hooks)

    if Registry[self.Name] == self then
        Registry[self.Name] = nil
    end
end

Logger.Root = build("", nil, nil, true)

function Logger.Get(path:string?):any
    if path and path ~= "" then
        const existing = Registry[path]
        if existing and not existing._destroyed then
            return existing
        end

        local node = Logger.Root
        for segment in string.gmatch(path, "[^%.]+") do
            node = Logger.Child(node, segment)
        end
        return node
    end
    return Logger.Root
end

function Logger.OnFatal(handler:(entry:Types.Entry) -> ()):() -> ()
    table.insert(FatalHandlers, handler)
    return function()
        const index = table.find(FatalHandlers, handler)
        if index then
            table.remove(FatalHandlers, index)
        end
    end
end

return Logger
