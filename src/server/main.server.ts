//-------------------------------------------------------------------- IMPORTS
import { Debris, Players } from "@rbxts/services";
import ProfileStore from "@server/ProfileStore";
import Pigeon from "@shared/Pigeon";
//-------------------------------------------------------------------- TopLine Vars
const PlayerStore = ProfileStore.New("Player_Data", {
    "Money": 500
})
const CommonNetwork = Pigeon.new<Pigeon.ServerCarrier>("Common")
const Sessions = new Map<number, ProfileStore.Profile<any>>();
//-------------------------------------------------------------------- PlayerLinks
function PlayerAdd(TargetPlayer: Player) {
    const Session = PlayerStore.StartSessionAsync(tostring(TargetPlayer.UserId), {
        Cancel: () => TargetPlayer.IsDescendantOf(Players)
    })

    if (Session){
        Session.Reconcile()
        Session.AddUserId(TargetPlayer.UserId)
        Sessions.set(TargetPlayer.UserId, Session)
    }
    CommonNetwork.BroadcastTo(TargetPlayer, "@Data/DataReady")
}

function PlayerRemoving(TargetPlayer: Player){
    const Session = Sessions.get(TargetPlayer.UserId)
    if (Session){
        Session.EndSession()
        Sessions.delete(TargetPlayer.UserId)
    }
    Debris.AddItem(TargetPlayer, 5)
    CommonNetwork.ReleaseTable("@PlayerData/" + tostring(TargetPlayer.UserId))
}

Players.PlayerAdded.Connect(PlayerAdd)
Players.PlayerRemoving.Connect(PlayerRemoving)
for (const Player of Players.GetPlayers()) {
    task.spawn(PlayerAdd, Player) // Spawning to prevent yielding on data
}
//-------------------------------------------------------------------- Main Code