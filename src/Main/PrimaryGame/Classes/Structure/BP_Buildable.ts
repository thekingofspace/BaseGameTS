//-------------------------------------------------------------------- MODULES
import Signal from "@shared/signal";
import { RegisterClass } from "../Super/CommonInstance";
import { BP_Structure } from "./BP_Structure";
//-------------------------------------------------------------------- Topline VARS
const MIN_BUILD_TIME = 1 / 60
const DEFAULT_BUILD_COLOR = Color3.fromRGB(63, 149, 255)
//-------------------------------------------------------------------- Types
export interface Look {
    Instance: BasePart | Decal;
    Color?: Color3;
    Transparency: number;
    Anchored?: boolean;
    CanCollide?: boolean;
    Hidden: boolean;
}
//-------------------------------------------------------------------- Easing
function Lerp(From: number, To: number, Alpha: number): number {
    return From + (To - From) * Alpha
}

function EaseOut(Alpha: number): number {
    const Inverse = 1 - Alpha

    return 1 - Inverse * Inverse * Inverse
}
//-------------------------------------------------------------------- BP_Buildable
RegisterClass("BP_Buildable", "BP_Structure")

export class BP_Buildable extends BP_Structure {
    public static readonly StaticName: string = "BP_Buildable";
    public readonly ClassName: string = "BP_Buildable";

    public BuildTime = 3;
    public BuildColor = DEFAULT_BUILD_COLOR;
    public BuildTransparency = 0.6;
    public BlendStart = 0.7;
    public BuildDepth = 0;
    public BuildPadding = 2;
    public FreezeWhileBuilding = true;
    public RunMono = false;

    public BuildProgress = 0;
    public IsBuilding = false;
    public IsBuilt = false;

    public readonly BuildStarted: Signal.Signal<[]> = Signal.new<[]>("Deffered");
    public readonly BuildCompleted: Signal.Signal<[]> = Signal.new<[]>("Deffered");

    public Tick?(delta: number): void;
    public OnBuilt?(): void;

    protected _looks: Array<Look> = [];
    protected _origin = CFrame.identity;
    protected _target = CFrame.identity;
    protected _elapsed = 0;

    private CaptureLooks() {
        const Looks = this._looks
        Looks.clear()

        for (const Item of this.Model.GetDescendants()) {
            if (Item.IsA("BasePart")) {
                Looks.push({
                    Instance: Item,
                    Color: Item.Color,
                    Transparency: Item.Transparency,
                    Anchored: Item.Anchored,
                    CanCollide: Item.CanCollide,
                    Hidden: false
                })
            } else if (Item.IsA("Decal")) {
                Looks.push({
                    Instance: Item,
                    Transparency: Item.Transparency,
                    Hidden: true
                })
            }
        }
    }

    private ApplyLooks(Alpha: number) {
        const BuildColor = this.BuildColor
        const BuildTransparency = this.BuildTransparency

        for (const Held of this._looks) {
            if (Held.Hidden) {
                const Face = Held.Instance as Decal
                Face.Transparency = Lerp(1, Held.Transparency, Alpha)
            } else {
                const Part = Held.Instance as BasePart
                Part.Color = BuildColor.Lerp(Held.Color as Color3, Alpha)
                Part.Transparency = Lerp(math.max(BuildTransparency, Held.Transparency), Held.Transparency, Alpha)
            }
        }
    }

    private RestoreLooks() {
        const Freeze = this.FreezeWhileBuilding

        for (const Held of this._looks) {
            if (Held.Hidden) {
                const Face = Held.Instance as Decal
                Face.Transparency = Held.Transparency
            } else {
                const Part = Held.Instance as BasePart
                Part.Color = Held.Color as Color3
                Part.Transparency = Held.Transparency

                if (Freeze) {
                    Part.Anchored = Held.Anchored as boolean
                    Part.CanCollide = Held.CanCollide as boolean
                }
            }
        }

        this._looks.clear()
    }

    private BlendAlpha(Progress: number): number {
        const Start = math.clamp(this.BlendStart, 0, 1)

        if (Progress <= Start) {
            return 0
        }

        if (Start >= 1) {
            return 1
        }

        return math.clamp((Progress - Start) / (1 - Start), 0, 1)
    }

    protected FinishBuild() {
        this.IsBuilding = false
        this.IsBuilt = true
        this.BuildProgress = 1

        this.Model.PivotTo(this._target)
        this.Model.SetAttribute("Ready", true)
        this.RestoreLooks()

        if (this.OnBuilt !== undefined) {
            const [Ok, Err] = pcall(() => this.OnBuilt?.())

            if (!Ok) {
                task.spawn(() => error(Err))
            }
        }

        if (this.Destroyed) {
            return
        }

        this.BuildCompleted.Fire()

        if (this.Destroyed) {
            return
        }

        if (!this.RunMono) {
            this.SetEnabled(false)
        }
    }

    protected BeginBuild(Position: CFrame) {
        const Target = this.Model

        this._target = Position
        this._elapsed = 0
        this.BuildProgress = 0
        this.IsBuilt = false

        Target.PivotTo(Position)

        let Depth = this.BuildDepth

        if (Depth <= 0) {
            Depth = Target.GetExtentsSize().Y + this.BuildPadding
        }

        this._origin = Position.add(new Vector3(0, -Depth, 0))

        this.CaptureLooks()

        if (this.FreezeWhileBuilding) {
            for (const Held of this._looks) {
                if (!Held.Hidden) {
                    const Part = Held.Instance as BasePart
                    Part.Anchored = true
                    Part.CanCollide = false
                }
            }
        }

        if (this.BuildTime <= 0) {
            this.IsBuilding = true
            this.FinishBuild()
            return
        }

        Target.PivotTo(this._origin)
        this.ApplyLooks(0)

        this.IsBuilding = true
        this.BuildStarted.Fire()
    }

    public ModelReady(Target: Model, Position: CFrame): void {
        this.BeginBuild(Position)
    }

    public SkipBuild() {
        if (this.IsBuilt || !this.IsBuilding) {
            return
        }

        this.FinishBuild()
    }

    public Update(delta: number): void {
        if (this.IsBuilding) {
            this._elapsed += delta

            const Duration = math.max(this.BuildTime, MIN_BUILD_TIME)
            const Progress = math.clamp(this._elapsed / Duration, 0, 1)
            this.BuildProgress = Progress

            this.Model.PivotTo(this._origin.Lerp(this._target, EaseOut(Progress)))
            this.ApplyLooks(this.BlendAlpha(Progress))

            if (Progress >= 1) {
                this.FinishBuild()
            }

            return
        }

        if (!this.IsBuilt || !this.RunMono) {
            return
        }

        this.Tick?.(delta)
    }

    protected OnDestroyed(): void {
        super.OnDestroyed()

        if (this.IsBuilding) {
            this.IsBuilding = false
            this.RestoreLooks()
        }

        this._looks.clear()

        this.BuildStarted.Destroy()
        this.BuildCompleted.Destroy()
    }
}
