--!strict

const Config = require(script.Parent.Config)

const State = Config.State

const Serialize = {}

export type Options = {
    MaxDepth:number?,
    MaxEntries:number?,
    MaxStringLength:number?,
    Redact:boolean?,
    Indent:string?,
}

function Serialize.Hash(text:string):string
    local hash = 2166136261
    for index = 1, #text do
        hash = bit32.bxor(hash, string.byte(text, index))
        hash = bit32.band(
            hash + bit32.lshift(hash, 1) + bit32.lshift(hash, 4)
                + bit32.lshift(hash, 7) + bit32.lshift(hash, 8) + bit32.lshift(hash, 24),
            0xFFFFFFFF
        )
    end
    return string.format("%08x", hash)
end

const function formatNumber(value:number):string
    if value ~= value then
        return "nan"
    end
    if value == math.huge then
        return "inf"
    end
    if value == -math.huge then
        return "-inf"
    end
    if value % 1 == 0 and math.abs(value) < 9007199254740992 then
        return string.format("%d", value)
    end
    return string.format("%.6g", value)
end

const ESCAPES:{[string]:string} = {
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
    ["\""] = "\\\"",
    ["\\"] = "\\\\",
}

const function formatString(value:string, limit:number):string
    local text = value
    local truncated = 0
    if #text > limit then
        truncated = #text - limit
        text = string.sub(text, 1, limit)
    end

    text = string.gsub(text, "[%c\"\\]", function(char:string):string
        return ESCAPES[char] or string.format("\\x%02x", string.byte(char))
    end)

    if truncated > 0 then
        return `"{text}"…(+{truncated} chars)`
    end
    return `"{text}"`
end

const function formatInstance(value:Instance):string
    const ok, full = pcall(function()
        return value:GetFullName()
    end)
    if ok then
        return `{value.ClassName}({full})`
    end
    return `{value.ClassName}(<unreachable>)`
end

const function formatFunction(value:(...any) -> ...any):string
    const ok, source, line = pcall(function()
        return debug.info(value, "sl")
    end)
    if ok and source then
        return `function<{source}:{line}>`
    end
    return "function"
end

const SPECIAL:{[string]:(value:any) -> string} = {
    Instance = formatInstance,
    EnumItem = function(value)
        return tostring(value)
    end,
    Enums = function()
        return "Enums"
    end,
    ["function"] = formatFunction,
    thread = function(value)
        return `thread<{coroutine.status(value)}>`
    end,
    buffer = function(value)
        return `buffer({buffer.len(value)} bytes)`
    end,
    Vector3 = function(value)
        return string.format("Vector3(%.3f, %.3f, %.3f)", value.X, value.Y, value.Z)
    end,
    Vector2 = function(value)
        return string.format("Vector2(%.3f, %.3f)", value.X, value.Y)
    end,
    CFrame = function(value)
        const position = value.Position
        return string.format("CFrame(%.3f, %.3f, %.3f)", position.X, position.Y, position.Z)
    end,
    Color3 = function(value)
        return string.format("Color3(%d, %d, %d)",
            math.round(value.R * 255), math.round(value.G * 255), math.round(value.B * 255))
    end,
    UDim2 = function(value)
        return string.format("UDim2(%.3g, %d, %.3g, %d)",
            value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
    end,
}

type Limits = {
    MaxDepth:number,
    MaxEntries:number,
    MaxStringLength:number,
    Redact:boolean,
    Indent:string?,
}

const function limitsFrom(options:Options?):Limits
    const given:Options = options or {}
    return {
        MaxDepth = given.MaxDepth or State.MaxDepth,
        MaxEntries = given.MaxEntries or State.MaxEntries,
        MaxStringLength = given.MaxStringLength or State.MaxStringLength,
        Redact = given.Redact ~= false,
        Indent = given.Indent,
    }
end

const function sortedKeys(source:{[any]:any}):{any}
    const keys:{any} = {}
    for key in pairs(source) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a:any, b:any)
        return tostring(a) < tostring(b)
    end)
    return keys
end

local render:(value:any, limits:Limits, depth:number, seen:{[any]:string}, path:string) -> string

const function renderTable(value:{[any]:any}, limits:Limits, depth:number, seen:{[any]:string}, path:string):string
    const previous = seen[value]
    if previous then
        return `<cycle → {previous}>`
    end
    if depth >= limits.MaxDepth then
        return "{…}"
    end

    seen[value] = path

    const parts:{string} = {}
    local count = 0
    local skipped = 0

    const length = #value
    local isArray = length > 0
    if isArray then
        for key in pairs(value) do
            if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > length then
                isArray = false
                break
            end
        end
    end

    if isArray then
        for index = 1, length do
            if count >= limits.MaxEntries then
                skipped = length - count
                break
            end
            count += 1
            table.insert(parts, render(value[index], limits, depth + 1, seen, `{path}[{index}]`))
        end
    else
        for _, key in ipairs(sortedKeys(value)) do
            if count >= limits.MaxEntries then
                skipped += 1
                continue
            end
            count += 1

            const name = tostring(key)
            local rendered:string
            if limits.Redact and type(key) == "string" and Config.IsRedacted(key) then
                rendered = `<redacted {typeof(value[key])}>`
            else
                rendered = render(value[key], limits, depth + 1, seen, `{path}.{name}`)
            end
            table.insert(parts, `{name} = {rendered}`)
        end
    end

    seen[value] = nil

    if skipped > 0 then
        table.insert(parts, `…(+{skipped} more)`)
    end
    if #parts == 0 then
        return "{}"
    end

    const indent = limits.Indent
    if indent then
        const pad = string.rep(indent, depth + 1)
        return "{\n" .. pad .. table.concat(parts, ",\n" .. pad) .. "\n" .. string.rep(indent, depth) .. "}"
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

function render(value:any, limits:Limits, depth:number, seen:{[any]:string}, path:string):string
    const kind = typeof(value)

    if value == nil then
        return "nil"
    elseif kind == "boolean" then
        return tostring(value)
    elseif kind == "number" then
        return formatNumber(value)
    elseif kind == "string" then
        return formatString(value, limits.MaxStringLength)
    elseif kind == "table" then
        const meta = getmetatable(value::any)
        if type(meta) == "table" and rawget(meta::any, "__tostring") then
            const ok, text = pcall(tostring, value)
            if ok then
                return text
            end
        end
        return renderTable(value, limits, depth, seen, path)
    end

    const special = SPECIAL[kind]
    if special then
        const ok, text = pcall(special, value)
        if ok then
            return text
        end
        return `<{kind}>`
    end

    const ok, text = pcall(tostring, value)
    if ok then
        return `{kind}({text})`
    end
    return `<{kind}>`
end

function Serialize.Inspect(value:any, options:Options?):string
    return render(value, limitsFrom(options), 0, {}, "root")
end

function Serialize.Pretty(value:any, options:Options?):string
    const limits = limitsFrom(options)
    limits.Indent = limits.Indent or "  "
    return render(value, limits, 0, {}, "root")
end

function Serialize.Fields(fields:{[string]:any}?, options:Options?):string
    if fields then
        const limits = limitsFrom(options)
        const parts:{string} = {}
        for _, key in ipairs(sortedKeys(fields)) do
            const name = tostring(key)
            if limits.Redact and Config.IsRedacted(name) then
                table.insert(parts, `{name}=<redacted>`)
            else
                table.insert(parts, `{name}={render(fields[key], limits, 1, {}, name)}`)
            end
        end
        return table.concat(parts, " ")
    end
    return ""
end

function Serialize.Sanitize(value:any, options:Options?):any
    const limits = limitsFrom(options)

    local walk:(value:any, depth:number, seen:{[any]:boolean}) -> any
    function walk(current:any, depth:number, seen:{[any]:boolean}):any
        const kind = typeof(current)

        if current == nil or kind == "boolean" or kind == "string" then
            if kind == "string" and #(current::string) > limits.MaxStringLength then
                return string.sub(current::string, 1, limits.MaxStringLength) .. "…"
            end
            return current
        end

        if kind == "number" then
            if current ~= current or current == math.huge or current == -math.huge then
                return formatNumber(current)
            end
            return current
        end

        if kind ~= "table" then
            return render(current, limits, depth, {}, "root")
        end

        if seen[current] then
            return "<cycle>"
        end
        if depth >= limits.MaxDepth then
            return "<truncated>"
        end

        seen[current] = true
        const out:{[string]:any} = {}
        local count = 0
        for key, item in pairs(current::{[any]:any}) do
            if count >= limits.MaxEntries then
                out["…"] = "truncated"
                break
            end
            count += 1

            const name = if type(key) == "string" then key else tostring(key)
            if limits.Redact and Config.IsRedacted(name) then
                out[name] = "<redacted>"
            else
                out[name] = walk(item, depth + 1, seen)
            end
        end
        seen[current] = nil

        return out
    end

    return walk(value, 0, {})
end

return Serialize
