//-------------------------------------------------------------------- Types
export type Constructor = (Target: Model, ...args: Array<unknown>) => void;
export type Spawner = (At: CFrame, ...args: Array<unknown>) => BasePart;
//-------------------------------------------------------------------- Helpers
function RootOf(Template: Model): BasePart {
    const Found = Template.PrimaryPart !== undefined ? Template.PrimaryPart : Template.FindFirstChild("RootPart")

    if (Found === undefined || !Found.IsA("BasePart")) {
        error(`MovableObject: template "${Template.Name}" needs a PrimaryPart or a child part named "RootPart"`)
    }

    return Found
}

function WeldLoose(Target: Model, Root: BasePart) {
    const Joined = new Set<Instance>()

    for (const Item of Target.GetDescendants()) {
        if (Item.IsA("WeldConstraint") || Item.IsA("JointInstance")) {
            const Part0 = Item.Part0
            const Part1 = Item.Part1

            if (Part0 !== undefined) {
                Joined.add(Part0)
            }

            if (Part1 !== undefined) {
                Joined.add(Part1)
            }
        }
    }

    for (const Item of Target.GetDescendants()) {
        if (Item.IsA("BasePart")) {
            if (Item !== Root && !Joined.has(Item)) {
                const Weld = new Instance("WeldConstraint")
                Weld.Part0 = Root
                Weld.Part1 = Item
                Weld.Parent = Item
            }

            Item.Anchored = false
        }
    }
}
//-------------------------------------------------------------------- MovableObject
export function MovableObject(Template: Model, Construct?: Constructor): Spawner {
    RootOf(Template)

    return (At: CFrame, ...args: Array<unknown>) => {
        const Clone = Template.Clone()

        if (Construct !== undefined) {
            Construct(Clone, ...args)
        }

        const Root = RootOf(Clone)
        Clone.PivotTo(At.mul(Root.CFrame.ToObjectSpace(Clone.GetPivot())))

        const Base = new Instance("Part")
        Base.Name = `${Template.Name}Base`
        Base.Anchored = true
        Base.CanCollide = false
        Base.CanQuery = false
        Base.CanTouch = false
        Base.Transparency = 1
        Base.Size = Root.Size
        Base.CFrame = Root.CFrame

        WeldLoose(Clone, Root)

        const Weld = new Instance("WeldConstraint")
        Weld.Part0 = Base
        Weld.Part1 = Root
        Weld.Parent = Root

        Clone.Parent = Base

        Base.Destroying.Connect(() => {
            if (Clone.Parent !== undefined && !Clone.IsDescendantOf(Base)) {
                Clone.Destroy()
            }
        })

        return Base
    }
}

export default MovableObject
