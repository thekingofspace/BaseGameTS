--!strict

const Serialize = require(script.Parent.Serialize)
const Types = require(script.Parent.Types)

const Trace = {}

const MAX_FRAMES = 24

const SELF_SOURCE = (debug.info(1, "s") or "")::string
const MODULE_ROOT = string.match(SELF_SOURCE, "^(.*)%.[^%.]*$") or SELF_SOURCE

const function isInternal(source:string):boolean
    return MODULE_ROOT ~= "" and string.sub(source, 1, #MODULE_ROOT) == MODULE_ROOT
end

function Trace.Capture(skip:number?, limit:number?):Types.Trace
    const start = 2 + (skip or 0)
    const max = limit or MAX_FRAMES

    const frames:{Types.Frame} = {}
    local level = start
    local trimming = true

    while #frames < max do
        const source, line, name = debug.info(level, "sln")
        if source == nil then
            break
        end
        level += 1

        const path = source::string
        if trimming and isInternal(path) then
            continue
        end
        trimming = false

        table.insert(frames, {
            Source = path,
            Line = (line::number) or 0,
            Name = if name ~= nil and name ~= "" then name::string else nil,
            What = if path == "[C]" then "C" else "Lua",
        })
    end

    return { Frames = frames }
end

function Trace.Location(skip:number?):string?
    const source, line = debug.info(2 + (skip or 0), "sl")
    if source == nil then
        return nil
    end
    return `{source}:{line}`
end

function Trace.FromTraceback(raw:string):Types.Trace
    const frames:{Types.Frame} = {}

    for line in string.gmatch(raw, "[^\r\n]+") do
        const text = string.match(line, "^%s*(.-)%s*$") or line
        if text == "" or text == "Stack Begin" or text == "Stack End" then
            continue
        end

        local source, number, name = string.match(text, "^Script '(.-)', Line (%d+)%s*%-?%s*(.*)$")
        if source == nil then
            source, number, name = string.match(text, "^(.-):(%d+)%s*(.*)$")
        end

        if source ~= nil and number ~= nil then
            const cleaned = string.gsub(name or "", "^function%s+", "")
            table.insert(frames, {
                Source = source,
                Line = tonumber(number) or 0,
                Name = if cleaned ~= "" then cleaned else nil,
                What = if source == "[C]" then "C" else "Lua",
            })
        end
    end

    return { Frames = frames, Raw = raw }
end

function Trace.Format(trace:Types.Trace?, indent:string?):string
    if trace then
        if #trace.Frames == 0 then
            return trace.Raw or "<no stack>"
        end

        const pad = indent or "    "
        const lines:{string} = {}
        for _, frame in ipairs(trace.Frames) do
            if frame.Name then
                table.insert(lines, `{pad}at {frame.Name} ({frame.Source}:{frame.Line})`)
            else
                table.insert(lines, `{pad}at {frame.Source}:{frame.Line}`)
            end
        end
        return table.concat(lines, "\n")
    end
    return "<no stack>"
end

function Trace.ToWire(trace:Types.Trace?):{string}?
    if trace then
        const out:{string} = {}
        for _, frame in ipairs(trace.Frames) do
            table.insert(out, `{frame.Source}:{frame.Line}:{frame.Name or ""}`)
        end
        return out
    end
    return nil
end

function Trace.FromWire(packed:{string}?):Types.Trace?
    if packed then
        const frames:{Types.Frame} = {}
        for _, text in ipairs(packed) do
            if type(text) ~= "string" then
                continue
            end
            const source, line, name = string.match(text, "^(.*):(%d+):(.*)$")
            if source then
                table.insert(frames, {
                    Source = source,
                    Line = tonumber(line) or 0,
                    Name = if name ~= "" then name else nil,
                    What = if source == "[C]" then "C" else "Lua",
                })
            end
        end
        return { Frames = frames }
    end
    return nil
end

function Trace.Normalize(message:string):string
    local text = message

    text = string.gsub(text, "0[xX]%x+", "<hex>")
    text = string.gsub(text, "%x%x%x%x%x%x%x%x%-%x+%-%x+%-%x+%-%x+", "<uuid>")
    text = string.gsub(text, "%d+%.%d+", "<num>")
    text = string.gsub(text, "%d+", "<num>")
    text = string.gsub(text, "%s+", " ")
    text = string.match(text, "^%s*(.-)%s*$") or text

    return text
end

function Trace.Fingerprint(message:string, trace:Types.Trace?, salt:string?):string
    const parts = { salt or "", Trace.Normalize(message) }

    if trace then
        for index = 1, math.min(3, #trace.Frames) do
            const frame = trace.Frames[index]
            table.insert(parts, `{frame.Source}:{frame.Line}`)
        end
    end

    return Serialize.Hash(table.concat(parts, "|"))
end

return Trace
