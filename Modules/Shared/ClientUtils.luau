local ClientUtils = {}

local escapes = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&apos;",
}

local function escape(text: string): string
    return (string.gsub(text, "[&<>\"']", escapes))
end

local function toHex(color: Color3): string
    local r = math.clamp(math.round(color.R * 255), 0, 255)
    local g = math.clamp(math.round(color.G * 255), 0, 255)
    local b = math.clamp(math.round(color.B * 255), 0, 255)
    return string.format("%02X%02X%02X", r, g, b)
end
function ClientUtils.resolveRichColor(text: string, color: Color3): string
    return `<font color="#{toHex(color)}">{escape(text)}</font>`
end

export type TextObject = TextLabel | TextButton | TextBox

local activeTypeOuts: { [TextObject]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

function ClientUtils.typeOut(label: TextObject, text: string?, secondsPerGrapheme: number?): () -> ()
    local previous = activeTypeOuts[label]
    if previous then
        previous()
    end

    local fullText = if text ~= nil then text else label.Text
    local delay = secondsPerGrapheme or 0.04

    label.Text = fullText
    label.MaxVisibleGraphemes = 0

    local total = 0
    for _ in utf8.graphemes(fullText) do
        total += 1
    end

    local finished = false
    local function finish()
        if finished then
            return
        end
        finished = true
        if activeTypeOuts[label] == finish then
            activeTypeOuts[label] = nil
        end
        label.MaxVisibleGraphemes = -1
    end
    activeTypeOuts[label] = finish

    task.spawn(function()
        for visible = 1, total do
            if finished then
                return
            end
            label.MaxVisibleGraphemes = visible
            task.wait(delay)
        end
        finish()
    end)

    return finish
end

function ClientUtils.deepPairs(
    tbl: { [any]: any },
    callback: (key: any, value: any) -> (),
    callbackOnTables: boolean?
)
    for key, value in tbl do
        if type(value) == "table" then
            if callbackOnTables then
                callback(key, value)
            end
            ClientUtils.deepPairs(value, callback, callbackOnTables)
        else
            callback(key, value)
        end
    end
end

return ClientUtils
