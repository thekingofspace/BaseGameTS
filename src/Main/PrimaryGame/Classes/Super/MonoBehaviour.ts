//-------------------------------------------------------------------- SERVICES
import { RunService } from "@rbxts/services";
//-------------------------------------------------------------------- MODULES
import Signal from "@shared/signal";
import { CommonInstance, RegisterClass } from "./CommonInstance";
//-------------------------------------------------------------------- Types
export type Process = (delta: number) => void;

export interface Connectable<T extends Array<unknown>> {
    Connect(sink: (...args: T) => void): defined;
}

interface InvokeRecord {
    Callback: () => void;
    At: number;
    Interval?: number;
}

interface ScheduleRecord {
    Callback: () => void;
    At: number;
}

interface Bucket {
    Items: Array<MonoBehaviour | false>;
    Slots: Map<MonoBehaviour, number>;
    Count: number;
    Holes: number;
    Connection?: RBXScriptConnection;
}

interface Group {
    Event: RBXScriptSignal<(delta: number) => void>;
    Step: (bucket: Bucket, delta: number) => void;
    Buckets: Array<Bucket>;
    Homes: Map<MonoBehaviour, Bucket>;
    Count: number;
}

type HookInvoke = (Self: MonoBehaviour, Delta: number) => void;
//-------------------------------------------------------------------- Topline VARS
const BUCKET_LIMIT = 40
//-------------------------------------------------------------------- Guarded calls
function RunGuarded(Body: () => void) {
    const [Ok, Err] = pcall(Body)

    if (!Ok) {
        task.spawn(() => error(Err))
    }
}
//-------------------------------------------------------------------- Buckets
function NewGroup(Event: RBXScriptSignal<(delta: number) => void>, Step: (bucket: Bucket, delta: number) => void): Group {
    return {
        Event: Event,
        Step: Step,
        Buckets: [],
        Homes: new Map<MonoBehaviour, Bucket>(),
        Count: 0
    }
}

function CompactBucket(Target: Bucket) {
    if (Target.Holes === 0) {
        return
    }

    const Items = Target.Items
    const Slots = Target.Slots
    let Write = 0

    for (let Read = 0; Read < Items.size(); Read++) {
        const Item = Items[Read]

        if (Item !== false) {
            Items[Write] = Item
            Slots.set(Item, Write)
            Write += 1
        }
    }

    for (let Index = Items.size(); Index > Write; Index--) {
        Items.pop()
    }

    Target.Holes = 0
}

function OpenBucket(Owner: Group): Bucket {
    const Fresh: Bucket = {
        Items: [],
        Slots: new Map<MonoBehaviour, number>(),
        Count: 0,
        Holes: 0
    }

    Owner.Buckets.push(Fresh)

    Fresh.Connection = Owner.Event.Connect((Delta) => {
        Owner.Step(Fresh, Delta)
    })

    return Fresh
}

function CloseBucket(Owner: Group, Target: Bucket) {
    const Link = Target.Connection
    Target.Connection = undefined

    if (Link !== undefined) {
        Link.Disconnect()
    }

    Target.Items.clear()
    Target.Slots.clear()
    Target.Holes = 0

    const Buckets = Owner.Buckets

    for (let Index = Buckets.size() - 1; Index >= 0; Index--) {
        if (Buckets[Index] === Target) {
            Buckets.remove(Index)
            break
        }
    }
}

function GroupAdd(Owner: Group, Item: MonoBehaviour) {
    if (Owner.Homes.has(Item)) {
        return
    }

    let Target: Bucket | undefined = undefined

    for (const Candidate of Owner.Buckets) {
        if (Candidate.Count < BUCKET_LIMIT) {
            Target = Candidate
            break
        }
    }

    const Chosen = Target !== undefined ? Target : OpenBucket(Owner)
    const Slot = Chosen.Items.size()

    Chosen.Items[Slot] = Item
    Chosen.Slots.set(Item, Slot)
    Chosen.Count += 1

    Owner.Homes.set(Item, Chosen)
    Owner.Count += 1
}

function GroupRemove(Owner: Group, Item: MonoBehaviour) {
    const Home = Owner.Homes.get(Item)

    if (Home === undefined) {
        return
    }

    Owner.Homes.delete(Item)
    Owner.Count -= 1

    const Slot = Home.Slots.get(Item)

    if (Slot !== undefined) {
        Home.Slots.delete(Item)
        Home.Items[Slot] = false
        Home.Holes += 1
    }

    Home.Count -= 1

    if (Home.Count <= 0) {
        CloseBucket(Owner, Home)
    }
}

function StepUpdates(Target: Bucket, Delta: number) {
    const Items = Target.Items

    for (let Index = 0; Index < Items.size(); Index++) {
        const Self = Items[Index]

        if (Self !== false) {
            Self.StepFrame(Delta)
        }
    }

    CompactBucket(Target)
}

function HookStepper(Invoke: HookInvoke) {
    return (Target: Bucket, Delta: number) => {
        const Items = Target.Items

        for (let Index = 0; Index < Items.size(); Index++) {
            const Self = Items[Index]

            if (Self !== false) {
                Self.StepPhase(Invoke, Delta)
            }
        }

        CompactBucket(Target)
    }
}

const Stepping = NewGroup(RunService.Heartbeat, StepUpdates)
const Simulating = NewGroup(RunService.PreSimulation, HookStepper((Self, Delta) => Self.FixedUpdate?.(Delta)))
const Latening = NewGroup(RunService.Heartbeat, HookStepper((Self, Delta) => Self.LateUpdate?.(Delta)))
const Rendering = NewGroup(RunService.PreRender, HookStepper((Self, Delta) => Self.OnRender?.(Delta)))
//-------------------------------------------------------------------- Disposal
function DisposeOf(Item: unknown) {
    if (typeIs(Item, "RBXScriptConnection")) {
        Item.Disconnect()
    } else if (typeIs(Item, "Instance")) {
        Item.Destroy()
    } else if (typeIs(Item, "function")) {
        (Item as () => void)()
    } else if (typeIs(Item, "thread")) {
        if (coroutine.status(Item) !== "dead") {
            pcall(() => task.cancel(Item))
        }
    } else if (typeIs(Item, "table")) {
        const Holder = Item as { Destroy?: (self: unknown) => void; Disconnect?: (self: unknown) => void }
        const [Ok, Method] = pcall(() => Holder.Destroy !== undefined ? Holder.Destroy : Holder.Disconnect)

        if (Ok && typeIs(Method, "function")) {
            (Method as (self: unknown) => void)(Holder)
        }
    }
}
//-------------------------------------------------------------------- MonoBehaviour
RegisterClass("MonoBehaviour", "CommonInstance")

export abstract class MonoBehaviour extends CommonInstance {
    public readonly ClassName: string = "MonoBehaviour";

    public Enabled = true;
    public IsStarted = false;
    public TimeScale = 1;
    public DeltaTime = 0;
    public TimeAlive = 0;
    public FrameCount = 0;

    public readonly Started: Signal.Signal<[]> = Signal.new<[]>("Deffered");
    public readonly EnabledChanged: Signal.Signal<[boolean]> = Signal.new<[boolean]>("Deffered");

    public Start?(): void;
    public Update?(delta: number): void;
    public FixedUpdate?(delta: number): void;
    public LateUpdate?(delta: number): void;
    public OnRender?(delta: number): void;
    public OnEnable?(): void;
    public OnDisable?(): void;
    public OnDestroy?(): void;

    private _bin: Array<defined> = [];
    private _invokes = new Map<number, InvokeRecord>();
    private _schedules = new Map<string, ScheduleRecord>();
    private _due = new Map<number, Array<string>>();
    private _dueFrom = 0;
    private _processes = new Map<string, Process>();
    private _processOrder: Array<string | false> = [];
    private _processHoles = 0;
    private _nextHandle = 0;
    private _enabled = false;

    public static GetActive(): Array<MonoBehaviour> {
        const Active = new Array<MonoBehaviour>()

        for (const Held of Stepping.Buckets) {
            for (const Item of Held.Items) {
                if (Item !== false) {
                    Active.push(Item)
                }
            }
        }

        return Active
    }

    public static ActiveCount(): number {
        return Stepping.Count
    }

    public static ConnectionCount(): number {
        return Stepping.Buckets.size()
    }

    public Ready(): void {
        super.Ready()

        GroupAdd(Stepping, this)

        if (this.FixedUpdate !== undefined) {
            GroupAdd(Simulating, this)
        }

        if (this.LateUpdate !== undefined) {
            GroupAdd(Latening, this)
        }

        if (this.OnRender !== undefined && RunService.IsClient()) {
            GroupAdd(Rendering, this)
        }
    }

    private Reconcile() {
        const Wanted = this.Enabled === true

        if (Wanted === this._enabled) {
            return
        }

        this._enabled = Wanted

        if (Wanted) {
            if (this.OnEnable !== undefined) {
                RunGuarded(() => this.OnEnable?.())
            }
        } else if (this.OnDisable !== undefined) {
            RunGuarded(() => this.OnDisable?.())
        }

        if (!this.Destroyed) {
            this.EnabledChanged.Fire(Wanted)
        }
    }

    private TickInvokes() {
        const Invokes = this._invokes

        if (Invokes.isEmpty()) {
            return
        }

        const Clock = this.TimeAlive
        const Due = new Array<number>()

        for (const [Handle, Record] of Invokes) {
            if (Clock >= Record.At) {
                Due.push(Handle)
            }
        }

        if (Due.isEmpty()) {
            return
        }

        for (const Handle of Due) {
            const Record = Invokes.get(Handle)

            if (Record !== undefined) {
                if (Record.Interval !== undefined) {
                    Record.At = Clock + Record.Interval
                } else {
                    Invokes.delete(Handle)
                }

                RunGuarded(() => Record.Callback())

                if (this.Destroyed) {
                    return
                }
            }
        }
    }

    private TickSchedules() {
        const Frame = this.FrameCount
        const Due = this._due

        if (Due.isEmpty()) {
            this._dueFrom = Frame + 1
            return
        }

        const Schedules = this._schedules

        for (let Target = this._dueFrom; Target <= Frame; Target++) {
            const Names = Due.get(Target)

            if (Names !== undefined) {
                Due.delete(Target)

                for (const Name of Names) {
                    const Record = Schedules.get(Name)

                    if (Record !== undefined && Record.At === Target) {
                        Schedules.delete(Name)

                        RunGuarded(() => Record.Callback())

                        if (this.Destroyed) {
                            this._dueFrom = Target + 1
                            return
                        }
                    }
                }
            }
        }

        this._dueFrom = Frame + 1
    }

    private CompactProcesses() {
        if (this._processHoles === 0) {
            return
        }

        const Order = this._processOrder
        let Write = 0

        for (let Read = 0; Read < Order.size(); Read++) {
            const Name = Order[Read]

            if (Name !== false) {
                Order[Write] = Name
                Write += 1
            }
        }

        for (let Index = Order.size(); Index > Write; Index--) {
            Order.pop()
        }

        this._processHoles = 0
    }

    private RunProcesses(Delta: number) {
        const Order = this._processOrder
        const Count = Order.size()

        if (Count === 0) {
            return
        }

        const Processes = this._processes

        for (let Index = 0; Index < Count; Index++) {
            const Name = Order[Index]

            if (Name !== false) {
                const Runner = Processes.get(Name)

                if (Runner !== undefined) {
                    RunGuarded(() => Runner(Delta))

                    if (this.Destroyed || !this._enabled) {
                        return
                    }
                }
            }
        }

        this.CompactProcesses()
    }

    public StepFrame(Delta: number) {
        this.Reconcile()

        if (this.Destroyed || !this._enabled) {
            return
        }

        if (!this.IsStarted) {
            this.IsStarted = true

            if (this.Start !== undefined) {
                RunGuarded(() => this.Start?.())
            }

            if (this.Destroyed) {
                return
            }

            this.Started.Fire()

            if (this.Destroyed || !this._enabled) {
                return
            }
        }

        const Scaled = Delta * this.TimeScale
        this.DeltaTime = Scaled
        this.TimeAlive += Scaled
        this.FrameCount += 1

        this.TickInvokes()

        if (this.Destroyed || !this._enabled) {
            return
        }

        this.TickSchedules()

        if (this.Destroyed || !this._enabled) {
            return
        }

        if (this.Update !== undefined) {
            RunGuarded(() => this.Update?.(Scaled))

            if (this.Destroyed || !this._enabled) {
                return
            }
        }

        this.RunProcesses(Scaled)
    }

    public StepPhase(Invoke: HookInvoke, Delta: number) {
        if (this.Destroyed) {
            return
        }

        this.Reconcile()

        if (this.IsStarted && this._enabled && !this.Destroyed) {
            RunGuarded(() => Invoke(this, Delta * this.TimeScale))
        }
    }

    public SetEnabled(Wanted: boolean) {
        if (this.Destroyed) {
            return
        }

        const Next = Wanted === true

        if (this.Enabled === Next) {
            return
        }

        this.Enabled = Next
        this.Reconcile()
    }

    public Invoke(Callback: () => void, Delay: number): number {
        this._nextHandle += 1
        this._invokes.set(this._nextHandle, {
            Callback: Callback,
            At: this.TimeAlive + math.max(Delay, 0)
        })

        return this._nextHandle
    }

    public InvokeRepeating(Callback: () => void, Delay: number, Interval: number): number {
        if (Interval <= 0) {
            error("InvokeRepeating needs a positive interval", 2)
        }

        this._nextHandle += 1
        this._invokes.set(this._nextHandle, {
            Callback: Callback,
            At: this.TimeAlive + math.max(Delay, 0),
            Interval: Interval
        })

        return this._nextHandle
    }

    public CancelInvoke(Handle?: number) {
        if (Handle !== undefined) {
            this._invokes.delete(Handle)
        } else {
            this._invokes.clear()
        }
    }

    public IsInvoking(Handle?: number): boolean {
        if (Handle !== undefined) {
            return this._invokes.has(Handle)
        }

        return !this._invokes.isEmpty()
    }

    public Schedule(Name: string, Ticks: number, Callback: () => void) {
        if (Name === "") {
            error("Schedule expects a non-empty string name", 2)
        }

        if (this.Destroyed) {
            error(`cannot Schedule on a destroyed ${this.ClassName}`, 2)
        }

        const At = this.FrameCount + math.max(math.floor(Ticks), 1)
        this._schedules.set(Name, { Callback: Callback, At: At })

        const Slot = this._due.get(At)

        if (Slot !== undefined) {
            Slot.push(Name)
        } else {
            this._due.set(At, [Name])
        }
    }

    public Unschedule(Name?: string) {
        if (Name !== undefined) {
            this._schedules.delete(Name)
        } else {
            this._schedules.clear()
            this._due.clear()
        }
    }

    public IsScheduled(Name: string): boolean {
        return this._schedules.has(Name)
    }

    public AttachProcess(Name: string, Runner: Process) {
        if (Name === "") {
            error("AttachProcess expects a non-empty string name", 2)
        }

        if (this.Destroyed) {
            error(`cannot AttachProcess on a destroyed ${this.ClassName}`, 2)
        }

        if (this._processes.has(Name)) {
            this._processes.set(Name, Runner)
            return
        }

        this._processes.set(Name, Runner)
        this._processOrder.push(Name)
    }

    public DetachProcess(Name?: string) {
        if (Name === undefined) {
            this._processes.clear()
            this._processOrder.clear()
            this._processHoles = 0
            return
        }

        if (!this._processes.has(Name)) {
            return
        }

        this._processes.delete(Name)

        const Order = this._processOrder

        for (let Index = 0; Index < Order.size(); Index++) {
            if (Order[Index] === Name) {
                Order[Index] = false
                this._processHoles += 1
                break
            }
        }
    }

    public HasProcess(Name: string): boolean {
        return this._processes.has(Name)
    }

    public Bind<T extends Array<unknown>>(Event: Connectable<T>, Callback: (...args: T) => void): defined {
        if (this.Destroyed) {
            error(`cannot Bind on a destroyed ${this.ClassName}`, 2)
        }

        const Link = Event.Connect((...args: T) => {
            if (this.Destroyed) {
                return
            }

            Callback(...args)
        })

        this._bin.push(Link)

        return Link
    }

    public Track<T extends defined>(Object: T): T {
        if (this.Destroyed) {
            DisposeOf(Object)
            return Object
        }

        this._bin.push(Object)

        return Object
    }

    public Untrack(Object: unknown) {
        const Bin = this._bin

        for (let Index = Bin.size() - 1; Index >= 0; Index--) {
            if (Bin[Index] === Object) {
                Bin.remove(Index)
                break
            }
        }
    }

    public StartTask<A extends Array<unknown>>(Callback: (...args: A) => void, ...args: A): thread {
        if (this.Destroyed) {
            error(`cannot StartTask on a destroyed ${this.ClassName}`, 2)
        }

        const Runner = task.spawn(Callback, ...args)

        if (coroutine.status(Runner) !== "dead") {
            this._bin.push(Runner)
        }

        return Runner
    }

    public StopTask(Runner: thread) {
        this.Untrack(Runner)

        if (coroutine.status(Runner) !== "dead") {
            pcall(() => task.cancel(Runner))
        }
    }

    public Wait(Seconds?: number): number {
        const Target = math.max(Seconds !== undefined ? Seconds : 0, 0)
        let Elapsed = 0

        do {
            const Delta = task.wait()

            if (this.Destroyed) {
                break
            }

            Elapsed += Delta * this.TimeScale
        } while (Elapsed < Target)

        return Elapsed
    }

    protected OnDestroyed(): void {
        super.OnDestroyed()

        GroupRemove(Stepping, this)
        GroupRemove(Simulating, this)
        GroupRemove(Latening, this)
        GroupRemove(Rendering, this)

        if (this._enabled) {
            this._enabled = false
            this.Enabled = false

            if (this.OnDisable !== undefined) {
                RunGuarded(() => this.OnDisable?.())
            }

            this.EnabledChanged.Fire(false)
        }

        if (this.OnDestroy !== undefined) {
            RunGuarded(() => this.OnDestroy?.())
        }

        this._invokes.clear()
        this._schedules.clear()
        this._due.clear()
        this._processes.clear()
        this._processOrder.clear()
        this._processHoles = 0

        const Bin = this._bin

        for (let Index = Bin.size() - 1; Index >= 0; Index--) {
            const Item = Bin[Index]
            Bin.pop()

            const [Ok, Err] = pcall(() => DisposeOf(Item))

            if (!Ok) {
                task.spawn(() => error(Err))
            }
        }

        this.Started.Destroy()
        this.EnabledChanged.Destroy()
    }
}
