//-------------------------------------------------------------------- SERVICES
import { TweenService, Workspace } from "@rbxts/services";
//-------------------------------------------------------------------- MODULES
import { RegisterClass } from "../Super/CommonInstance";
import { BP_Buildable } from "./BP_Buildable";
//-------------------------------------------------------------------- Topline VARS
const SegmentFolder_Name = "WallSegments"
const SEGMENT_PROCESS = "wall_segments"
const UNOWNED = 0

let SegmentFolderRef: Folder | undefined = undefined
let Relinking = false
//-------------------------------------------------------------------- Types
export interface WallSegment {
    Part: BasePart;
    A: BP_BuildableWall;
    B: BP_BuildableWall;
}

export type WallBucket = Array<BP_BuildableWall>;
export type WallOwners = Map<Player | number, WallBucket>;
export type WallLinkRegistry = Map<string, WallOwners>;

interface Candidate {
    Other: BP_BuildableWall;
    Distance: number;
}

const WallLinks: WallLinkRegistry = new Map<string, WallOwners>()
//-------------------------------------------------------------------- Helpers
function SegmentFolder(): Folder {
    const Cached = SegmentFolderRef

    if (Cached !== undefined && Cached.Parent !== undefined) {
        return Cached
    }

    let Found = Workspace.FindFirstChild(SegmentFolder_Name)

    if (Found === undefined) {
        const Made = new Instance("Folder")
        Made.Name = SegmentFolder_Name
        Made.Parent = Workspace
        Found = Made
    }

    SegmentFolderRef = Found as Folder

    return SegmentFolderRef
}

function WallAnchor(Target: Model, Height: number): Vector3 {
    const Pivot = Target.GetPivot().Position
    const [Bounds, Size] = Target.GetBoundingBox()
    const Bottom = Bounds.Position.Y - Size.Y / 2

    return new Vector3(Pivot.X, Bottom + Height / 2, Pivot.Z)
}

function PlanarDistance(A: Vector3, B: Vector3): number {
    const dx = A.X - B.X
    const dz = A.Z - B.Z

    return math.sqrt(dx * dx + dz * dz)
}

function FadeFactor(Endpoint: BP_BuildableWall, BlendStart: number): number {
    if (Endpoint.IsBuilt) {
        return 1
    }

    if (!Endpoint.IsBuilding) {
        return 0
    }

    const Progress = Endpoint.BuildProgress

    if (Progress <= BlendStart) {
        return 0
    }

    if (BlendStart >= 1) {
        return 1
    }

    return (Progress - BlendStart) / (1 - BlendStart)
}

function PartnerOf(Segment: WallSegment, SelfRef: BP_BuildableWall): BP_BuildableWall {
    if (Segment.A === SelfRef) {
        return Segment.B
    }

    return Segment.A
}
//-------------------------------------------------------------------- BP_BuildableWall
RegisterClass("BP_BuildableWall", "BP_Buildable")

export class BP_BuildableWall extends BP_Buildable {
    public static readonly StaticName: string = "BP_BuildableWall";
    public readonly ClassName: string = "BP_BuildableWall";

    public static readonly WallLinks = WallLinks;

    public WallThickness = 1;
    public WallHeight = 7;
    public WallColor = Color3.fromRGB(125, 125, 125);
    public WallMaterial: Enum.Material = Enum.Material.SmoothPlastic;
    public MaxLinkDistance = 30;
    public MaxLinks = 3;
    public RelinkOnPlace = true;
    public RelinkOnDestroy = true;
    public FadeTime = 1;

    public BuildTime = 2.5;
    public RunMono = false;

    protected _segments: Array<WallSegment> = [];
    protected _ownerKey: Player | number = UNOWNED;

    private BucketFor(Create: boolean): WallBucket | undefined {
        const ClassKey = this.ClassName
        let ByOwner = WallLinks.get(ClassKey)

        if (ByOwner === undefined) {
            if (!Create) {
                return undefined
            }

            ByOwner = new Map<Player | number, WallBucket>()
            WallLinks.set(ClassKey, ByOwner)
        }

        const OwnerKey = this._ownerKey
        let Bucket = ByOwner.get(OwnerKey)

        if (Bucket === undefined) {
            if (!Create) {
                return undefined
            }

            Bucket = []
            ByOwner.set(OwnerKey, Bucket)
        }

        return Bucket
    }

    private GatherLinkTargets(Bucket: WallBucket | undefined, OwnPos: Vector3, Budget: number): Array<Candidate> {
        const Candidates = new Array<Candidate>()

        if (Bucket === undefined || Budget <= 0) {
            return Candidates
        }

        const MaxDistance = this.MaxLinkDistance

        for (const Other of Bucket) {
            if (Other === this || Other.Destroyed) {
                continue
            }

            const Target = Other.Model as Model | undefined

            if (Target === undefined || Target.Parent === undefined) {
                continue
            }

            const Distance = PlanarDistance(Target.GetPivot().Position, OwnPos)

            if (Distance > MaxDistance) {
                continue
            }

            if (this.IsLinkedTo(Other)) {
                continue
            }

            Candidates.push({ Other: Other, Distance: Distance })
        }

        Candidates.sort((X, Y) => X.Distance < Y.Distance)

        while (Candidates.size() > Budget) {
            Candidates.pop()
        }

        return Candidates
    }

    public UpdateSegments() {
        const Thickness = this.WallThickness
        const Height = this.WallHeight
        const BlendStart = this.BlendStart
        const WallColor = this.WallColor
        const BuildColor = this.BuildColor
        const BuildTransparency = this.BuildTransparency

        for (const Segment of this._segments) {
            const Part = Segment.Part

            if (Part.Parent === undefined) {
                continue
            }

            const A = Segment.A
            const B = Segment.B
            const ModelA = A.Model as Model | undefined
            const ModelB = B.Model as Model | undefined

            if (A.Destroyed || B.Destroyed || ModelA === undefined || ModelB === undefined) {
                continue
            }

            const PointA = WallAnchor(ModelA, Height)
            const PointB = WallAnchor(ModelB, Height)
            const Length = PointB.sub(PointA).Magnitude

            if (Length > 0.05) {
                Part.Size = new Vector3(Thickness, Height, Length)
                Part.CFrame = CFrame.lookAt(PointA.Lerp(PointB, 0.5), PointB)
            }

            const Fade = math.min(FadeFactor(A, BlendStart), FadeFactor(B, BlendStart))

            if (Fade >= 1) {
                Part.Color = WallColor
                Part.Transparency = 0
                Part.CanCollide = true
            } else {
                Part.Color = BuildColor.Lerp(WallColor, Fade)
                Part.Transparency = BuildTransparency * (1 - Fade)
                Part.CanCollide = false
            }
        }
    }

    private LinkPass(): number {
        const Target = this.Model as Model | undefined

        if (this.Destroyed || Target === undefined) {
            return 0
        }

        const Budget = this.MaxLinks - this.OutboundCount()

        if (Budget <= 0) {
            return 0
        }

        const Bucket = this.BucketFor(true)
        const OwnPos = Target.GetPivot().Position
        const Candidates = this.GatherLinkTargets(Bucket, OwnPos, Budget)

        let Made = 0

        for (const Entry of Candidates) {
            const Other = Entry.Other

            const Part = new Instance("Part")
            Part.Name = "WallSegment"
            Part.Anchored = true
            Part.CanCollide = false
            Part.Color = this.BuildColor
            Part.Transparency = this.BuildTransparency
            Part.Size = new Vector3(this.WallThickness, this.WallHeight, 1)
            Part.Material = this.WallMaterial
            Part.Parent = SegmentFolder()

            const Segment: WallSegment = { Part: Part, A: Other, B: this }
            this._segments.push(Segment)
            Other.AttachSegment(Segment)
            Made += 1
        }

        if (Made > 0) {
            this.UpdateSegments()
        }

        return Made
    }

    private RegisterAndLink() {
        this._ownerKey = this.Owner !== undefined ? this.Owner : UNOWNED

        const Bucket = this.BucketFor(true)

        if (Bucket !== undefined) {
            Bucket.push(this)
        }

        this.LinkPass()

        if (this.RelinkOnPlace) {
            this.NotifyNeighbours()
        }
    }

    private Unregister() {
        const Bucket = this.BucketFor(false)

        if (Bucket === undefined) {
            return
        }

        for (let Index = 0; Index < Bucket.size(); Index++) {
            if (Bucket[Index] === this) {
                Bucket.remove(Index)
                break
            }
        }
    }

    private NotifyNeighbours() {
        if (Relinking) {
            return
        }

        const Target = this.Model as Model | undefined
        const Bucket = this.BucketFor(false)

        if (Target === undefined || Bucket === undefined) {
            return
        }

        Relinking = true

        const OwnPos = Target.GetPivot().Position
        const Reach = this.MaxLinkDistance

        for (const Other of [...Bucket]) {
            if (Other === this || Other.Destroyed) {
                continue
            }

            const OtherModel = Other.Model as Model | undefined

            if (OtherModel === undefined || OtherModel.Parent === undefined) {
                continue
            }

            if (PlanarDistance(OtherModel.GetPivot().Position, OwnPos) <= Reach) {
                Other.TopUpLinks()
            }
        }

        Relinking = false
    }

    private TopUpNeighbours() {
        if (this.RelinkOnDestroy !== true) {
            return
        }

        this.NotifyNeighbours()
    }

    private FadeSegment(Part: BasePart) {
        Part.CanCollide = false
        Part.Color = new Color3(0, 0, 0)

        const Motion = TweenService.Create(Part, new TweenInfo(this.FadeTime), { Transparency: 1 })

        Motion.Completed.Once(() => {
            Part.Destroy()
        })

        Motion.Play()
    }

    private DropSegments(Fade: boolean) {
        const Dropped = this._segments
        this._segments = []

        for (const Segment of Dropped) {
            Segment.A.DetachSegment(Segment)
            Segment.B.DetachSegment(Segment)

            if (Fade) {
                this.FadeSegment(Segment.Part)
            } else {
                Segment.Part.Destroy()
            }
        }
    }

    public ModelReady(Target: Model, Position: CFrame): void {
        this.AttachProcess(SEGMENT_PROCESS, () => this.UpdateSegments())

        super.ModelReady(Target, Position)

        this.RegisterAndLink()
    }

    public OnBuilt(): void {
        this.UpdateSegments()
        this.DetachProcess(SEGMENT_PROCESS)
    }

    public GetWalls(): Array<BasePart> {
        const Walls = new Array<BasePart>()

        for (const Segment of this._segments) {
            Walls.push(Segment.Part)
        }

        return Walls
    }

    public AttachSegment(Segment: WallSegment) {
        this._segments.push(Segment)
    }

    public DetachSegment(Segment: WallSegment) {
        const Segments = this._segments

        for (let Index = 0; Index < Segments.size(); Index++) {
            if (Segments[Index] === Segment) {
                Segments.remove(Index)
                break
            }
        }
    }

    public LinkCount(): number {
        return this._segments.size()
    }

    public OutboundCount(): number {
        let Count = 0

        for (const Segment of this._segments) {
            if (Segment.B === this) {
                Count += 1
            }
        }

        return Count
    }

    public IsLinkedTo(Other: BP_BuildableWall): boolean {
        for (const Segment of this._segments) {
            if (PartnerOf(Segment, this) === Other) {
                return true
            }
        }

        return false
    }

    public FarthestLinkDistance(): number {
        const Target = this.Model as Model | undefined

        if (Target === undefined) {
            return -1
        }

        const OwnPos = Target.GetPivot().Position
        let Worst = -1

        for (const Segment of this._segments) {
            const Partner = PartnerOf(Segment, this)
            const PartnerModel = Partner.Model as Model | undefined

            if (PartnerModel !== undefined) {
                const Distance = PlanarDistance(PartnerModel.GetPivot().Position, OwnPos)

                if (Distance > Worst) {
                    Worst = Distance
                }
            }
        }

        return Worst
    }

    public DropFarthestLink(): BP_BuildableWall | undefined {
        const Target = this.Model as Model | undefined

        if (Target === undefined) {
            return undefined
        }

        const OwnPos = Target.GetPivot().Position
        let WorstIndex: number | undefined = undefined
        let Worst = -1

        for (let Index = 0; Index < this._segments.size(); Index++) {
            const Segment = this._segments[Index]
            const Partner = PartnerOf(Segment, this)
            const PartnerModel = Partner.Model as Model | undefined

            if (PartnerModel !== undefined) {
                const Distance = PlanarDistance(PartnerModel.GetPivot().Position, OwnPos)

                if (Distance > Worst) {
                    Worst = Distance
                    WorstIndex = Index
                }
            }
        }

        if (WorstIndex === undefined) {
            return undefined
        }

        const Segment = this._segments.remove(WorstIndex) as WallSegment
        const Partner = PartnerOf(Segment, this)

        Partner.DetachSegment(Segment)
        Segment.Part.Destroy()

        return Partner
    }

    public TopUpLinks() {
        this.LinkPass()
    }

    public Relink() {
        if (this.Destroyed) {
            return
        }

        this.LinkPass()
        this.UpdateSegments()
    }

    protected OnDestroyed(): void {
        super.OnDestroyed()

        this.Unregister()
        this.DropSegments(this.IsBuilt)
        this.TopUpNeighbours()
    }
}
