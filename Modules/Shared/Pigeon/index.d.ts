/**
 * Type declarations for **Pigeon** (`Modules/Shared/Pigeon/init.luau`).
 *
 * Pigeon multiplexes every carrier over a small pool of shared `RemoteEvent`s
 * (`ReplicatedStorage/PigeonRefs`), buffering packets until the other side is
 * listening.
 *
 * Call-syntax rules used throughout this file:
 * - Everything on `pigeon` itself (`new`, `StagedTable`, `Transformer`,
 *   `GetRef`) and everything on `pigeon.Network` is defined with a dot and
 *   takes no `self`, so those are declared as **properties** holding arrow
 *   types and compile to `Pigeon.new(...)` / `Pigeon.Network.Push(...)`.
 * - Every member of a carrier, a transformer and a staged table takes `self`,
 *   so those stay **methods** and compile to colon calls.
 *
 * Server/client split: the Luau `PigeonCarrier` type merges both halves, but at
 * runtime the server-only members throw `ERR_NOT_SERVER` on the client and the
 * client-only members throw `ERR_NOT_CLIENT` on the server. That split is
 * modelled here as {@link Pigeon.ServerCarrier} and {@link Pigeon.ClientCarrier};
 * annotate the result of `Pigeon.new` with the side you are on:
 *
 * ```ts
 * const carrier: Pigeon.ServerCarrier = Pigeon.new("Combat");
 * ```
 *
 * The callback shape of `On`/`When` also differs by side — the server receives
 * the sending `Player` as the first argument, the client does not.
 */

declare namespace Pigeon {
	/**
	 * Lifetime owner. Every connection a carrier makes is tracked on a
	 * transformer, so destroying it tears the whole carrier down.
	 */
	interface Transformer {
		/** Stable id; hashed to pick which `RemoteEvent` bucket this traffic uses. */
		readonly uuid: string;
		readonly destroyed: boolean;

		/**
		 * Registers a teardown function. Returns an "untrack" function that
		 * removes it again. If the transformer is already destroyed the
		 * teardown runs immediately.
		 */
		Track(disconnect: () => void): () => void;
		/** Runs every tracked teardown and unregisters from the ref pool. */
		Destroy(): void;
	}

	interface CarrierOptions {
		/** Route pushes through `UnreliableRemoteEvent`s instead. */
		Unreliable?: boolean;
		/** Seconds to wait for a `Call`/`CallTo` response. Defaults to 10. */
		Timeout?: number;
		/**
		 * Reuse an existing transformer instead of creating one. When supplied,
		 * the carrier does not own it and will not destroy it.
		 */
		Transformer?: Transformer;
	}

	/**
	 * Runs on every packet in one direction. Return the (possibly rewritten)
	 * event name and argument list; return `$tuple()` to pass the packet
	 * through unchanged. Errors are caught and warned about.
	 */
	type MiddlewareFunction = (
		direction: "incoming" | "outgoing",
		event: string,
		args: Array<unknown>,
		player: Player | undefined,
	) => LuaTuple<[event?: string, args?: Array<unknown>]>;

	/**
	 * Guards a staged table capture/release. Only an explicit `false` denies —
	 * `true` or `undefined` allows.
	 */
	type StageGuard = (player: Player, id: string) => boolean | undefined;

	/** Runs after a patch or snapshot lands, with the staged table's live view. */
	type StageUpdate<T = Record<string, unknown>> = (view: T) => void;

	/**
	 * A replicated table. The server captures one onto a carrier; clients
	 * request it and receive a snapshot plus a live patch stream.
	 *
	 * Values must be plain Roblox data — no functions, threads, metatables or
	 * cycles. Writes through the view are validated and throw otherwise.
	 */
	interface StageTable<T = Record<string, unknown>> {
		/**
		 * The proxy view. Reading walks the store, writing records a patch and
		 * (on the server) replicates it to subscribers on the next `defer`.
		 */
		GetTable(): T;

		/** Adds a guard consulted before a client is allowed to capture this table. */
		UseCapture(Callback: StageGuard): void;
		/** Adds a guard consulted before a client is allowed to release this table. */
		UseRelease(Callback: StageGuard): void;
		/** Runs the callback whenever patches or a snapshot are applied. Returns a disconnect function. */
		OnUpdate(Callback: StageUpdate<T>): () => void;
		/** Client side: stops following the table and tells the server to drop the subscription. */
		Release(): void;
	}

	/** Members that behave the same on both sides. */
	interface Carrier {
		/** Whether pushes go out over `UnreliableRemoteEvent`s. Set from `CarrierOptions`. */
		Unreliable: boolean;
		/** Seconds a `Call`/`CallTo` waits before resolving as a failure. `undefined` means the 10s default. */
		Timeout: number | undefined;

		/**
		 * Removes a listener/responder. Passing no callback clears every
		 * listener *and* the responder for that event.
		 */
		Off(event: string, Callback?: Callback): void;

		/** Adds middleware for packets arriving at this carrier. Runs in the order added. */
		UseIncoming(Callback: MiddlewareFunction): void;
		/** Adds middleware for packets leaving this carrier. Runs in the order added. */
		UseOutgoing(Callback: MiddlewareFunction): void;

		/**
		 * Client side: announces this carrier as ready so the server flushes
		 * anything it buffered for this channel. No-op on the server, and
		 * safe to call more than once. Returns the carrier for chaining.
		 */
		Init(): this;

		/**
		 * Drops every listener, room, staged table and connection. Also
		 * destroys the transformer if the carrier created it.
		 */
		Destroy(): void;
	}

	/**
	 * The server half of a carrier. These members throw `ERR_NOT_SERVER`
	 * if called from a client.
	 */
	interface ServerCarrier extends Carrier {
		/** Sends an event to the given players (a single `Player` is accepted). Unapproved players are skipped. */
		BroadcastTo(Targets: Array<Player> | Player, event: string, ...args: Array<unknown>): void;
		/** Sends an event to every player. */
		Broadcast(event: string, ...args: Array<unknown>): void;
		/** Sends an event to every player except the ones given. */
		BroadcastExcept(Targets: Array<Player> | Player, event: string, ...args: Array<unknown>): void;
		/**
		 * Yields until the target's `When` responder replies, or until
		 * `Timeout`. Returns nothing on timeout, on a failed handshake, or if
		 * the player leaves.
		 */
		CallTo<R extends Array<unknown> = Array<unknown>>(
			Target: Player,
			Event: string,
			...args: Array<unknown>
		): LuaTuple<R>;
		/** Sends an event to every member of a room. Warns if the room does not exist. */
		SendToRoom(Room: string, event: string, ...args: Array<unknown>): void;

		/** Creates (or replaces) a room. Throws if any member has not passed the handshake. */
		CreateRoom(RoomID: string, Players: Array<Player>): void;
		/** Forgets a room. */
		DestroyRoom(RoomID: string): void;
		/** Adds players to a room, creating it if needed. Throws on unapproved players. */
		JoinRoom(RoomID: string, Players: Array<Player> | Player): void;
		/** Removes players from a room. */
		LeaveRoom(RoomID: string, Players: Array<Player> | Player): void;

		/**
		 * Publishes a staged table under `id` so clients can `RequestTable` it.
		 * Writes made through the table's view are replicated to subscribers.
		 */
		CaptureTable(id: string, Table: StageTable<any>): void;
		/** Stops publishing the table under `id`. */
		ReleaseTable(id: string): void;
		/**
		 * Pushes the table at `id` onto the targets (everyone if omitted)
		 * without waiting for them to ask. Throws if nothing is captured there.
		 */
		ForceTable(id: string, Targets?: Array<Player> | Player): void;

		/**
		 * Requires clients to pass this check before any other event of theirs
		 * is routed. Setting it clears the current approvals.
		 */
		UseHandshake(Callback: (player: Player, ...args: Array<unknown>) => boolean): void;
		/**
		 * The subset of `Targets` (default: every player) that passed the
		 * handshake. With no handshake installed, returns the candidates
		 * unchanged. Has no runtime side guard, but is only meaningful here.
		 */
		Approved(Targets?: Array<Player>): Array<Player>;
		/**
		 * Revokes approval, removes the players from every room and drops their
		 * staged-table subscriptions. Returns how many were actually approved.
		 */
		Revoke(Targets: Array<Player> | Player): number;

		/**
		 * Listens for a client event. The sending player is passed first.
		 *
		 * Pass the payload tuple to type the arguments:
		 * `On<[number, string]>("Hit", (player, damage, kind) => ...)`
		 */
		On<A extends Array<unknown> = Array<unknown>>(
			event: string,
			Callback: (player: Player, ...args: A) => void,
		): void;
		/**
		 * Sets the single responder for a client `Call`. The sending player is
		 * passed first; return values are sent back. Pass no callback to clear it.
		 */
		When<A extends Array<unknown> = Array<unknown>, R = unknown>(
			event: string,
			Callback?: (player: Player, ...args: A) => R,
		): void;
	}

	/**
	 * The client half of a carrier. These members throw `ERR_NOT_CLIENT`
	 * if called from the server.
	 */
	interface ClientCarrier extends Carrier {
		/** Fires an event at the server. */
		Emit(event: string, ...args: Array<unknown>): void;
		/**
		 * Yields until the server's `When` responder replies, or until
		 * `Timeout`. Returns nothing on timeout.
		 */
		Call<R extends Array<unknown> = Array<unknown>>(
			event: string,
			...args: Array<unknown>
		): LuaTuple<R>;
		/**
		 * Asks the server for the staged table captured under `id` and starts
		 * following it. Throws `ERR_CAPTURE_DENIED` if a capture guard refused.
		 */
		RequestTable<T = Record<string, unknown>>(id: string): StageTable<T>;
		/** Round-trip time in seconds, measured with an internal ping event. */
		Ping(): number;
		/** Runs the server's handshake check and returns whether it passed. */
		Handshake(...args: Array<unknown>): boolean;

		/**
		 * Listens for a server event. No player is passed — `packet.player` is
		 * only populated when `IS_SERVER`.
		 *
		 * Pass the payload tuple to type the arguments:
		 * `On<[number, string]>("Hit", (damage, kind) => ...)`
		 */
		On<A extends Array<unknown> = Array<unknown>>(
			event: string,
			Callback: (...args: A) => void,
		): void;
		/**
		 * Sets the single responder for a server `CallTo`; return values are
		 * sent back. Pass no callback to clear it.
		 */
		When<A extends Array<unknown> = Array<unknown>, R = unknown>(
			event: string,
			Callback?: (...args: A) => R,
		): void;
	}

	/**
	 * The full runtime surface of a carrier, matching the Luau `PigeonCarrier`
	 * type. Prefer annotating with `ServerCarrier` or `ClientCarrier` so the
	 * compiler catches calls that would throw on the side you are running on.
	 */
	type PigeonCarrier = ServerCarrier & ClientCarrier;

	/** Argument payload as it travels over the wire; `n` preserves trailing `nil`s. */
	interface Payload {
		args: Array<unknown>;
		n: number;
	}

	/** Counters returned by `Network.Diagnostics`. */
	interface NetworkDiagnostics {
		listeners: number;
		watchers: number;
		orphaned: number;
		pending: number;
		readySeats: number;
		bufferedPackets: number;
		readyChannels: number;
		bufferedChannels: number;
		outbound: number;
	}

	/**
	 * The shared transport under every carrier. Exposed as `Pigeon.Network`
	 * for tooling and diagnostics — prefer carriers for normal traffic.
	 *
	 * Every member is defined with a dot in Luau, so they are all properties
	 * here and compile to `Pigeon.Network.Foo(...)`.
	 */
	interface Network {
		/** How many transformers are currently registered; drives the ref pool size. */
		readonly KnownTransformers: number;

		/** Size of the `RemoteEvent` pool (1-32 on the server; the published attribute on the client). */
		GetRefCount: () => number;
		/** Counts up a transformer and, on the server, resizes/creates the ref pool. */
		Register: (Transformer: Transformer) => void;
		/** Counts a transformer back down and resyncs the pool on the server. */
		Unregister: (Transformer: Transformer) => void;
		/** The `RemoteEvent` this transformer's traffic is hashed onto. Yields on the client until it exists. */
		GetRef: (Transformer: Transformer) => RemoteEvent;

		/**
		 * Listens for one exact wire event. Any packets held for it are
		 * replayed immediately. Returns a disconnect function.
		 */
		Receive: (event: string, callback: (...args: Array<unknown>) => void) => () => void;
		/**
		 * Listens for every event on a channel (the carrier name before the
		 * `\0` separator). Returns a disconnect function.
		 */
		ReceiveChannel: (
			channel: string,
			callback: (event: string, ...args: Array<unknown>) => void,
		) => () => void;

		/** Snapshot of the transport's internal queue sizes. */
		Diagnostics: () => NetworkDiagnostics;

		/** Client -> server: marks a channel ready so the server flushes its buffer. */
		Ready: (Transformer: Transformer, channel: string) => void;
		/** Client -> server: fire-and-forget push. */
		Push: (Transformer: Transformer, event: string, data: Payload, unreliable?: boolean) => void;
		/** Server -> clients: fire-and-forget push, buffered per player until they are ready. */
		Broadcast: (
			players: Array<Player>,
			Transformer: Transformer,
			event: string,
			data: Payload,
			unreliable?: boolean,
		) => void;
		/**
		 * Client -> server request. Yields; returns `[ok, response]`, where a
		 * failure carries `"timeout"`.
		 */
		Call: (
			Transformer: Transformer,
			event: string,
			data: Payload,
			timeout?: number,
		) => LuaTuple<[boolean, unknown]>;
		/** Replies to a request on the bucket it arrived on. `player` is required on the server. */
		Respond: (bucket: number, promiseId: number, data: Payload | undefined, player?: Player) => void;
		/**
		 * Server -> clients request. Yields until every player answers, one
		 * leaves, or the timeout elapses; the success value is a map of player
		 * to response.
		 */
		BroadcastCall: (
			players: Array<Player>,
			Transformer: Transformer,
			event: string,
			data: Payload,
			timeout?: number,
		) => LuaTuple<[boolean, unknown]>;
	}
}

interface PigeonModule {
	/** The shared transport. See {@link Pigeon.Network}. */
	readonly Network: Pigeon.Network;
	/**
	 * The `Types` module. It is a pure type module and evaluates to the literal
	 * `true` at runtime — the types themselves live in the `Pigeon` namespace.
	 */
	readonly Types: true;

	/**
	 * Creates (or reuses) a carrier. Carriers created without `options` are
	 * cached by name, so calling `new("Combat")` on both sides of the same
	 * script returns the same object; passing `options` always builds a fresh,
	 * uncached carrier.
	 *
	 * Throws `ERR_NO_NAME` on an empty name and `ERR_NO_TRANSFORMER` if
	 * `options.Transformer` is not a transformer.
	 *
	 * Pick the side to get the right `On`/`When` shape. `PigeonCarrier` merges
	 * both halves, and in an intersection TypeScript resolves `On` to the
	 * server overload — which is why the client otherwise sees a stray
	 * `player` first argument:
	 *
	 * ```ts
	 * const Net = Pigeon.new<Pigeon.ClientCarrier>("Network"); // On(...args)
	 * const Net = Pigeon.new<Pigeon.ServerCarrier>("Network"); // On(player, ...args)
	 * ```
	 */
	new: <C extends Pigeon.Carrier = Pigeon.PigeonCarrier>(
		name: string,
		options?: Pigeon.CarrierOptions,
	) => C;

	/**
	 * Creates a staged table seeded with `initial`. Throws if the seed holds
	 * anything but plain Roblox data.
	 */
	StagedTable: <T = Record<string, unknown>>(initial?: T) => Pigeon.StageTable<T>;

	/** Creates a lifetime owner. `uuid` defaults to a fresh GUID. */
	Transformer: (uuid?: string) => Pigeon.Transformer;

	/** The `RemoteEvent` a transformer's traffic is hashed onto. */
	GetRef: (transformer: Pigeon.Transformer) => RemoteEvent;
}

declare const Pigeon: PigeonModule;

export = Pigeon;
