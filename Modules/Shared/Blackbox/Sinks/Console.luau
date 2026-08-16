--!strict

const TestService = game:GetService("TestService")

const Config = require(script.Parent.Parent.Config)
const Level = require(script.Parent.Parent.Level)
const Serialize = require(script.Parent.Parent.Serialize)
const Trace = require(script.Parent.Parent.Trace)
const Types = require(script.Parent.Parent.Types)

const State = Config.State

const Console = {}
Console.__index = Console

Console.Emitting = false

const RECENT_LIMIT = 64
local Recent:{[string]:boolean} = {}
local RecentCount = 0

const function remember(text:string)
    if RecentCount >= RECENT_LIMIT then
        Recent = {}
        RecentCount = 0
    end
    if not Recent[text] then
        Recent[text] = true
        RecentCount += 1
    end
end

function Console.WasEmitted(text:string):boolean
    if Recent[text] then
        Recent[text] = nil
        RecentCount -= 1
        return true
    end
    return false
end

const GLYPHS:{[number]:string} = {
    [Level.TRACE] = "·",
    [Level.DEBUG] = "◦",
    [Level.INFO] = "•",
    [Level.WARN] = "▲",
    [Level.ERROR] = "✖",
    [Level.FATAL] = "☠",
}

const function glyphFor(level:number):string
    const exact = GLYPHS[level]
    if exact then
        return exact
    end
    local best = "•"
    local bestValue = -math.huge
    for value, glyph in pairs(GLYPHS) do
        if value <= level and value > bestValue then
            best, bestValue = glyph, value
        end
    end
    return best
end

const function timestamp():string
    const ok, text = pcall(function()
        return DateTime.now():FormatLocalTime("HH:mm:ss.SSS", "en-us")
    end)
    if ok then
        return text
    end
    return os.date("%H:%M:%S")::string
end

const function headline(entry:Types.Entry, options:typeof(State.Console)):string
    const parts:{string} = {}

    if options.ShowTime then
        table.insert(parts, `[{timestamp()}]`)
    end
    if options.Glyphs then
        table.insert(parts, glyphFor(entry.Level))
    end
    if options.ShowLevel then
        table.insert(parts, string.format("%-5s", entry.LevelName))
    end
    if options.ShowLogger and entry.Logger ~= "" then
        table.insert(parts, entry.Logger)
    end
    if options.ShowSpan and entry.Span then
        table.insert(parts, `({entry.Span})`)
    end

    table.insert(parts, "»")
    table.insert(parts, entry.Message)

    if entry.Count > 1 then
        table.insert(parts, `(x{entry.Count})`)
    end

    return table.concat(parts, " ")
end

function Console.Render(entry:Types.Entry, options:typeof(State.Console)?):string
    const style = options or State.Console
    const lines = { headline(entry, style) }
    const indent = if style.Multiline then "    │ " else "  "

    if style.ShowFields and entry.Fields and next(entry.Fields) ~= nil then
        const fields = Serialize.Fields(entry.Fields)
        if style.Multiline then
            table.insert(lines, indent .. fields)
        else
            lines[1] ..= `  {fields}`
        end
    end

    if entry.Fault then
        const fault = entry.Fault
        table.insert(lines, `{indent}{fault.Kind}: {fault.Message}`)

        local cause = fault.Cause
        local depth = 1
        while cause do
            table.insert(lines, `{indent}{string.rep("  ", depth)}caused by {cause.Kind}: {cause.Message}`)
            cause = cause.Cause
            depth += 1
        end

        if next(fault.Details) ~= nil then
            table.insert(lines, indent .. Serialize.Fields(fault.Details))
        end
    end

    if style.Traceback and entry.Trace and entry.Level >= State.TraceLevel then
        table.insert(lines, Trace.Format(entry.Trace, indent))
    end

    if entry.Breadcrumbs and #entry.Breadcrumbs > 0 then
        table.insert(lines, `{indent}breadcrumbs ({#entry.Breadcrumbs}):`)
        for _, crumb in ipairs(entry.Breadcrumbs) do
            const detail = if crumb.Fields then "  " .. Serialize.Fields(crumb.Fields) else ""
            table.insert(lines, `{indent}  [{crumb.Category}] {crumb.Message}{detail}`)
        end
    end

    return table.concat(lines, "\n")
end

const function emit(level:number, text:string, useTestService:boolean)
    if level >= Level.ERROR then
        if useTestService and pcall(function()
            TestService:Error(text)
        end) then
            return
        end
        warn(text)
    elseif level >= Level.WARN then
        warn(text)
    elseif level <= Level.DEBUG and useTestService then
        if not pcall(function()
            TestService:Message(text)
        end) then
            print(text)
        end
    else
        print(text)
    end
end

function Console.Write(self:any, entry:Types.Entry)
    const style = self.Options or State.Console

    Console.Emitting = true
    const ok, rendered = pcall(Console.Render, entry, style)
    if ok then
        remember(rendered)
        emit(entry.Level, rendered, style.UseTestService)
    else
        warn(`[Blackbox] console sink failed to render an entry: {tostring(rendered)}`)
    end
    Console.Emitting = false
end

function Console.new(options:Types.ConsoleOptions?):Types.Sink
    local style = State.Console
    if options then
        style = table.clone(State.Console)
        for key, value in pairs(options::{[string]:any}) do
            (style::{[string]:any})[key] = value
        end
    end

    const self = setmetatable({
        Name = "Console",
        Level = Level.TRACE,
        Enabled = true,
        Options = style,
    }, Console)

    return (self::any)::Types.Sink
end

return Console
