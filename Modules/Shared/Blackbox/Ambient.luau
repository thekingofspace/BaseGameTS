--!strict

const Serialize = require(script.Parent.Serialize)

const Ambient = {}

export type Frame = {
    Name:string,
    SpanId:string,
    TraceId:string,
    Fields:{[string]:any}?,
    Started:number,
}

type Stack = {Frame}

const Stacks:{[thread]:Stack} = setmetatable({}, { __mode = "k" })::any

local counter = 0

function Ambient.NewId(prefix:string?):string
    counter += 1
    const stamp = Serialize.Hash(`{counter}:{os.clock()}:{math.random()}`)
    return `{prefix or ""}{string.sub(stamp, 1, 8)}`
end

const function stackFor(thread:thread, create:boolean):Stack?
    local stack = Stacks[thread]
    if stack == nil and create then
        stack = {}
        Stacks[thread] = stack
    end
    return stack
end

function Ambient.Push(name:string, fields:{[string]:any}?, traceId:string?):Frame
    const thread = coroutine.running()
    const stack = stackFor(thread, true)::Stack
    const parent = stack[#stack]

    const frame:Frame = {
        Name = name,
        SpanId = Ambient.NewId(),
        TraceId = traceId or (if parent then parent.TraceId else Ambient.NewId()),
        Fields = fields,
        Started = os.clock(),
    }

    table.insert(stack, frame)
    return frame
end

function Ambient.Pop(frame:Frame?):Frame?
    const thread = coroutine.running()
    const stack = stackFor(thread, false)
    if stack and #stack > 0 then
        if frame == nil then
            return table.remove(stack)
        end

        for index = #stack, 1, -1 do
            if stack[index] == frame then
                for _ = #stack, index, -1 do
                    table.remove(stack)
                end
                break
            end
        end

        if #stack == 0 then
            Stacks[thread] = nil
        end
        return frame
    end
    return nil
end

function Ambient.Current():Frame?
    const stack = stackFor(coroutine.running(), false)
    if stack then
        return stack[#stack]
    end
    return nil
end

function Ambient.TraceId():string?
    const frame = Ambient.Current()
    return if frame then frame.TraceId else nil
end

function Ambient.Fields():{[string]:any}?
    const stack = stackFor(coroutine.running(), false)
    if not stack then
        return nil
    end

    local merged:{[string]:any}? = nil
    for _, frame in ipairs(stack::Stack) do
        const fields = frame.Fields
        if fields then
            const target:{[string]:any} = merged or {}
            merged = target
            for key, value in pairs(fields) do
                target[key] = value
            end
        end
    end
    return merged
end

function Ambient.Annotate(fields:{[string]:any})
    const frame = Ambient.Current()
    if frame then
        const target:{[string]:any} = frame.Fields or {}
        frame.Fields = target
        for key, value in pairs(fields) do
            target[key] = value
        end
    end
end

function Ambient.Path():string?
    const stack = stackFor(coroutine.running(), false)
    if not stack or #stack == 0 then
        return nil
    end

    const names:{string} = {}
    for _, frame in ipairs(stack::Stack) do
        table.insert(names, frame.Name)
    end
    return table.concat(names, " > ")
end

function Ambient.Capture():Stack?
    const stack = stackFor(coroutine.running(), false)
    if stack and #stack > 0 then
        return table.clone(stack)
    end
    return nil
end

function Ambient.Adopt(captured:Stack?)
    const thread = coroutine.running()
    if captured and #captured > 0 then
        Stacks[thread] = table.clone(captured)
    else
        Stacks[thread] = nil
    end
end

function Ambient.Wear<A..., R...>(captured:Stack?, fn:(A...) -> R..., ...:A...):R...
    const thread = coroutine.running()
    const previous = Stacks[thread]

    Ambient.Adopt(captured)
    const results = table.pack(pcall(fn::any, ...))
    Stacks[thread] = previous

    if not results[1] then
        error(results[2], 0)
    end
    return table.unpack(results, 2, results.n)
end

function Ambient.Clear()
    Stacks[coroutine.running()] = nil
end

return Ambient
