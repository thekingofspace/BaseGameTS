//-------------------------------------------------------------------- SERVICES
import { Players, ReplicatedStorage, RunService } from "@rbxts/services";
//-------------------------------------------------------------------- MODULES
import Blackbox from "@shared/Blackbox";
import * as PlayerData from "@game/Classes/PlayerData";
import "@game/Classes/Structure/BP_BuildableWall";
//-------------------------------------------------------------------- Pointers

const GameStorage = ReplicatedStorage.WaitForChild("PrimaryGame", 500)
const ClassStorage = GameStorage !== undefined ? GameStorage.FindFirstChild("Classes") : undefined
const Structures = ClassStorage !== undefined ? ClassStorage.FindFirstChild("Structure") : undefined
//-------------------------------------------------------------------- Topline VARS
const Log = Blackbox.Get("Client.Boot")
const LocalPlayer = Players.LocalPlayer
const GameSocket = PlayerData.GameSocket
const UnreliableGameSocket = PlayerData.UnreliableGameSocket

Blackbox.Configure({ Console: { UseTestService: RunService.IsStudio() } })
//-------------------------------------------------------------------- Event linker
GameSocket.Init()
UnreliableGameSocket.Init()
//-------------------------------------------------------------------- Last safety check
PlayerData.Await()

Log.Info("game data recieved", { userId: LocalPlayer.UserId, EventID: "@Data/DataReady" })
//-------------------------------------------------------------------- Important Vars
const _Money = PlayerData.GetNumber(["Money"], 0)

PlayerData.OnUpdate(["Money"], (Value) => {
    Log.Debug("money changed", { Value: Value })
})
//-------------------------------------------------------------------- Vars
const ActionMap: Record<string, () => any> = {
    Test: () => {
        return $tuple("abc", 123);
    },

    Re: () => {
        return $tuple("xyz", 456);
    },
};

const Result = ActionMap["Var"]?.();

if (Result) {
    const [Test, Fah]: LuaTuple<[number, string]> = Result;
    print(Test, Fah)
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

