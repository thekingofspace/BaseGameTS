local RunService = game:GetService("RunService")

local signal = require(script.Parent.signal)

export type Signal<T...> = signal.Signal<T...>

export type ReplicationPP = {
    ----------------------------------------------------------------------------
    -- Server side
    ----------------------------------------------------------------------------
    -- Stages a snapshot of the object for each target player. Non-blocking.
    ReplicateAsset: (targets: Player | {Player}, object: Instance) -> (),
    -- Replicates to every current player; pass persistent = true to also
    -- auto-replicate to players who join later (until UnReplicateAll or the
    -- original is destroyed).
    ReplicateToAll: (object: Instance, persistent: boolean?) -> (),
    -- Revokes the object from the given players (pending or confirmed).
    UnReplicate: (targets: Player | {Player}, object: Instance) -> (),
    -- Revokes the object from every player and clears its persistent flag.
    UnReplicateAll: (object: Instance) -> (),
    -- True once the player has confirmed their local copy exists.
    IsReplicated: (player: Player, object: Instance) -> boolean,
    -- True while a replication has been staged but not yet confirmed.
    IsPending: (player: Player, object: Instance) -> boolean,
    -- Every player that currently holds a confirmed copy of the object.
    GetReplicatedPlayers: (object: Instance) -> {Player},
    -- Fired with (player, original) when a client confirms its local copy.
    OnConfirmed: Signal<Player, Instance>,
    -- Fired with (player, original) when a player's copy is revoked or the
    -- client reports it destroyed. Not fired when the player leaves the game.
    OnRemoved: Signal<Player, Instance>,

    ----------------------------------------------------------------------------
    -- Client side
    ----------------------------------------------------------------------------
    -- The local (client-only) folder in ReplicatedStorage holding every asset.
    GetAssetFolder: () -> Folder,
    -- Finds a replicated asset by name, or nil if it has not arrived.
    GetAsset: (name: string) -> Instance?,
    -- Every asset currently replicated to this client.
    GetAssets: () -> {Instance},
    -- Yields until an asset with the given name arrives. Returns nil if
    -- `timeout` (seconds) elapses first; waits forever when omitted.
    AwaitAsset: (name: string, timeout: number?) -> Instance?,
    -- Fired with the local copy right after it is registered.
    OnReplication: Signal<Instance>,
    -- Fired with the local copy when it is destroyed (revoked or otherwise).
    OnUnReplication: Signal<Instance>,
}

local target:ReplicationPP = (RunService:IsServer() and require(script.Server) or require(script.Client))::any

return target