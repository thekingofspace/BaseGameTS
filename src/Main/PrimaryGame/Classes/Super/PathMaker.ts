//-------------------------------------------------------------------- SERVICES
import { PathfindingService, Workspace } from "@rbxts/services";
//-------------------------------------------------------------------- Topline VARS
const PROBE_UP = 5
const PROBE_DOWN = 160

const SEARCH_RINGS = [4, 8, 12, 16, 20, 24, 28, 32]
const SEARCH_SPOKES = 12
const SEARCH_BUCKET = 4
const SEARCH_TRIES = 16
const MAX_CLIMB = 64
const FLY_STEP = 2
const FLY_MAX_STEPS = 512
const FLY_SIMPLIFY = 0.35
const RESUME_EVERY = 4
const RESUME_TRIES = 8

const SNAP_UP = 2
const SNAP_DOWN = 2.5
const CLIP_LIFT = 0.5
const CLIP_SKIN = 0.5
const DECLIP_DEPTH = 6
const PROBE_NUDGE = 0.15
const SUPPORT_STEP = 2
const SUPPORT_HEIGHT = 2.5

const DROP_BUDGET = 16
const MAX_WALK_SLOPE = math.rad(60)

const WATER_PROBE = 20
const FLUSH_LINKS = 8
//-------------------------------------------------------------------- Types
export interface Options {
    CanFly?: boolean;
    OnWater?: boolean;
    Offset?: number;
    Clearance?: number;
    Ignore?: Array<Instance>;
    AgentRadius?: number;
    AgentHeight?: number;
    AgentCanJump?: boolean;
    AgentCanClimb?: boolean;
    WaypointSpacing?: number;
    Costs?: Record<string, number>;
}

export interface PathModes {
    Ground?: boolean;
    Air?: boolean;
    Water?: boolean;
}

export interface StageResult {
    Points: Array<Vector3>;
    Whole: boolean;
}

export interface CarryResult {
    Points?: Array<Vector3>;
    Ok: boolean;
}

export interface LinkResult {
    Hit?: Vector3;
    FromFar: boolean;
}

export type Stage = (Self: PathMaker, Anchor: Vector3, Points: Array<Vector3>) => StageResult;
export type Extend = (Self: PathMaker, From: Vector3, To: Vector3, Points?: Array<Vector3>) => CarryResult;

export interface PathTrait {
    Name: string;
    Modes?: PathModes;
    PreClip?: Array<Stage>;
    PostClip?: Array<Stage>;
    Final?: Array<Stage>;
    Extend?: Array<Extend>;
}

interface Leg {
    Goal: Vector3;
    Reached: boolean;
    Count: number;
}
//-------------------------------------------------------------------- Helpers
function Lerp(A: number, B: number, T: number): number {
    return A + (B - A) * T
}

function RollingMax(Heights: Array<number>, Index: number, Window: number): number {
    let Best = Heights[Index]

    const Start = math.max(0, Index - Window)
    const Finish = math.min(Heights.size() - 1, Index + Window)

    for (let Scan = Start; Scan <= Finish; Scan++) {
        if (Heights[Scan] > Best) {
            Best = Heights[Scan]
        }
    }

    return Best
}

export function ComputeBest(Self: PathMaker, From: Vector3, To: Vector3): CarryResult {
    const Direct = Self.ComputeGround(From, To)

    if (Direct.Ok) {
        return Direct
    }

    const Candidates = new Array<Vector3>()

    for (let Ring = 1; Ring <= SEARCH_RINGS.size(); Ring++) {
        const Radius = SEARCH_RINGS[Ring - 1]

        for (let Spoke = 1; Spoke <= SEARCH_SPOKES; Spoke++) {
            const Angle = (Spoke / SEARCH_SPOKES) * math.pi * 2 + Ring * 0.37
            const Spot = To.add(new Vector3(math.cos(Angle) * Radius, 0, math.sin(Angle) * Radius))

            Candidates.push(Self.SnapDown(Spot))
        }
    }

    Candidates.sort((A, B) => {
        const NearA = math.round(A.sub(To).Magnitude / SEARCH_BUCKET)
        const NearB = math.round(B.sub(To).Magnitude / SEARCH_BUCKET)

        if (NearA !== NearB) {
            return NearA < NearB
        }

        return A.sub(From).Magnitude < B.sub(From).Magnitude
    })

    const Tries = math.min(Candidates.size(), SEARCH_TRIES)

    for (let Index = 0; Index < Tries; Index++) {
        const Fallback = Self.ComputeGround(From, Candidates[Index])

        if (Fallback.Ok) {
            return { Points: Fallback.Points, Ok: false }
        }
    }

    return { Points: undefined, Ok: false }
}

export function FlyLeg(Self: PathMaker, From: Vector3, To: Vector3): CarryResult {
    const Flat = new Vector3(To.X - From.X, 0, To.Z - From.Z)
    const Distance = Flat.Magnitude

    if (Distance < 1e-3) {
        return { Points: [To], Ok: true }
    }

    const Steps = math.clamp(math.ceil(Distance / FLY_STEP), 1, FLY_MAX_STEPS)
    const Direction = Flat.Unit
    const TopY = math.max(From.Y, To.Y) + MAX_CLIMB
    const BottomY = math.min(From.Y, To.Y) - PROBE_DOWN

    const Samples = new Array<Vector3>()
    const Heights = new Array<number>()

    for (let Step = 0; Step <= Steps; Step++) {
        const Alpha = Step / Steps
        const Point = From.add(Direction.mul(Distance * Alpha))
        const Ground = Self.SurfaceY(Point.X, Point.Z, TopY, BottomY)

        Samples[Step] = Point
        Heights[Step] = Ground !== undefined ? Ground : Lerp(From.Y, To.Y, Alpha) - Self.Clearance
    }

    const Radius = Self.Agent.AgentRadius !== undefined ? Self.Agent.AgentRadius : 2
    const Window = math.max(1, math.ceil((Radius + FLY_STEP) / FLY_STEP))
    const Altitudes = new Array<number>()

    for (let Index = 0; Index <= Steps; Index++) {
        Altitudes[Index] = RollingMax(Heights, Index, Window) + Self.Clearance
    }

    const Points = new Array<Vector3>()
    let KeptAt = 0
    let Airborne = false
    let Peak = Heights[0]
    let Tries = 0

    for (let Index = 1; Index <= Steps; Index++) {
        const Sample = Samples[Index]
        const Altitude = Altitudes[Index]
        const Surface = Heights[Index]
        const Hugging = Altitude <= Surface + Self.Clearance + 1e-3

        if (!Hugging) {
            Airborne = true
        }

        if (Surface > Peak) {
            Peak = Surface
        }

        const Landed = Airborne && Hugging && Surface < Peak - Self.Clearance
        const Ordinal = Index + 1

        if (Landed && Tries < RESUME_TRIES && (Ordinal % RESUME_EVERY === 0 || Index === Steps)) {
            Tries += 1

            const Landing = new Vector3(Sample.X, Surface, Sample.Z)
            const Ground = Self.ComputeGround(Landing, To)

            if (Ground.Ok && Ground.Points !== undefined) {
                Points.push(new Vector3(Sample.X, Altitude, Sample.Z))
                Points.push(Landing)

                for (const Item of Ground.Points) {
                    Points.push(Item)
                }

                return { Points: Points, Ok: true }
            }
        }

        const Ahead = Index + 1 <= Steps ? Altitudes[Index + 1] : undefined
        const MidRun = Ahead !== undefined
            && math.abs(Altitude - Altitudes[KeptAt]) <= FLY_SIMPLIFY
            && math.abs(Ahead - Altitude) <= FLY_SIMPLIFY

        if (!MidRun) {
            Points.push(new Vector3(Sample.X, Altitude, Sample.Z))
            KeptAt = Index
        }
    }

    Points.push(To)

    return { Points: Points, Ok: true }
}

function FarLip(Self: PathMaker, Start: Vector3, B: Vector3, Top: number): Vector3 | undefined {
    const Flat = new Vector3(B.X - Start.X, 0, B.Z - Start.Z)
    const Span = Flat.Magnitude

    if (Span < 1e-3) {
        return undefined
    }

    const Direction = Flat.div(Span)

    const OnTop = (Distance: number) => {
        const Probe = Start.add(Direction.mul(Distance))

        return Self.SurfaceY(Probe.X, Probe.Z, Top + PROBE_UP, Top - 1) !== undefined
    }

    let Good = 0
    let Bad: number | undefined = undefined
    let Distance = 1

    while (Distance < Span) {
        if (OnTop(Distance)) {
            Good = Distance
        } else {
            Bad = Distance
            break
        }

        Distance += 1
    }

    if (Bad === undefined) {
        if (OnTop(Span)) {
            return undefined
        }

        Bad = Span
    }

    let Low: number = Good
    let High: number = Bad

    for (let Pass = 0; Pass < 8; Pass++) {
        const Half: number = (Low + High) / 2

        if (OnTop(Half)) {
            Low = Half
        } else {
            High = Half
        }
    }

    if (Low <= 0) {
        return undefined
    }

    const Probe = Start.add(Direction.mul(Low))
    const Y = Self.SurfaceY(Probe.X, Probe.Z, Top + PROBE_UP, Top - 1)

    return new Vector3(Probe.X, Y !== undefined ? Y : Top, Probe.Z)
}

function Resolve(Self: PathMaker, A: Vector3, B: Vector3, Depth: number, Out: Array<Vector3>): boolean {
    const Link = Self.LinkHit(A, B)

    if (Link.Hit === undefined) {
        if (Self.PointBuried(B)) {
            return false
        }

        Out.push(B)

        return true
    }

    if (Depth <= 0) {
        return false
    }

    const Hit = Link.Hit
    const Flat = new Vector3(B.X - A.X, 0, B.Z - A.Z)
    const Inward = Flat.Magnitude > 1e-3
        ? Flat.Unit.mul(Link.FromFar ? -PROBE_NUDGE : PROBE_NUDGE)
        : Vector3.zero

    const Top = Self.SurfaceY(Hit.X + Inward.X, Hit.Z + Inward.Z, math.max(A.Y, B.Y) + MAX_CLIMB, Hit.Y - 1)

    if (Top === undefined) {
        return false
    }

    let Mid = new Vector3(Hit.X, Top, Hit.Z)

    if (Mid.sub(B).Magnitude <= CLIP_SKIN) {
        return false
    }

    if (Mid.sub(A).Magnitude <= CLIP_SKIN) {
        const Lip = FarLip(Self, Mid, B, Top)

        if (Lip === undefined || Lip.sub(A).Magnitude <= CLIP_SKIN) {
            return false
        }

        Mid = Lip
    }

    return Resolve(Self, A, Mid, Depth - 1, Out) && Resolve(Self, Mid, B, Depth - 1, Out)
}

function DeClip(Self: PathMaker, Anchor: Vector3, Points: Array<Vector3>): StageResult {
    const Out = new Array<Vector3>()
    let Previous = Anchor

    for (const Target of Points) {
        if (!Resolve(Self, Previous, Target, DECLIP_DEPTH, Out)) {
            return { Points: Out, Whole: false }
        }

        Previous = Target
    }

    return { Points: Out, Whole: true }
}

export function GateSlope(Self: PathMaker, Anchor: Vector3, Points: Array<Vector3>): StageResult {
    let Previous = Anchor

    for (let Index = 0; Index < Points.size(); Index++) {
        const Point = Points[Index]
        const Delta = Point.sub(Previous)
        const Flat = new Vector3(Delta.X, 0, Delta.Z).Magnitude
        let Breaks = false

        if (Delta.Y > -CLIP_LIFT) {
            Breaks = Delta.Y > CLIP_LIFT && math.atan2(Delta.Y, Flat) > MAX_WALK_SLOPE

            if (!Breaks) {
                const Steps = math.max(1, math.ceil(Delta.Magnitude / SUPPORT_STEP))

                for (let Step = 1; Step < Steps; Step++) {
                    const Sample = Previous.add(Delta.mul(Step / Steps))
                    const Ground = Self.SurfaceY(Sample.X, Sample.Z, Sample.Y + 1, Sample.Y - (SUPPORT_HEIGHT + 1))

                    if (Ground === undefined || Sample.Y - Ground > SUPPORT_HEIGHT) {
                        Breaks = true
                        break
                    }
                }
            }
        }

        if (Breaks) {
            const Kept = new Array<Vector3>()

            for (let Scan = 0; Scan < Index; Scan++) {
                Kept.push(Points[Scan])
            }

            return { Points: Kept, Whole: false }
        }

        Previous = Point
    }

    return { Points: Points, Whole: true }
}

function SquareDrops(Self: PathMaker, Anchor: Vector3, Points: Array<Vector3>): Array<Vector3> {
    const Out = new Array<Vector3>()
    let Previous = Anchor
    let Budget = DROP_BUDGET
    let Index = 0

    while (Index < Points.size()) {
        const Point = Points[Index]
        const Drop = Previous.Y - Point.Y
        const Flat = new Vector3(Point.X - Previous.X, 0, Point.Z - Previous.Z)
        let Reshaped = false

        if (Budget > 0 && Drop > SUPPORT_HEIGHT && Flat.Magnitude > 1) {
            const Direction = Flat.Unit
            const GroundA = Self.SurfaceY(
                Previous.X - Direction.X * PROBE_NUDGE,
                Previous.Z - Direction.Z * PROBE_NUDGE,
                Previous.Y + 1,
                Previous.Y - (SUPPORT_HEIGHT + 1)
            )

            if (GroundA !== undefined) {
                const Hover = math.max(Previous.Y - GroundA, 0)
                const Ahead = Self.SurfaceY(
                    Previous.X + Direction.X * PROBE_NUDGE * 2,
                    Previous.Z + Direction.Z * PROBE_NUDGE * 2,
                    GroundA + PROBE_UP,
                    GroundA - 1
                )

                const Lip = Ahead === undefined
                    ? new Vector3(Previous.X, GroundA, Previous.Z)
                    : FarLip(Self, new Vector3(Previous.X, GroundA, Previous.Z), Point, GroundA)

                if (Lip !== undefined) {
                    const DropX = Lip.X + Direction.X * PROBE_NUDGE * 2
                    const DropZ = Lip.Z + Direction.Z * PROBE_NUDGE * 2
                    const Lower = Self.SurfaceY(DropX, DropZ, Lip.Y - 0.1, Lip.Y - PROBE_DOWN)

                    if (Lower !== undefined && Lip.Y - Lower > SUPPORT_HEIGHT) {
                        Budget -= 1
                        Reshaped = true

                        if (new Vector3(Lip.X - Previous.X, 0, Lip.Z - Previous.Z).Magnitude > 0.05) {
                            Out.push(new Vector3(Lip.X, Lip.Y + Hover, Lip.Z))
                        }

                        const Landing = new Vector3(DropX, Lower + Hover, DropZ)
                        Out.push(Landing)
                        Previous = Landing
                    }
                }
            }
        }

        if (!Reshaped) {
            Out.push(Point)
            Previous = Point
            Index += 1
        }
    }

    return Out
}

function PinToWater(Self: PathMaker, Point: Vector3): Vector3 | undefined {
    const Hit = Workspace.Raycast(
        new Vector3(Point.X, Point.Y + WATER_PROBE, Point.Z),
        new Vector3(0, -(WATER_PROBE + PROBE_DOWN), 0),
        Self.RayParams
    )

    if (Hit === undefined || Hit.Material !== Enum.Material.Water) {
        return undefined
    }

    return new Vector3(Point.X, Hit.Position.Y, Point.Z)
}

export function GateWater(Self: PathMaker, _Anchor: Vector3, Points: Array<Vector3>): StageResult {
    for (let Index = 0; Index < Points.size(); Index++) {
        const Pinned = PinToWater(Self, Points[Index])

        if (Pinned === undefined) {
            const Kept = new Array<Vector3>()

            for (let Scan = 0; Scan < Index; Scan++) {
                Kept.push(Points[Scan])
            }

            return { Points: Kept, Whole: false }
        }

        Points[Index] = Pinned
    }

    return { Points: Points, Whole: true }
}
//-------------------------------------------------------------------- PathMaker
export class PathMaker {
    public Offset = 0;
    public Clearance = 2;
    public Modes: PathModes = {};

    public RayParams = new RaycastParams();
    public Overlap = new OverlapParams();
    public Agent: AgentParameters = {
        AgentRadius: 2,
        AgentHeight: 5,
        WaypointSpacing: 4
    };

    protected _stages = {
        PreClip: new Array<Stage>(),
        PostClip: new Array<Stage>(),
        Final: new Array<Stage>()
    };

    protected _extend = new Array<Extend>();

    private Points = new Array<Vector3>();
    private Legs = new Array<Leg>();
    private Cursor = 0;
    private Sweep = 0;
    private Rebuilding = false;
    private Origin = Vector3.zero;
    private Path?: Path;
    private PathFor?: boolean;

    constructor(...Traits: Array<PathTrait>) {
        this.RayParams.FilterType = Enum.RaycastFilterType.Exclude
        this.RayParams.FilterDescendantsInstances = []
        this.RayParams.IgnoreWater = false

        this.Overlap.FilterType = Enum.RaycastFilterType.Exclude
        this.Overlap.FilterDescendantsInstances = []

        for (const Trait of Traits) {
            this.Use(Trait)
        }
    }

    public Use(Trait: PathTrait): this {
        const Modes = Trait.Modes

        if (Modes !== undefined) {
            if (Modes.Ground !== undefined) {
                this.Modes.Ground = Modes.Ground
            }

            if (Modes.Air !== undefined) {
                this.Modes.Air = Modes.Air
            }

            if (Modes.Water !== undefined) {
                this.Modes.Water = Modes.Water
            }
        }

        if (Trait.PreClip !== undefined) {
            for (const Gate of Trait.PreClip) {
                this._stages.PreClip.push(Gate)
            }
        }

        if (Trait.PostClip !== undefined) {
            for (const Gate of Trait.PostClip) {
                this._stages.PostClip.push(Gate)
            }
        }

        if (Trait.Final !== undefined) {
            for (const Gate of Trait.Final) {
                this._stages.Final.push(Gate)
            }
        }

        if (Trait.Extend !== undefined) {
            for (const Carry of Trait.Extend) {
                this._extend.push(Carry)
            }
        }

        return this
    }

    public CanFly(): boolean {
        return this.Modes.Air === true
    }

    public SetCanFly(Value: boolean) {
        this.Modes.Air = Value === true
    }

    public OnWater(): boolean {
        return this.Modes.Water === true
    }

    public SetOnWater(Value: boolean) {
        this.Modes.Water = Value === true
    }

    public SurfaceY(X: number, Z: number, TopY: number, BottomY: number): number | undefined {
        const Hit = Workspace.Raycast(new Vector3(X, TopY, Z), new Vector3(0, BottomY - TopY, 0), this.RayParams)

        return Hit !== undefined ? Hit.Position.Y : undefined
    }

    public SnapDown(Position: Vector3): Vector3 {
        const Y = this.SurfaceY(Position.X, Position.Z, Position.Y + PROBE_UP, Position.Y - PROBE_DOWN)

        return Y !== undefined ? new Vector3(Position.X, Y, Position.Z) : Position
    }

    public SnapToSurface(Point: Vector3): Vector3 {
        const Y = this.SurfaceY(Point.X, Point.Z, Point.Y + SNAP_UP, Point.Y - SNAP_DOWN)

        return Y !== undefined ? new Vector3(Point.X, Y, Point.Z) : Point
    }

    public LinkHit(A: Vector3, B: Vector3): LinkResult {
        const Lift = new Vector3(0, CLIP_LIFT, 0)
        const From = A.add(Lift)
        const Delta = B.add(Lift).sub(From)
        const Span = Delta.Magnitude

        if (Span <= CLIP_SKIN * 2) {
            return { Hit: undefined, FromFar: false }
        }

        const Direction = Delta.div(Span)
        const Reach = Direction.mul(Span - CLIP_SKIN * 2)
        const Forward = Workspace.Raycast(From.add(Direction.mul(CLIP_SKIN)), Reach, this.RayParams)

        if (Forward !== undefined) {
            return { Hit: Forward.Position, FromFar: false }
        }

        const Backward = Workspace.Raycast(From.add(Direction.mul(Span - CLIP_SKIN)), Reach.mul(-1), this.RayParams)

        return { Hit: Backward !== undefined ? Backward.Position : undefined, FromFar: true }
    }

    public PointBuried(Point: Vector3): boolean {
        const Hits = Workspace.GetPartBoundsInBox(
            new CFrame(Point.add(new Vector3(0, CLIP_LIFT, 0))),
            Vector3.one.mul(0.1),
            this.Overlap
        )

        return Hits.size() > 0
    }

    public ComputeGround(From: Vector3, To: Vector3): CarryResult {
        const Route = this.EnsurePath()
        const [Ok] = pcall(() => Route.ComputeAsync(From, To))

        if (!Ok || Route.Status !== Enum.PathStatus.Success) {
            return { Points: undefined, Ok: false }
        }

        const Points = this.WaypointsToPoints(Route.GetWaypoints())

        if (Points.size() === 0) {
            Points.push(To)
        }

        return { Points: Points, Ok: true }
    }

    private WaypointsToPoints(Waypoints: Array<PathWaypoint>): Array<Vector3> {
        const Points = new Array<Vector3>()

        for (let Index = 1; Index < Waypoints.size(); Index++) {
            Points.push(this.SnapToSurface(Waypoints[Index].Position))
        }

        return Points
    }

    private EnsurePath(): Path {
        if (this.PathFor === this.CanFly() && this.Path !== undefined) {
            return this.Path
        }

        const Agent: AgentParameters = {
            AgentRadius: this.Agent.AgentRadius,
            AgentHeight: this.Agent.AgentHeight,
            AgentCanJump: this.Agent.AgentCanJump !== undefined ? this.Agent.AgentCanJump : this.CanFly(),
            AgentCanClimb: this.Agent.AgentCanClimb !== undefined ? this.Agent.AgentCanClimb : this.CanFly(),
            WaypointSpacing: this.Agent.WaypointSpacing,
            Costs: this.Agent.Costs
        }

        this.PathFor = this.CanFly()
        this.Path = PathfindingService.CreatePath(Agent)

        return this.Path
    }

    private LastPoint(): Vector3 {
        return this.Points.size() > 0 ? this.Points[this.Points.size() - 1] : this.Origin
    }

    private RunStage(Gates: Array<Stage>, Anchor: Vector3, Points: Array<Vector3>): StageResult {
        let Current = Points
        let Cut = false

        for (const Gate of Gates) {
            const Result = Gate(this, Anchor, Current)
            Current = Result.Points

            if (!Result.Whole) {
                Cut = true
            }
        }

        return { Points: Current, Whole: !Cut }
    }

    private BuildLeg(From: Vector3, To: Vector3): CarryResult {
        const Best = ComputeBest(this, From, To)

        if (Best.Ok) {
            return Best
        }

        for (const Carry of this._extend) {
            const Carried = Carry(this, From, To, Best.Points)

            if (Carried.Ok) {
                return { Points: Carried.Points, Ok: true }
            }
        }

        return Best
    }

    private Rebuild(): boolean {
        const Here = this.Cursor > 0 ? this.Points[this.Cursor - 1] : this.Origin
        const Goals = new Array<Vector3>()
        let Walked = 0

        for (const Leg of this.Legs) {
            if (Walked + Leg.Count > this.Cursor) {
                Goals.push(Leg.Goal)
            }

            Walked += Leg.Count
        }

        this.Rebuilding = true
        this.SetOrigin(Here)

        for (const Goal of Goals) {
            this.Push(Goal)
        }

        this.Rebuilding = false

        return this.Points.size() > 0
    }

    public InitPath(Origin: Vector3, Options?: Options) {
        const Config: Options = Options !== undefined ? Options : {}
        const Ignore = Config.Ignore !== undefined ? Config.Ignore : []

        this.RayParams.FilterDescendantsInstances = Ignore
        this.Overlap.FilterDescendantsInstances = Ignore

        if (Config.CanFly !== undefined) {
            this.SetCanFly(Config.CanFly === true)
        }

        if (Config.OnWater !== undefined) {
            this.SetOnWater(Config.OnWater === true)
        }

        this.Offset = Config.Offset !== undefined ? Config.Offset : 0
        this.Clearance = Config.Clearance !== undefined ? Config.Clearance : 2

        this.Agent = {
            AgentRadius: Config.AgentRadius !== undefined ? Config.AgentRadius : 2,
            AgentHeight: Config.AgentHeight !== undefined ? Config.AgentHeight : 5,
            AgentCanJump: Config.AgentCanJump,
            AgentCanClimb: Config.AgentCanClimb,
            WaypointSpacing: Config.WaypointSpacing !== undefined ? Config.WaypointSpacing : 4,
            Costs: Config.Costs !== undefined ? Config.Costs : (this.OnWater() ? { Water: 0.5 } : undefined)
        }

        this.Path = undefined
        this.PathFor = undefined
        this.Clear()
        this.Origin = this.SnapDown(Origin)
    }

    public Push(Position: Vector3): boolean {
        const Goal = this.SnapDown(Position)
        const From = this.LastPoint()
        const Leg = this.BuildLeg(From, Goal)

        let Points = Leg.Points
        let Reached = Leg.Ok

        if (Points === undefined || Points.size() === 0) {
            return false
        }

        const Pre = this.RunStage(this._stages.PreClip, From, Points)
        Points = Pre.Points

        if (!Pre.Whole) {
            Reached = false
        }

        const Clean = DeClip(this, From, Points)
        Points = Clean.Points

        if (!Clean.Whole) {
            Reached = false
        }

        const Post = this.RunStage(this._stages.PostClip, From, Points)
        Points = Post.Points

        if (!Post.Whole) {
            Reached = false
        }

        Points = SquareDrops(this, From, Points)

        const Final = this.RunStage(this._stages.Final, From, Points)
        Points = Final.Points

        if (!Final.Whole) {
            Reached = false
        }

        if (Points.size() === 0) {
            return false
        }

        this.Legs.push({ Goal: Goal, Reached: Reached, Count: Points.size() })

        for (const Point of Points) {
            this.Points.push(Point)
        }

        return Reached
    }

    public Pop(): Vector3 | undefined {
        const Leg = this.Legs.pop()

        if (Leg === undefined) {
            return undefined
        }

        for (let Index = 0; Index < Leg.Count; Index++) {
            this.Points.pop()
        }

        if (this.Cursor > this.Points.size()) {
            this.Cursor = this.Points.size()
        }

        return Leg.Goal
    }

    public Next(): Vector3 | undefined {
        if (this.Rebuilding) {
            return undefined
        }

        for (let Attempt = 0; Attempt < 2; Attempt++) {
            if (this.Cursor >= this.Points.size()) {
                return undefined
            }

            const Here = this.Cursor > 0 ? this.Points[this.Cursor - 1] : this.Origin
            const Target = this.Points[this.Cursor]

            if (this.LinkHit(Here, Target).Hit === undefined && !this.PointBuried(Target)) {
                this.Cursor += 1

                return Target.add(new Vector3(0, this.Offset, 0))
            }

            if (!this.Rebuild()) {
                return undefined
            }
        }

        this.Clear()

        return undefined
    }

    public Peek(): Vector3 | undefined {
        if (this.Cursor >= this.Points.size()) {
            return undefined
        }

        return this.Points[this.Cursor].add(new Vector3(0, this.Offset, 0))
    }

    public Get(): Array<Vector3> {
        const Points = new Array<Vector3>()

        for (let Index = this.Cursor; Index < this.Points.size(); Index++) {
            Points.push(this.Points[Index].add(new Vector3(0, this.Offset, 0)))
        }

        return Points
    }

    public Flush(Force?: boolean): boolean {
        if (this.Rebuilding || this.Cursor >= this.Points.size()) {
            return false
        }

        let Stale = Force === true

        if (!Stale) {
            let Index = math.max(this.Sweep, this.Cursor)

            for (let Link = 0; Link < FLUSH_LINKS; Link++) {
                if (Index >= this.Points.size()) {
                    break
                }

                const From = Index > 0 ? this.Points[Index - 1] : this.Origin
                const Target = this.Points[Index]

                if (this.LinkHit(From, Target).Hit !== undefined || this.PointBuried(Target)) {
                    Stale = true
                    break
                }

                Index += 1
            }

            this.Sweep = Index >= this.Points.size() ? 0 : Index
        }

        if (!Stale) {
            return false
        }

        if (!this.Rebuild()) {
            this.Clear()
        }

        return true
    }

    public Finished(): boolean {
        return !this.Rebuilding && this.Cursor >= this.Points.size()
    }

    public Clear() {
        this.Points.clear()
        this.Legs.clear()
        this.Cursor = 0
        this.Sweep = 0
    }

    public SetOrigin(Position: Vector3) {
        this.Clear()
        this.Origin = this.SnapDown(Position)
    }

    public SetIgnore(Instances: Array<Instance>) {
        this.RayParams.FilterDescendantsInstances = Instances
        this.Overlap.FilterDescendantsInstances = Instances
    }
}
//-------------------------------------------------------------------- Traits
export const Grounded: PathTrait = {
    Name: "PathGrounded",
    Modes: { Ground: true },
    Final: [
        (Self, Anchor, Points) => {
            if (Self.CanFly()) {
                return { Points: Points, Whole: true }
            }

            return GateSlope(Self, Anchor, Points)
        }
    ]
}

export const Airborne: PathTrait = {
    Name: "PathAirborne",
    Modes: { Air: true },
    Extend: [
        (Self, From, To, Points) => {
            if (!Self.CanFly()) {
                return { Points: Points, Ok: false }
            }

            const Launch = Points !== undefined && Points.size() > 0 ? Points[Points.size() - 1] : From
            const Flight = FlyLeg(Self, Launch, To)

            if (!Flight.Ok || Flight.Points === undefined) {
                return { Points: Points, Ok: false }
            }

            const Merged = Points !== undefined ? Points : new Array<Vector3>()

            for (const Point of Flight.Points) {
                Merged.push(Point)
            }

            return { Points: Merged, Ok: true }
        }
    ]
}

export const Floating: PathTrait = {
    Name: "PathFloating",
    Modes: { Water: true },
    PreClip: [GateWater],
    PostClip: [GateWater]
}
