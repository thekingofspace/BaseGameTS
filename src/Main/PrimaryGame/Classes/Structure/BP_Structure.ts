//-------------------------------------------------------------------- SERVICES
import { Debris, HttpService, Players, RunService, TweenService, Workspace } from "@rbxts/services";
//-------------------------------------------------------------------- MODULES
import Pigeon from "@shared/Pigeon";
import { RegisterClass } from "../Super/CommonInstance";
import { MonoBehaviour } from "../Super/MonoBehaviour";
//-------------------------------------------------------------------- Topline VARS
const StructureFolder_Name = "Structures"
const StructureFolder_Timeout = 500
const OwnerClick_Distance = 64
const Support_Samples = 3
const Support_Inset = 0.9
const Support_Skin = 0.15
const Support_MaxGap = 1.5
const Support_MinRatio = 0.6
const Support_Probe = Vector3.one.mul(0.1)

const FadeOut_Time = 0.45
const FadeOut_Info = new TweenInfo(FadeOut_Time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
const FadeOut_Black = new Color3(0, 0, 0)

const IsClient = RunService.IsClient()

let StructureFolder: Folder | undefined = undefined

const StructureSocket = Pigeon.new<Pigeon.PigeonCarrier>("StructureSocket")
const OwnedStructures = new Map<Player, Map<string, BP_Structure>>()
const CreationActions = new Map<string, (guid: string) => void>()
//-------------------------------------------------------------------- Types
export type StructureInfo = Record<string, unknown>;
//-------------------------------------------------------------------- Fade out
function FadeAndClear(Target: Model) {
    if (Target.Parent === undefined) {
        return
    }

    for (const Item of Target.GetDescendants()) {
        if (Item.IsA("BasePart")) {
            Item.Anchored = true
            Item.CanCollide = false
            Item.CanQuery = false
            Item.CanTouch = false

            TweenService.Create(Item, FadeOut_Info, {
                Color: FadeOut_Black,
                Transparency: 1
            }).Play()
        } else if (Item.IsA("Decal")) {
            TweenService.Create(Item, FadeOut_Info, { Transparency: 1 }).Play()
        }
    }

    Debris.AddItem(Target, FadeOut_Time + 0.1)
}
//-------------------------------------------------------------------- Support probing
const SupportRay = new RaycastParams()
SupportRay.FilterType = Enum.RaycastFilterType.Exclude
SupportRay.IgnoreWater = false

const SupportOverlap = new OverlapParams()
SupportOverlap.FilterType = Enum.RaycastFilterType.Exclude

function SampleOffset(Index: number, Span: number): number {
    if (Support_Samples < 2) {
        return 0
    }

    return -Span + (Index - 1) * (2 * Span) / (Support_Samples - 1)
}

function HasSpaceUnder(Target: Model, Position: CFrame, Ignore?: Array<Instance>): boolean {
    const [Bounds, Size] = Target.GetBoundingBox()

    if (Size.X <= 0 && Size.Y <= 0 && Size.Z <= 0) {
        return false
    }

    const Base = Position.mul(Target.GetPivot().ToObjectSpace(Bounds))
    const Filter: Array<Instance> = [Target]

    if (Ignore !== undefined) {
        for (const Item of Ignore) {
            Filter.push(Item)
        }
    }

    SupportRay.FilterDescendantsInstances = Filter
    SupportOverlap.FilterDescendantsInstances = Filter

    const SpanX = Size.X * 0.5 * Support_Inset
    const SpanZ = Size.Z * 0.5 * Support_Inset
    const Floor = -Size.Y * 0.5 + Support_Skin
    const Reach = Base.UpVector.mul(-(Support_Skin + Support_MaxGap))

    let Supported = 0

    for (let ix = 1; ix <= Support_Samples; ix++) {
        const ox = SampleOffset(ix, SpanX)

        for (let iz = 1; iz <= Support_Samples; iz++) {
            const Origin = Base.mul(new CFrame(ox, Floor, SampleOffset(iz, SpanZ))).Position

            if (Workspace.Raycast(Origin, Reach, SupportRay) !== undefined) {
                Supported += 1
            } else if (Workspace.GetPartBoundsInBox(new CFrame(Origin), Support_Probe, SupportOverlap).size() > 0) {
                Supported += 1
            }
        }
    }

    return Supported < math.ceil(Support_Samples * Support_Samples * Support_MinRatio)
}
//-------------------------------------------------------------------- BP_Structure
RegisterClass("BP_Structure", "MonoBehaviour")

export class BP_Structure extends MonoBehaviour {
    public static readonly StaticName: string = "BP_Structure";
    public readonly ClassName: string = "BP_Structure";

    public Enabled = false;
    public Model!: Model;
    public Owner?: Player;

    protected GUID = "";

    public ModelReady?(Target: Model, Position: CFrame): void;

    public static readonly CachedInstances = new Map<string, BP_Structure>();

    public static HasSpaceUnder(Target: Model, Position: CFrame, Ignore?: Array<Instance>): boolean {
        return HasSpaceUnder(Target, Position, Ignore)
    }

    public static RunClientAction(id: string, guid: string) {
        const Registered = CreationActions.get(id)

        if (Registered !== undefined) {
            Registered(guid)
        }
    }

    public static LinkClientAction(this: typeof BP_Structure, Callback: (guid: string) => void) {
        CreationActions.set(this.StaticName, Callback)
    }

    public Ready(): void {
        super.Ready()

        if (!IsClient) {
            this.SetEnabled(true)
        }
    }

    public GetGUID(): string {
        return this.GUID
    }

    public RegisterModel(Target: Model, Position: CFrame, Owner?: Player) {
        this.Model = Target
        this.GUID = HttpService.GenerateGUID()

        Target.SetAttribute("Ready", false)
        Target.SetAttribute("id", this.ClassName)
        Target.SetAttribute("guid", this.GUID)
        Target.AddTag("BP_StructureInstance")

        if (Owner !== undefined) {
            this.SetOwner(Owner)
        }

        Target.Parent = StructureFolder

        if (this.ModelReady !== undefined) {
            this.ModelReady(Target, Position)
        } else {
            Target.PivotTo(Position)
            Target.SetAttribute("Ready", true)
        }
    }

    public SetOwner(Owner?: Player) {
        const Previous = this.Owner

        if (Previous === Owner) {
            return
        }

        if (Previous !== undefined) {
            const Released = OwnedStructures.get(Previous)

            if (Released !== undefined) {
                Released.delete(this.GUID)
            }
        }

        this.Owner = Owner

        const Held = this.Model as Model | undefined

        if (Held !== undefined) {
            Held.SetAttribute("owner", Owner !== undefined ? Owner.UserId : undefined)
        }

        if (Owner !== undefined) {
            const Existing = OwnedStructures.get(Owner)
            const Owned = Existing !== undefined ? Existing : new Map<string, BP_Structure>()

            if (Existing === undefined) {
                OwnedStructures.set(Owner, Owned)
            }

            Owned.set(this.GUID, this)
        }
    }

    public IsOwnedBy(Target: Player): boolean {
        return this.Owner === Target
    }

    protected OnDestroyed(): void {
        super.OnDestroyed()

        const Owner = this.Owner

        if (Owner !== undefined) {
            const Owned = OwnedStructures.get(Owner)

            if (Owned !== undefined) {
                Owned.delete(this.GUID)
            }

            this.Owner = undefined
        }

        const Held = this.Model as Model | undefined

        if (Held !== undefined) {
            Held.SetAttribute("Ready", false)
            task.defer(FadeAndClear, Held)
        }
    }
}
//-------------------------------------------------------------------- Boot
if (!IsClient) {
    const Made = new Instance("Folder")
    Made.Name = StructureFolder_Name
    Made.Parent = Workspace
    StructureFolder = Made

    const ReleaseOwned = (Leaving: Player) => {
        const Owned = OwnedStructures.get(Leaving)

        if (Owned === undefined) {
            return
        }

        OwnedStructures.delete(Leaving)

        for (const [, Held] of Owned) {
            if (!Held.Destroyed) {
                Held.Destroy()
            }
        }
    }

    Players.PlayerRemoving.Connect(ReleaseOwned)

    StructureSocket.On<[string]>("@Structure/Destroy", (Requester, guid) => {
        if (!typeIs(guid, "string")) {
            return
        }

        const Owned = OwnedStructures.get(Requester)

        if (Owned === undefined) {
            return
        }

        const Held = Owned.get(guid)

        if (Held === undefined || Held.Destroyed) {
            return
        }

        Held.Destroy()
    })
} else {
    const LocalPlayer = Players.LocalPlayer

    const AttachOwnerControls = (Inst: Instance): ClickDetector => {
        const Detector = new Instance("ClickDetector")
        Detector.Name = "BP_OwnerControls"
        Detector.MaxActivationDistance = OwnerClick_Distance

        let Sent = false

        Detector.RightMouseClick.Connect((Clicker) => {
            if (Sent || Clicker !== LocalPlayer) {
                return
            }

            Sent = true

            StructureSocket.Emit("@Structure/Destroy", Inst.GetAttribute("guid"))
        })

        Detector.Parent = Inst

        return Detector
    }

    const WatchOwnership = (Inst: Instance) => {
        let Detector: ClickDetector | undefined = undefined

        const Sync = () => {
            const Owns = Inst.GetAttribute("owner") === LocalPlayer.UserId

            if (Owns && Detector === undefined) {
                Detector = AttachOwnerControls(Inst)
            } else if (!Owns && Detector !== undefined) {
                Detector.Destroy()
                Detector = undefined
            }
        }

        Sync()
        Inst.GetAttributeChangedSignal("owner").Connect(Sync)
    }

    const Observe = (Inst: Instance) => {
        if (Inst.GetAttribute("Ready") !== true) {
            Inst.GetAttributeChangedSignal("Ready").Wait()
        }

        WatchOwnership(Inst)

        const id = Inst.GetAttribute("id")
        const guid = Inst.GetAttribute("guid")

        if (typeIs(id, "string") && typeIs(guid, "string")) {
            BP_Structure.RunClientAction(id, guid)
        }
    }

    const Existing = Workspace.FindFirstChild(StructureFolder_Name)
    const Found = Existing !== undefined ? Existing : Workspace.WaitForChild(StructureFolder_Name, StructureFolder_Timeout)

    if (Found === undefined) {
        warn(`[BP_Structure] '${StructureFolder_Name}' never replicated after ${StructureFolder_Timeout}s — structures will not be tracked`)
    } else {
        StructureFolder = Found as Folder

        StructureFolder.ChildAdded.Connect(Observe)

        for (const Inst of StructureFolder.GetChildren()) {
            task.spawn(Observe, Inst)
        }
    }

    StructureSocket.Init()
}
