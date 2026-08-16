--!strict

export type LevelName = "TRACE" | "DEBUG" | "INFO" | "WARN" | "ERROR" | "FATAL" | "OFF"

const Level = {
    TRACE = 10,
    DEBUG = 20,
    INFO = 30,
    WARN = 40,
    ERROR = 50,
    FATAL = 60,
    OFF = 1000,
}

local NAMES:{[number]:string} = {}
local VALUES:{[string]:number} = {}

const function reindex()
    table.clear(NAMES)
    table.clear(VALUES)
    for name:string, value in pairs((Level::any)) do
        if type(value) == "number" then
            NAMES[value] = name
            VALUES[name] = value
        end
    end
end

function Level.NameOf(value:number):string
    const exact = NAMES[value]
    if exact then
        return exact
    end

    local bestName:string? = nil
    local bestValue = -math.huge
    for name, candidate in pairs(VALUES) do
        if candidate <= value and candidate > bestValue then
            bestName, bestValue = name, candidate
        end
    end

    if bestName == nil then
        return `LEVEL{value}`
    end
    return `{bestName}+{value - bestValue}`
end

function Level.Resolve(level:(LevelName | string | number)?):number?
    if type(level) == "number" then
        return level
    end
    if type(level) == "string" then
        return VALUES[level:upper()]
    end
    return nil
end

function Level.Expect(level:LevelName | string | number, context:string?):number
    const resolved = Level.Resolve(level)
    if resolved then
        return resolved
    end
    error(`{context or "Blackbox"}: '{tostring(level)}' is not a known log level`, 3)
end

function Level.Register(name:string, value:number)
    const key = name:upper()
    if type(value) ~= "number" then
        error("Blackbox: a level value must be a number", 2)
    end
    if VALUES[key] ~= nil and VALUES[key] ~= value then
        error(`Blackbox: level '{key}' is already registered at {VALUES[key]}`, 2)
    end
    (Level::any)[key] = value
    reindex()
end

function Level.All():{[string]:number}
    return table.clone(VALUES)
end

reindex()

return Level
