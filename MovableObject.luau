export type Constructor = (Model: Model, ...any) -> ()
export type Spawner = (At: CFrame, ...any) -> BasePart

local function RootOf(Template: Model): BasePart
    local Root: Instance? = Template.PrimaryPart or Template:FindFirstChild("RootPart")
    assert(
        Root and Root:IsA("BasePart"),
        `MovableObject: template "{Template.Name}" needs a PrimaryPart or a child part named "RootPart"`
    )
    return Root :: BasePart
end

local function WeldLoose(Model: Model, Root: BasePart)
    local Joined: {[Instance]: boolean} = {}
    for _, Item in ipairs(Model:GetDescendants()) do
        if Item:IsA("WeldConstraint") or Item:IsA("JointInstance") then
            local Part0 = (Item :: any).Part0
            local Part1 = (Item :: any).Part1
            if Part0 then
                Joined[Part0] = true
            end
            if Part1 then
                Joined[Part1] = true
            end
        end
    end

    for _, Item in ipairs(Model:GetDescendants()) do
        if Item:IsA("BasePart") then
            if Item ~= Root and not Joined[Item] then
                local Weld = Instance.new("WeldConstraint")
                Weld.Part0 = Root
                Weld.Part1 = Item
                Weld.Parent = Item
            end
            Item.Anchored = false
        end
    end
end

return function(Template: Model, Construct: Constructor?): Spawner
    RootOf(Template)

    return function(At: CFrame, ...): BasePart
        local Model = Template:Clone()
        if Construct then
            Construct(Model, ...)
        end

        local Root = RootOf(Model)
        Model:PivotTo(At * Root.CFrame:ToObjectSpace(Model:GetPivot()))
        local Base = Instance.new("Part")
        Base.Name = Template.Name .. "Base"
        Base.Anchored = true
        Base.CanCollide = false
        Base.CanQuery = false
        Base.CanTouch = false
        Base.Transparency = 1
        Base.Size = Root.Size
        Base.CFrame = Root.CFrame

        WeldLoose(Model, Root)
        local Weld = Instance.new("WeldConstraint")
        Weld.Part0 = Base
        Weld.Part1 = Root
        Weld.Parent = Root

        Model.Parent = Base

        Base.Destroying:Connect(function()
            if Model.Parent and not Model:IsDescendantOf(Base) then
                Model:Destroy()
            end
        end)

        return Base
    end
end
