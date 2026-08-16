const ReplicatedStorage = game:GetService("ReplicatedStorage")
const vide = require(ReplicatedStorage.Shared.vide)

const create = vide.create

export type Spec = {
    ClassName: string | Instance,
    [any]: any,
}

const RESERVED = {
    ClassName = true,
    Children = true,
    Attributes = true,
    Tags = true,
}

local load

const function build_child(child: any): any
    if type(child) == "table" and child.ClassName ~= nil then
        return load(child)
    end
    return child
end

function load(spec: Spec): Instance
    if type(spec) ~= "table" then
        error(`VideLoader: expected a spec table, got {typeof(spec)}`, 2)
    end

    local class = spec.ClassName
    if class == nil then
        error("VideLoader: spec is missing a `ClassName` field", 2)
    end

    local props = {}

    for key, value in spec do
        if type(key) == "string" and not RESERVED[key] then
            props[key] = value
        end
    end

    local count = 0
    for _, child in ipairs(spec) do
        count += 1
        props[count] = build_child(child)
    end

    if type(spec.Children) == "table" then
        for _, child in ipairs(spec.Children) do
            count += 1
            props[count] = build_child(child)
        end
    end

    local instance:Instance = (create :: any)(class)(props)

    if type(spec.Attributes) == "table" then
        for name, value in spec.Attributes do
            instance:SetAttribute(name, value)
        end
    end

    if type(spec.Tags) == "table" then
        for _, tag in ipairs(spec.Tags) do
            instance:AddTag(tag)
        end
    end

    return instance
end

return load
