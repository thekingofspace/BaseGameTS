//-------------------------------------------------------------------- IMPORTS
import { Debris, Players, ReplicatedStorage } from "@rbxts/services";
import ProfileStore from "@server/ProfileStore";
import Pigeon from "@shared/Pigeon";
import { DataStore_Name, DataTemplate, Player_Data } from "@data/PlayerData";
import "@game/Classes/Structure/BP_BuildableWall";
//-------------------------------------------------------------------- Pointers
const GameStorage = ReplicatedStorage.FindFirstChild("PrimaryGame")
const ClassStorage = GameStorage !== undefined ? GameStorage.FindFirstChild("Classes") : undefined
const Structures = ClassStorage !== undefined ? ClassStorage.FindFirstChild("Structure") : undefined
//-------------------------------------------------------------------- TopLine Vars
const PlayerStore = ProfileStore.New<Player_Data>(DataStore_Name, DataTemplate)
const CommonNetwork = Pigeon.new<Pigeon.ServerCarrier>("Common")
const Sessions = new Map<number, PlayerController>();
const ThreadSession = new Map<number, Array<thread>>();
//-------------------------------------------------------------------- PlayerDataClass
/*
    Headers
    @Data/DataUpdate Var 1 is {string, string} this is the specific path you want to set
    var 2 is the new value
*/
type ActionItem = {
    UseStd: boolean;
    Get?: (self: PlayerController) => unknown;
    Set?: (self: PlayerController, value: unknown) => void;
};

const ActionAray: Record<string, ActionItem | undefined> = {
    "Money": {
        "UseStd": true
    },

    "Level": {
        "UseStd": false,

        Get: (Controller) => {
            return true
        },

        Set: (Controller, Value) => {
            return true
        }
    }
}

class PlayerController {
    public SealedData: ProfileStore.Profile<Player_Data>;
    private Owner: Player;

    constructor(Profile: ProfileStore.Profile<Player_Data>, Owner: Player){
        this.SealedData = Profile
        this.Owner = Owner
    };

    private InformUpdate(Path: Array<string>, Value: unknown){
        CommonNetwork.BroadcastTo(this.Owner, "@Data/DataUpdate", Path, Value)
    };

    private Container(Path: Array<string>): Record<string, unknown> | undefined {
        let Node = this.SealedData.Data as unknown as Record<string, unknown>

        for (let Index = 0; Index < Path.size() - 1; Index++) {
            const Next = Node[Path[Index]]

            if (!typeIs(Next, "table")) {
                return undefined
            }

            Node = Next as Record<string, unknown>
        }

        return Node
    };

    public GetOwner(){
        return this.Owner
    };

    public IsActive(){
        return this.SealedData.IsActive()
    };

    public Snapshot(){
        return this.SealedData.Data
    };

    public Get(Path: Array<string>): unknown {
        if (Path.size() === 0) {
            return undefined
        }

        const Action = ActionAray[Path[0]]

        if (Action && !Action.UseStd) {
            return Action.Get !== undefined ? Action.Get(this) : undefined
        }

        const Node = this.Container(Path)

        return Node !== undefined ? Node[Path[Path.size() - 1]] : undefined
    };

    public Set(Path: Array<string>, Value: unknown){
        if (Path.size() === 0 || !this.SealedData.IsActive()) {
            return false
        }

        const Action = ActionAray[Path[0]]

        if (Action && !Action.UseStd) {
            if (Action.Set === undefined) {
                return false
            }

            Action.Set(this, Value)
            return true
        }

        const Node = this.Container(Path)

        if (Node === undefined) {
            return false
        }

        Node[Path[Path.size() - 1]] = Value
        this.InformUpdate(Path, Value)
        return true
    };

    public Increment(Path: Array<string>, Amount: number){
        const Current = this.Get(Path)

        if (!typeIs(Current, "number")) {
            return undefined
        }

        const Total = Current + Amount

        return this.Set(Path, Total) ? Total : undefined
    };

    public Destroy(){
        if (this.SealedData.IsActive()) {
            this.SealedData.EndSession()
        }
    };
}
//-------------------------------------------------------------------- PlayerLinks
function FetchData(TargetPlayer: Player): PlayerController | undefined {
    const GUID = TargetPlayer.UserId
    const Existing = Sessions.get(GUID)

    if (Existing) {
        return Existing
    }

    if (!TargetPlayer.IsDescendantOf(Players)) {
        return undefined
    }

    const Thread = coroutine.running()

    let Threads = ThreadSession.get(GUID)

    if (!Threads) {
        Threads = []
        ThreadSession.set(GUID, Threads)
    }

    Threads.push(Thread)
    coroutine.yield()

    return Sessions.get(GUID)
}

function PlayerAdd(TargetPlayer: Player) {
    const UID = TargetPlayer.UserId

    if (!Sessions.has(UID)) {
        const Session = PlayerStore.StartSessionAsync(tostring(UID), {
            Cancel: () => !TargetPlayer.IsDescendantOf(Players)
        })

        if (Session) {
            Session.AddUserId(UID)
            Session.Reconcile()

            Session.OnSessionEnd.Connect(() => {
                const Current = Sessions.get(UID)

                if (Current !== undefined && Current.SealedData === Session) {
                    Sessions.delete(UID)
                    TargetPlayer.Kick("Your data session was ended, please rejoin.")
                }
            })

            if (TargetPlayer.IsDescendantOf(Players)) {
                Sessions.set(UID, new PlayerController(Session, TargetPlayer))
            } else {
                Session.EndSession()
            }
        } else {
            TargetPlayer.Kick("Unable to load your data, please rejoin.")
        }
    }

    const Threads = ThreadSession.get(UID)

    if (Threads) {
        for (const Thread of Threads) {
            coroutine.resume(Thread)
        }
        ThreadSession.delete(UID)
    }

    const Controller = Sessions.get(UID)

    if (Controller) {
        CommonNetwork.BroadcastTo(TargetPlayer, "@Data/DataReady", Controller.Snapshot())
    }
}

function PlayerRemoving(TargetPlayer: Player){
    const UID = TargetPlayer.UserId
    const Session = Sessions.get(UID)
    const PendingThreads = ThreadSession.get(UID)

    if (Session){
        Sessions.delete(UID)
        Session.Destroy()
    }

    if (PendingThreads) {
        for (const Thread of PendingThreads) {
            coroutine.resume(Thread)
        }
        ThreadSession.delete(UID)
    }

    Debris.AddItem(TargetPlayer, 5)
}

Players.PlayerAdded.Connect(PlayerAdd)
Players.PlayerRemoving.Connect(PlayerRemoving)
for (const Player of Players.GetPlayers()) {
    task.spawn(PlayerAdd, Player) // Spawning to prevent yielding on data
}
//-------------------------------------------------------------------- Boot Structure
if (Structures !== undefined) {
    const Instances = Structures.FindFirstChild("Instances")

    if (Instances !== undefined) {
        for (const Item of Instances.GetChildren()) {
            if (Item.IsA("ModuleScript")) {
                require(Item)
            }
        }
    }
}

