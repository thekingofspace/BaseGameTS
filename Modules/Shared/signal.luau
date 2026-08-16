const module = {}

export type Connection = {
    -- Removes this connection from its signal so the callback no longer runs
    Disconnect:(self:Connection) -> (),
    -- Wraps the callback in extra logic; the wrapper gets the original callback plus the fired args and decides if/how to run it. Stacks, newest runs outermost
    Extend:(self:Connection, wrapper:(original:(...any) -> ...any, ...any) -> ...any) -> Connection,
    src:(...any) -> ...any
}

-- Runs before listeners on Fire/Invoke. Return true plus the args to forward, or false to block the fire
export type MiddlewareFunction = (...any) -> (boolean, ...any)

export type Signal<t...> = {
    Mode:"Deffered" | "Serial", -- deffered means the threads are run via task.defer. serial means they run one after another this can lead to hi wait times
    -- Runs the callback every time the signal fires
    Connect:(self:Signal<t...>, sink:(t...) -> ...any) -> Connection,
    -- Runs the callback on the next fire only, then disconnects
    Once:(self:Signal<t...>, sink:(t...) -> ...any) -> Connection,

    -- Fires all listeners (and resumes Await-ing threads) with the given args
    Fire:(self:Signal<t...>, t...) -> (),

    -- Fires serially and returns the last non-empty value returned by a listener
    Invoke:(self:Signal<t...>, t...) -> ...any,
    -- Fires serially and returns every non-empty return, packed, in a list
    InvokePersitent:(self:Signal<t...>, t...) -> {{any}},

    -- Adds middleware that can transform or block fires; runs in the order added
    Use:(self:Signal<t...>, middleware:MiddlewareFunction) -> (),
    -- Forwards every fire of this signal into the target signal; disconnect the returned connection to stop
    Pipe:(self:Signal<t...>, target:Signal<t...>) -> Connection,
    -- True if anything is currently connected
    HasConnections:(self:Signal<t...>) -> boolean,

    -- Yields the current thread until the next fire, returning its args
    ---@yields
    Await:(self:Signal<t...>) -> ...any,
    -- Like Await, but resumes with no values after `timeout` seconds if nothing fired
    ---@yields
    AwaitFor:(self:Signal<t...>, timeout:number) -> ...any,

    -- Disconnects everything, clears middleware, and unhooks any wrapped RBXScriptSignal
    Destroy:(self:Signal<t...>) -> (),
}

type ConnectionObject = {
    Disconnect:(self:ConnectionObject) -> (),
    src:(...any) -> ...any,
    _signal:SignalObject,
    _meta:boolean,
    _once:boolean,
    _connected:boolean,
    _next:ConnectionObject?,
}

type SignalObject = {
    Mode:"Deffered" | "Serial",
    _head:ConnectionObject?,
    _metaHead:ConnectionObject?,
    _waiting:{thread},
    _middleware:{MiddlewareFunction},
    _upstream:RBXScriptConnection?,
}

const Connection = {}
Connection.__index = Connection

function Connection.Disconnect(self:ConnectionObject)
    if not self._connected then
        return
    end
    self._connected = false

    local signal = self._signal
    local head = if self._meta then signal._metaHead else signal._head

    if head == self then
        if self._meta then
            signal._metaHead = self._next
        else
            signal._head = self._next
        end
    else
        local prev = head
        while prev and prev._next ~= self do
            prev = prev._next
        end
        if prev then
            prev._next = self._next
        end
    end
end

function Connection.Extend(self:ConnectionObject, wrapper:(original:(...any) -> ...any, ...any) -> ...any):ConnectionObject
    local inner = self.src
    self.src = function(...)
        return wrapper(inner, ...)
    end
    return self
end

const function createConnection(signal:SignalObject, sink:(...any) -> ...any, meta:boolean, once:boolean):ConnectionObject
    local node = setmetatable({
        src = sink,
        _signal = signal,
        _meta = meta,
        _once = once,
        _connected = true,
        _next = if meta then signal._metaHead else signal._head,
    }, Connection)

    if meta then
        signal._metaHead = node :: any
    else
        signal._head = node :: any
    end

    return node :: any
end

const function collectLast(head:ConnectionObject?, args:{any}, argc:number):{any}?
    local last:{any}? = nil
    local node = head
    while node do
        local nextNode = node._next
        if node._connected then
            local returns = table.pack(node.src(table.unpack(args, 1, argc)))
            if returns.n > 0 then
                last = returns
            end
            if node._once then
                node:Disconnect()
            end
        end
        node = nextNode
    end
    return last
end

const function collectAll(head:ConnectionObject?, args:{any}, argc:number):{{any}}
    local results = {}
    local node = head
    while node do
        local nextNode = node._next
        if node._connected then
            local returns = table.pack(node.src(table.unpack(args, 1, argc)))
            if returns.n > 0 then
                table.insert(results, returns)
            end
            if node._once then
                node:Disconnect()
            end
        end
        node = nextNode
    end
    return results
end

const function applyMiddleware(self:SignalObject, ...):(boolean, {any})
    local args = table.pack(...)
    for _, mw in ipairs(self._middleware) do
        local returns = table.pack(mw(table.unpack(args, 1, args.n)))
        if not returns[1] then
            return false, args
        end
        args = { n = returns.n - 1, table.unpack(returns, 2, returns.n) }
    end
    return true, args
end

const function fireListeners(self:SignalObject, ...)
    local node = self._head
    while node do
        local nextNode = node._next
        if node._connected then
            if node._once then
                node:Disconnect()
            end
            if self.Mode == "Deffered" then
                task.defer(node.src, ...)
            else
                local ok, err = pcall(node.src, ...)
                if not ok then
                    task.spawn(error, err)
                end
            end
        end
        node = nextNode
    end

    if #self._waiting > 0 then
        local waiting = self._waiting
        self._waiting = {}
        for _, thread in waiting do
            task.spawn(thread, ...)
        end
    end
end

const Signal = {}
Signal.__index = Signal

function Signal.Connect(self:SignalObject, sink:(...any) -> ...any)
    return createConnection(self, sink, false, false)
end

function Signal.Once(self:SignalObject, sink:(...any) -> ...any)
    return createConnection(self, sink, false, true)
end

function Signal.Fire(self:SignalObject, ...)
    if #self._middleware > 0 then
        local allowed, args = applyMiddleware(self, ...)
        if not allowed then
            return
        end
        return fireListeners(self, table.unpack(args, 1, args.n))
    end
    return fireListeners(self, ...)
end

function Signal.Invoke(self:SignalObject, ...)
    local allowed, args = applyMiddleware(self, ...)
    if not allowed then
        return
    end
    local last = collectLast(self._head, args, args.n)
    if last then
        return table.unpack(last, 1, last.n)
    end
    return
end

function Signal.InvokePersitent(self:SignalObject, ...)
    local allowed, args = applyMiddleware(self, ...)
    if not allowed then
        return {}
    end
    return collectAll(self._head, args, args.n)
end

function Signal.Use(self:SignalObject, middleware:MiddlewareFunction)
    table.insert(self._middleware, middleware)
end

function Signal.Pipe(self:SignalObject, target:Signal<...any>):Connection
    return createConnection(self, function(...)
        target:Fire(...)
    end, false, false) :: any
end

function Signal.HasConnections(self:SignalObject):boolean
    return self._head ~= nil
end


function Signal.Await(self:SignalObject)
    table.insert(self._waiting, coroutine.running())
    return coroutine.yield()
end

function Signal.AwaitFor(self:SignalObject, timeout:number)
    local thread = coroutine.running()
    table.insert(self._waiting, thread)
    local timer = task.delay(timeout, function()
        local index = table.find(self._waiting, thread)
        if index then
            table.remove(self._waiting, index)
            task.spawn(thread)
        end
    end)

    local results = table.pack(coroutine.yield())
    if coroutine.status(timer) == "suspended" then
        task.cancel(timer)
    end
    return table.unpack(results, 1, results.n)
end

function Signal.Destroy(self:SignalObject)
    local node = self._head
    while node do
        local nextNode = node._next
        node._connected = false
        node._next = nil
        node = nextNode
    end
    self._head = nil

    node = self._metaHead
    while node do
        local nextNode = node._next
        node._connected = false
        node._next = nil
        node = nextNode
    end
    self._metaHead = nil

    if self._upstream then
        self._upstream:Disconnect()
        self._upstream = nil
    end
    table.clear(self._middleware)
end

function module.new(Mode:("Deffered" | "Serial")?):Signal<...any>
    local self = setmetatable({
        Mode = Mode or "Serial",
        _head = nil,
        _metaHead = nil,
        _waiting = {},
        _middleware = {},
    }, Signal)

    return (self :: any) :: Signal<...any>
end

function module.wrap(rbxSignal:RBXScriptSignal, Mode:("Deffered" | "Serial")?):Signal<...any>
    local self = module.new(Mode) :: any
    self._upstream = rbxSignal:Connect(function(...)
        self:Fire(...)
    end)
    return self
end

return module
