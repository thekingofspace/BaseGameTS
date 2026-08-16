--!strict

const RunService = game:GetService("RunService")

const Level = require(script.Parent.Level)
const Types = require(script.Parent.Types)

const IS_STUDIO = RunService:IsStudio()

export type State = {
    Level:number,
    TraceLevel:number,
    BreadcrumbLevel:number,
    BreadcrumbLimit:number,
    HistoryLimit:number,

    MaxDepth:number,
    MaxEntries:number,
    MaxStringLength:number,
    RedactKeys:{string},

    Dedupe:boolean,
    DedupeWindow:number,
    RateLimit:number,
    RateBurst:number,
    Sample:{[number]:number},

    CaptureGlobalErrors:boolean,
    CaptureOutput:boolean,
    Tags:{[string]:any},

    Console:{
        ShowTime:boolean,
        ShowLevel:boolean,
        ShowLogger:boolean,
        ShowFields:boolean,
        ShowSpan:boolean,
        Multiline:boolean,
        Glyphs:boolean,
        Traceback:boolean,
        UseTestService:boolean,
    },
}

const State:State = {
    Level = if IS_STUDIO then Level.DEBUG else Level.INFO,
    TraceLevel = Level.ERROR,
    BreadcrumbLevel = Level.ERROR,
    BreadcrumbLimit = 32,
    HistoryLimit = 256,

    MaxDepth = 4,
    MaxEntries = 24,
    MaxStringLength = 512,
    RedactKeys = {
        "password", "passwd", "secret", "token", "apikey", "api_key",
        "auth", "cookie", "session", "credential", "private", "signature",
    },

    Dedupe = true,
    DedupeWindow = 5,
    RateLimit = 60,
    RateBurst = 120,
    Sample = {},

    CaptureGlobalErrors = true,
    CaptureOutput = false,
    Tags = {},

    Console = {
        ShowTime = true,
        ShowLevel = true,
        ShowLogger = true,
        ShowFields = true,
        ShowSpan = IS_STUDIO,
        Multiline = IS_STUDIO,
        Glyphs = true,
        Traceback = true,
        UseTestService = IS_STUDIO,
    },
}

const Config = {}
Config.State = State

const Watchers:{(state:State) -> ()} = {}

function Config.OnChanged(callback:(state:State) -> ()):() -> ()
    table.insert(Watchers, callback)
    return function()
        const index = table.find(Watchers, callback)
        if index then
            table.remove(Watchers, index)
        end
    end
end

const function applyLevel(target:{[string]:any}, key:string, value:any, label:string)
    if value == nil then
        return
    end
    target[key] = Level.Expect(value, `Blackbox.Configure({label})`)
end

const function applyBool(target:{[string]:any}, key:string, value:any)
    if value ~= nil then
        target[key] = value == true
    end
end

const function applyNumber(target:{[string]:any}, key:string, value:any, label:string)
    if value == nil then
        return
    end
    if type(value) ~= "number" then
        error(`Blackbox.Configure: {label} must be a number, got {typeof(value)}`, 3)
    end
    target[key] = value
end

function Config.Configure(options:Types.Config)
    if type(options) ~= "table" then
        error("Blackbox.Configure expects a table", 2)
    end

    applyLevel(State::any, "Level", options.Level, "Level")
    applyLevel(State::any, "TraceLevel", options.TraceLevel, "TraceLevel")
    applyLevel(State::any, "BreadcrumbLevel", options.BreadcrumbLevel, "BreadcrumbLevel")
    applyNumber(State::any, "BreadcrumbLimit", options.BreadcrumbLimit, "BreadcrumbLimit")
    applyNumber(State::any, "HistoryLimit", options.HistoryLimit, "HistoryLimit")
    applyNumber(State::any, "MaxDepth", options.MaxDepth, "MaxDepth")
    applyNumber(State::any, "MaxEntries", options.MaxEntries, "MaxEntries")
    applyNumber(State::any, "MaxStringLength", options.MaxStringLength, "MaxStringLength")
    applyBool(State::any, "Dedupe", options.Dedupe)
    applyNumber(State::any, "DedupeWindow", options.DedupeWindow, "DedupeWindow")
    applyNumber(State::any, "RateLimit", options.RateLimit, "RateLimit")
    applyNumber(State::any, "RateBurst", options.RateBurst, "RateBurst")
    applyBool(State::any, "CaptureGlobalErrors", options.CaptureGlobalErrors)
    applyBool(State::any, "CaptureOutput", options.CaptureOutput)

    if options.RedactKeys then
        const keys:{string} = {}
        for _, key in ipairs(options.RedactKeys) do
            table.insert(keys, key:lower())
        end
        State.RedactKeys = keys
    end

    if options.Tags then
        for key, value in pairs(options.Tags) do
            State.Tags[key] = value
        end
    end

    if options.Sample then
        const sample:{[number]:number} = {}
        for name, fraction in pairs(options.Sample) do
            sample[Level.Expect(name, "Blackbox.Configure(Sample)")] = fraction
        end
        State.Sample = sample
    end

    if options.Console then
        const console = options.Console
        applyBool(State.Console::any, "ShowTime", console.ShowTime)
        applyBool(State.Console::any, "ShowLevel", console.ShowLevel)
        applyBool(State.Console::any, "ShowLogger", console.ShowLogger)
        applyBool(State.Console::any, "ShowFields", console.ShowFields)
        applyBool(State.Console::any, "ShowSpan", console.ShowSpan)
        applyBool(State.Console::any, "Multiline", console.Multiline)
        applyBool(State.Console::any, "Glyphs", console.Glyphs)
        applyBool(State.Console::any, "Traceback", console.Traceback)
        applyBool(State.Console::any, "UseTestService", console.UseTestService)
    end

    for _, watcher in ipairs(Watchers) do
        task.spawn(watcher, State)
    end
end

function Config.IsRedacted(key:string):boolean
    const lowered = key:lower()
    for _, needle in ipairs(State.RedactKeys) do
        if string.find(lowered, needle, 1, true) then
            return true
        end
    end
    return false
end

return Config
