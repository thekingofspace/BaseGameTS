//-------------------------------------------------------------------- SERVICES
import { Players, RunService } from "@rbxts/services";
//-------------------------------------------------------------------- MODULES
import Blackbox from "@shared/Blackbox";
import * as PlayerData from "@game/Classes/PlayerData";
//-------------------------------------------------------------------- Topline VARS
const Log = Blackbox.Get("Lobby.Boot")
const LocalPlayer = Players.LocalPlayer
const GameSocket = PlayerData.GameSocket
const UnreliableGameSocket = PlayerData.UnreliableGameSocket

Blackbox.Configure({ Console: { UseTestService: RunService.IsStudio() } })
//-------------------------------------------------------------------- Event linker
GameSocket.Init()
UnreliableGameSocket.Init()
//-------------------------------------------------------------------- Last safety check
PlayerData.Await()

Log.Info("lobby data recieved", { userId: LocalPlayer.UserId, EventID: "@Data/DataReady" })
//-------------------------------------------------------------------- Important Vars

//-------------------------------------------------------------------- Vars

//-------------------------------------------------------------------- Main Code
