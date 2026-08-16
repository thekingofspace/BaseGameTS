--!strict

const Trace = require(script.Parent.Trace)
const Serialize = require(script.Parent.Serialize)
const Types = require(script.Parent.Types)

const FAULT_TAG = "Blackbox.Fault"

const Faults = {}

const FaultMeta = {}
FaultMeta.__index = FaultMeta

function FaultMeta.__tostring(self:any):string
    return `{self.Kind}: {self.Message}`
end

function FaultMeta.Is(self:any, kind:string):boolean
    if self.Kind == kind then
        return true
    end
    return string.sub(self.Kind, 1, #kind + 1) == kind .. "."
end

function FaultMeta.Detail(self:any, key:string, value:any):any
    self.Details[key] = value
    return self
end

function FaultMeta.Wrap(self:any, kind:string, message:string?, details:{[string]:any}?):any
    const wrapped = Faults.new(kind, message or self.Message, details, 1)
    wrapped.Cause = self
    wrapped.Retryable = self.Retryable
    wrapped.Fingerprint = self.Fingerprint
    return wrapped
end

function FaultMeta.Root(self:any):any
    local current = self
    while current.Cause do
        current = current.Cause
    end
    return current
end

function FaultMeta.Chain(self:any):{any}
    const chain:{any} = {}
    local current:any = self
    const seen:{[any]:boolean} = {}
    while current and not seen[current] do
        seen[current] = true
        table.insert(chain, current)
        current = current.Cause
    end
    return chain
end

function FaultMeta.ToString(self:any):string
    const lines:{string} = {}

    for index, fault in ipairs(FaultMeta.Chain(self)) do
        const prefix = if index == 1 then "" else string.rep("  ", index - 1) .. "caused by "
        table.insert(lines, `{prefix}{fault.Kind}: {fault.Message}`)

        if next(fault.Details) ~= nil then
            table.insert(lines, string.rep("  ", index) .. Serialize.Fields(fault.Details))
        end
    end

    const trace = self.Trace or FaultMeta.Root(self).Trace
    if trace then
        table.insert(lines, Trace.Format(trace))
    end

    return table.concat(lines, "\n")
end

function FaultMeta.ToTable(self:any):{[string]:any}
    return {
        Kind = self.Kind,
        Message = self.Message,
        Details = Serialize.Sanitize(self.Details),
        Trace = Trace.ToWire(self.Trace),
        Cause = if self.Cause then FaultMeta.ToTable(self.Cause) else nil,
        Time = self.Time,
        Retryable = self.Retryable,
        Fingerprint = self.Fingerprint,
    }
end

function FaultMeta.Throw(self:any)
    error(self, 0)
end

function Faults.new(kind:string, message:string?, details:{[string]:any}?, skip:number?):Types.Fault
    const text = message or kind
    const trace = Trace.Capture(1 + (skip or 0))

    const fault = setmetatable({
        Kind = kind,
        Message = text,
        Details = details or {},
        Trace = trace,
        Cause = nil,
        Time = os.time(),
        Clock = os.clock(),
        Retryable = false,
        Handled = false,
        Fingerprint = Trace.Fingerprint(text, trace, kind),
        __blackbox = FAULT_TAG,
    }, FaultMeta)

    return (fault::any)::Types.Fault
end

function Faults.IsFault(value:any):boolean
    return type(value) == "table" and rawget(value::any, "__blackbox") == FAULT_TAG
end

const function splitLuauError(text:string):(string, string?)
    const source, line, rest = string.match(text, "^(.-):(%d+):%s*(.*)$")
    if source and rest and rest ~= "" then
        return rest, `{source}:{line}`
    end
    return text, nil
end

function Faults.Coerce(value:any, skip:number?, defaultKind:string?):Types.Fault
    if Faults.IsFault(value) then
        return value
    end

    const kind = defaultKind or "Runtime"

    if type(value) == "string" then
        const message, location = splitLuauError(value)
        const fault = Faults.new(kind, message, nil, 1 + (skip or 0))
        if location then
            (fault::any).Details.At = location
        end
        return fault
    end

    if type(value) == "table" then
        const source = value::{[string]:any}
        const message = source.Message or source.message or source.error or tostring(value)
        const fault = Faults.new(
            source.Kind or source.kind or kind,
            tostring(message),
            source.Details or source.details,
            1 + (skip or 0)
        )
        if rawget(source, "Trace") == nil then
            (fault::any).Details.Raw = Serialize.Sanitize(source)
        end
        return fault
    end

    return Faults.new(kind, tostring(value), nil, 1 + (skip or 0))
end

function Faults.Throw(kind:string, message:string?, details:{[string]:any}?):never
    const fault = Faults.new(kind, message, details, 1);
    (fault::any):Throw()
    error(fault, 0)
end

export type Attempt = {
    Ok:(self:Attempt) -> boolean,
    Fault:(self:Attempt) -> Types.Fault?,
    Value:(self:Attempt) -> any,
    Values:(self:Attempt) -> ...any,

    Catch:(self:Attempt, kindOrHandler:(string | (fault:Types.Fault) -> ...any), handler:((fault:Types.Fault) -> ...any)?) -> Attempt,
    Match:(self:Attempt, handlers:{[string]:(fault:Types.Fault) -> ...any}) -> Attempt,
    Finally:(self:Attempt, fn:(ok:boolean, fault:Types.Fault?) -> ()) -> Attempt,

    Unwrap:(self:Attempt) -> ...any,
    UnwrapOr:(self:Attempt, ...any) -> ...any,
    Rethrow:(self:Attempt) -> (),
}

const AttemptMeta = {}
AttemptMeta.__index = AttemptMeta

function AttemptMeta.Ok(self:any):boolean
    return self._ok
end

function AttemptMeta.Fault(self:any):Types.Fault?
    return self._fault
end

function AttemptMeta.Value(self:any):any
    return self._values[1]
end

function AttemptMeta.Values(self:any):...any
    return table.unpack(self._values, 1, self._values.n)
end

function AttemptMeta.Catch(self:any, kindOrHandler:any, handler:any):any
    if self._ok or self._handled then
        return self
    end

    local kind:string? = nil
    local callback = kindOrHandler
    if type(kindOrHandler) == "string" then
        kind = kindOrHandler
        callback = handler
    end

    if type(callback) ~= "function" then
        error("Blackbox: Catch needs a handler function", 2)
    end
    if kind ~= nil and not self._fault:Is(kind) then
        return self
    end

    self._handled = true
    self._fault.Handled = true

    const results = table.pack(xpcall(callback, function(err)
        return Faults.Coerce(err, 1, "Handler")
    end, self._fault))

    if results[1] then
        self._values = table.pack(table.unpack(results, 2, results.n))
    else
        self._handled = false
        self._fault = results[2]
        self._values = table.pack()
    end

    return self
end

function AttemptMeta.Match(self:any, handlers:{[string]:any}):any
    if self._ok or self._handled then
        return self
    end

    const kinds:{string} = {}
    for kind in pairs(handlers) do
        if kind ~= "Default" then
            table.insert(kinds, kind)
        end
    end
    table.sort(kinds, function(a:string, b:string)
        return #a > #b
    end)

    for _, kind in ipairs(kinds) do
        if self._fault:Is(kind) then
            return AttemptMeta.Catch(self, kind, handlers[kind])
        end
    end

    if handlers.Default then
        return AttemptMeta.Catch(self, handlers.Default)
    end
    return self
end

function AttemptMeta.Finally(self:any, fn:(ok:boolean, fault:Types.Fault?) -> ()):any
    const ok, err = pcall(fn::any, self._ok, self._fault)
    if not ok and self._ok then
        self._ok = false
        self._fault = Faults.Coerce(err, 1, "Finally")
    end
    return self
end

function AttemptMeta.Unwrap(self:any):...any
    if not self._ok and not self._handled then
        self._fault:Throw()
    end
    return table.unpack(self._values, 1, self._values.n)
end

function AttemptMeta.UnwrapOr(self:any, ...:any):...any
    if not self._ok and not self._handled then
        return ...
    end
    return table.unpack(self._values, 1, self._values.n)
end

function AttemptMeta.Rethrow(self:any)
    if self._fault then
        self._fault:Throw()
    end
end

function Faults.Try(fn:(...any) -> ...any, ...:any):Attempt
    const results = table.pack(xpcall(fn, function(err:any):Types.Fault
        return Faults.Coerce(err, 1)
    end, ...))

    const ok = results[1] == true

    return (setmetatable({
        _ok = ok,
        _fault = if ok then nil else results[2],
        _values = if ok then table.pack(table.unpack(results, 2, results.n)) else table.pack(),
        _handled = false,
    }, AttemptMeta)::any)::Attempt
end

function Faults.Assert<T>(condition:T, kind:string, message:string?, details:{[string]:any}?):T
    if not condition then
        const fault = Faults.new(kind, message or "assertion failed", details, 1);
        (fault::any):Throw()
    end
    return condition
end

function Faults.Expect<T>(value:T?, kind:string, message:string?):T
    if value == nil then
        const fault = Faults.new(kind, message or "expected a value, got nil", nil, 1);
        (fault::any):Throw()
    end
    return value::T
end

export type RetryOptions = {
    Attempts:number?,
    Delay:number?,
    Backoff:number?,
    MaxDelay:number?,
    Jitter:number?,
    RetryIf:((fault:Types.Fault, attempt:number) -> boolean)?,
    OnRetry:((fault:Types.Fault, attempt:number, delay:number) -> ())?,
}

function Faults.Retry(options:RetryOptions, fn:(attempt:number) -> ...any, ...:any):Attempt
    const attempts = math.max(1, options.Attempts or 3)
    const backoff = options.Backoff or 2
    const maxDelay = options.MaxDelay or 30
    const jitter = options.Jitter or 0.25
    local delay = options.Delay or 0.5

    local last:Attempt = nil::any

    for attempt = 1, attempts do
        const outcome = Faults.Try(fn, attempt, ...)
        if outcome:Ok() then
            return outcome
        end

        last = outcome
        const fault = outcome:Fault()::Types.Fault

        if attempt >= attempts then
            break
        end
        if options.RetryIf and not options.RetryIf(fault, attempt) then
            break
        end

        const spread = delay * jitter
        const wait = math.clamp(delay + (math.random() * 2 - 1) * spread, 0, maxDelay)

        if options.OnRetry then
            options.OnRetry(fault, attempt, wait)
        end

        task.wait(wait)
        delay = math.min(delay * backoff, maxDelay)
    end

    return last
end

function Faults.Protect<A..., R...>(fn:(A...) -> R...):(A...) -> Attempt
    return function(...:any):Attempt
        return Faults.Try(fn::any, ...)
    end
end

Faults.Meta = FaultMeta

return Faults
