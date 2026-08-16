import Signal = require("../signal");

/**
 * Type declarations for **ReplicationPP** — replicates Instances to specific
 * players instead of to everyone.
 *
 * The server stages a clone of the object under a `ReplicationPP_Receiver` folder
 * in the target's `PlayerGui`; the client picks it up, waits for its descendants
 * to stream in, re-parents its own copy into a local `ReplicationPP_Assets` folder
 * in `ReplicatedStorage`, and claims it back over the wire.
 *
 * ### Server and client surfaces differ
 * `init.luau` resolves to `Server.luau` on the server and `Client.luau` on the
 * client, and the two modules share **no** members. Requiring this on the server
 * gives you {@link ReplicationPP.ServerApi} only; the client gives you
 * {@link ReplicationPP.ClientApi} only. Reaching for the other half is `undefined`
 * at runtime — it will not error at the call site, it will error as
 * "attempt to call a nil value".
 *
 * The default export merges both halves, mirroring the module's own `ReplicationPP`
 * Luau type. To have the compiler enforce the split, narrow at the import site:
 *
 * ```ts
 * import ReplicationPP from "Modules/Shared/ReplicationPP";
 * const Replication: ReplicationPP.ServerApi = ReplicationPP;
 * ```
 *
 * Every function here is defined with a dot and takes no `self`
 * (`function module.ReplicateAsset(...)`), so all of them are declared as
 * properties and compile to `ReplicationPP.ReplicateAsset(...)`. The signals are
 * `signal.luau` objects, so their own members stay colon calls.
 */
declare namespace ReplicationPP {
	/** The members that exist only when this module is required from the server. */
	interface ServerApi {
		/**
		 * Stages a snapshot of the object for each target player. Non-blocking —
		 * the clone and delivery happen on a spawned thread. A player who already
		 * has the object staged or confirmed is skipped.
		 *
		 * The object must be `Archivable`, and the target must have a `PlayerGui`.
		 */
		ReplicateAsset: (targets: Player | Array<Player>, object: Instance) => void;
		/**
		 * Replicates to every current player. Pass `persistent = true` to also
		 * auto-replicate to players who join later, until `UnReplicateAll` is called
		 * or the original is destroyed.
		 */
		ReplicateToAll: (object: Instance, persistent?: boolean) => void;
		/** Revokes the object from the given players, whether pending or confirmed. */
		UnReplicate: (targets: Player | Array<Player>, object: Instance) => void;
		/** Revokes the object from every player and clears its persistent flag. */
		UnReplicateAll: (object: Instance) => void;
		/** True once the player has confirmed their local copy exists. */
		IsReplicated: (player: Player, object: Instance) => boolean;
		/** True while a replication has been staged but not yet confirmed. */
		IsPending: (player: Player, object: Instance) => boolean;
		/** Every player that currently holds a confirmed copy of the object. */
		GetReplicatedPlayers: (object: Instance) => Array<Player>;

		/** Fired with `(player, original)` when a client confirms its local copy. */
		readonly OnConfirmed: Signal.Signal<[Player, Instance]>;
		/**
		 * Fired with `(player, original)` when a player's copy is revoked or the
		 * client reports it destroyed. Not fired when the player leaves the game.
		 */
		readonly OnRemoved: Signal.Signal<[Player, Instance]>;
	}

	/** The members that exist only when this module is required from the client. */
	interface ClientApi {
		/** The local (client-only) folder in `ReplicatedStorage` holding every asset. */
		GetAssetFolder: () => Folder;
		/** Finds a replicated asset by name, or `undefined` if it has not arrived. */
		GetAsset: (name: string) => Instance | undefined;
		/** Every asset currently replicated to this client. */
		GetAssets: () => Array<Instance>;
		/**
		 * Yields until an asset with the given name arrives. Returns `undefined` if
		 * `timeout` (seconds) elapses first; waits forever when omitted.
		 */
		AwaitAsset: (name: string, timeout?: number) => Instance | undefined;

		/** Fired with the local copy right after it is registered. */
		readonly OnReplication: Signal.Signal<[Instance]>;
		/** Fired with the local copy when it is destroyed, whether revoked or not. */
		readonly OnUnReplication: Signal.Signal<[Instance]>;
	}
}

/**
 * The merged surface, matching the `ReplicationPP` type declared in `init.luau`.
 * Only one half is actually present at runtime — see the namespace docs above.
 */
interface ReplicationPPModule extends ReplicationPP.ServerApi, ReplicationPP.ClientApi {}

declare const ReplicationPP: ReplicationPPModule;

export = ReplicationPP;
