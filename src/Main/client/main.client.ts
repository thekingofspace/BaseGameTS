//-------------------------------------------------------------------- SERVICES
import { Players, ReplicatedStorage, RunService } from "@rbxts/services";
//-------------------------------------------------------------------- MODULES
import Blackbox from "@shared/Blackbox";
import * as PlayerData from "@game/Classes/PlayerData";
//-------------------------------------------------------------------- Pointers
const GameStorage = ReplicatedStorage.WaitForChild("PrimaryGame", 500)
const ClassStorage = GameStorage !== undefined ? GameStorage.WaitForChild("Classes", 500) : undefined
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
const Money = PlayerData.GetNumber(["Money"], 0)

PlayerData.OnUpdate(["Money"], (Value) => {
    Log.Debug("money changed", { Value: Value })
})
//-------------------------------------------------------------------- Vars

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
