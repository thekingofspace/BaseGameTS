//-------------------------------------------------------------------- MODULES
import Pigeon from "@shared/Pigeon";
import { Player_Data } from "@data/PlayerData";
//-------------------------------------------------------------------- Types
export type { Player_Data };

export type UpdateListener = (Value: unknown, Path: Array<string>) => void;
//-------------------------------------------------------------------- Sockets
export const GameSocket = Pigeon.new<Pigeon.ClientCarrier>("Common", {"Timeout": 500})
export const UnreliableGameSocket = Pigeon.new<Pigeon.ClientCarrier>("Common_Unreliable", {"Unreliable": true})
//-------------------------------------------------------------------- Topline VARS
let Mirror: Record<string, unknown> = {}
let Ready = false

const Waiting = new Array<thread>()
const Listeners = new Map<string, Array<UpdateListener>>()
//-------------------------------------------------------------------- Internals
function KeyOf(Path: Array<string>) {
    return Path.join(".")
}

function Container(Path: Array<string>, Build: boolean): Record<string, unknown> | undefined {
    let Node = Mirror

    for (let Index = 0; Index < Path.size() - 1; Index++) {
        const Next = Node[Path[Index]]

        if (!typeIs(Next, "table")) {
            if (!Build) {
                return undefined
            }

            const Fresh: Record<string, unknown> = {}
            Node[Path[Index]] = Fresh
            Node = Fresh
        } else {
            Node = Next as Record<string, unknown>
        }
    }

    return Node
}

function Fire(Key: string, Value: unknown, Path: Array<string>) {
    const Bound = Listeners.get(Key)

    if (Bound === undefined) {
        return
    }

    for (const Callback of [...Bound]) {
        Callback(Value, Path)
    }
}

function Notify(Path: Array<string>) {
    let Key = ""
    let Node: unknown = Mirror

    Fire(Key, Node, Path)

    for (const Segment of Path) {
        Key = Key === "" ? Segment : `${Key}.${Segment}`
        Node = typeIs(Node, "table") ? (Node as Record<string, unknown>)[Segment] : undefined

        Fire(Key, Node, Path)
    }
}
//-------------------------------------------------------------------- Event linker
GameSocket.On<[Player_Data]>("@Data/DataReady", (Snapshot) => {
    if (Ready) {
        return
    }

    Mirror = Snapshot as unknown as Record<string, unknown>
    Ready = true

    for (const Thread of [...Waiting]) {
        if (coroutine.status(Thread) === "suspended") {
            coroutine.resume(Thread)
        }
    }

    Waiting.clear()
    Notify([])
})

GameSocket.On<[Array<string>, unknown]>("@Data/DataUpdate", (Path, Value) => {
    if (Path.size() === 0) {
        return
    }

    const Node = Container(Path, true)

    if (Node === undefined) {
        return
    }

    Node[Path[Path.size() - 1]] = Value
    Notify(Path)
})
//-------------------------------------------------------------------- API
export function IsReady() {
    return Ready
}

export function Await() {
    if (Ready) {
        return
    }

    Waiting.push(coroutine.running())
    coroutine.yield()
}

export function Snapshot() {
    return Mirror as unknown as Player_Data
}

export function Get(Path: Array<string>): unknown {
    if (Path.size() === 0) {
        return Mirror
    }

    const Node = Container(Path, false)

    return Node !== undefined ? Node[Path[Path.size() - 1]] : undefined
}

export function GetNumber(Path: Array<string>, Fallback: number) {
    const Value = Get(Path)

    return typeIs(Value, "number") ? Value : Fallback
}

export function OnUpdate(Path: Array<string>, Callback: UpdateListener) {
    const Key = KeyOf(Path)
    const Existing = Listeners.get(Key)
    const Bound = Existing !== undefined ? Existing : new Array<UpdateListener>()

    if (Existing === undefined) {
        Listeners.set(Key, Bound)
    }

    Bound.push(Callback)

    return () => {
        const Index = Bound.indexOf(Callback)

        if (Index !== -1) {
            Bound.remove(Index)
        }
    }
}
