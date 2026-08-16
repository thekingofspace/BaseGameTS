/**
 * Type declarations for **QuickZone** — a spatial partitioning library for Roblox.
 *
 * The three moving parts:
 * - **Zone** — a passive volume in world space. Does nothing until attached to an Observer.
 * - **Group** — a collection of entities whose positions get sampled by the scheduler.
 * - **Observer** — the bridge. It subscribes to Groups, has Zones attached to it, and
 *   fires enter/exit events for group members crossing those zones.
 *
 * Dot vs colon: `Zone.new`, `Zone.fromPart`, `Zone.fromParts`, `Observer.new`,
 * `Group.new`, `Group.players` and `Group.localPlayer` are all defined with a dot and
 * take no `self`, so they are declared as properties and compile to `Zone.new(...)`.
 * Everything on a Zone/Observer/Group instance takes `self`, as does every function on
 * the module table itself (`function QuickZone:getZones()`), so those stay method
 * syntax and compile to colon calls.
 */

declare namespace QuickZone {
	/** The geometric shape of a Zone. */
	type ShapeType = "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge";

	/**
	 * A custom table that mimics the spatial properties of a Roblox Instance.
	 * QuickZone detects which property to use to track it, checking in the order
	 * `Position`, `CFrame`, `WorldPosition`, `GetPivot`.
	 */
	interface EntityTable {
		Position?: Vector3;
		WorldPosition?: Vector3;
		CFrame?: CFrame;
		/** Declared as a method — the scheduler invokes it as `entity:GetPivot()`. */
		GetPivot?(): CFrame;
		[key: string]: unknown;
	}

	/**
	 * Anything that can be tracked inside a Group: a native Roblox Instance with a
	 * position, or a duck-typed table.
	 */
	type Entity = BasePart | Model | Camera | Attachment | Bone | EntityTable;

	/**
	 * Signature of the raw `onEntered`/`onExited` listeners. `metadata` is whatever
	 * was passed to `Group:add(entity, metadata)`.
	 */
	type Callback = (entity: Entity, zone: Zone, metadata: unknown) => void;

	/** Returned by every `on*` / `observe*` call. Invoke it to stop listening. */
	type Disconnect = () => void;

	/**
	 * The optional cleanup an `observe*` callback may return. It runs when the
	 * entity exits, or when the whole observation is torn down.
	 */
	type Cleanup = (() => void) | void;

	interface ZoneConfig {
		cframe: CFrame;
		size: Vector3;
		/** Defaults to `"Block"`. An unrecognised value warns and falls back to `"Block"`. */
		shape?: ShapeType;
		/** Reference part, used later by `syncToPart` / `getPart`. */
		part?: BasePart;
		/** Set `true` for zones that move or resize — static zones are far costlier to update. */
		isDynamic?: boolean;
		metadata?: unknown;
		/** Observers attached at construction time. */
		observers?: Array<Observer>;
	}

	/** Config accepted by `Zone.fromPart` / `Zone.fromParts` — shape comes from the part. */
	interface ZonePartConfig {
		isDynamic?: boolean;
		metadata?: unknown;
		observers?: Array<Observer>;
	}

	interface ObserverConfig {
		/** Resolution priority. When an entity sits in zones watched by several
		 * observers, the higher priority observer takes control. Defaults to `0`. */
		priority?: number;
		/**
		 * Accepted by the constructor but currently ignored — a new Observer is
		 * always created enabled. Use `setEnabled(false)` afterwards instead.
		 */
		enabled?: boolean;
		/** Wrap callbacks in `task.spawn`. Defaults to the global config (`true`). */
		safety?: boolean;
		/** Groups subscribed to at construction time. */
		groups?: Array<Group>;
	}

	interface GroupConfig {
		/** Position sample frequency in Hz. Must be `> 0`. Defaults to `30`. */
		updateRate?: number;
		/** Minimum movement in studs before a spatial query re-runs. Must be `>= 0`. Defaults to `0.1`. */
		precision?: number;
		/** Entities added at construction time. */
		entities?: Array<Entity>;
	}

	/** The subset of `GroupConfig` accepted by `Group:setConfig`. */
	interface GroupTuning {
		updateRate?: number;
		precision?: number;
	}

	/** Snapshot returned by `Group:getConfig`. `precision` is in studs, not squared. */
	interface GroupConfigSnapshot {
		updateRate: number;
		precision: number;
	}

	/**
	 * Zones define physical areas in world space. They are passive — a Zone does
	 * nothing until an Observer is attached to it.
	 */
	interface Zone {
		/** Attaches an Observer, which then starts monitoring this area. */
		attach(observer: Observer): Zone;
		/** Detaches an Observer from this zone. */
		detach(observer: Observer): Zone;
		/**
		 * Updates the zone to its reference part's current CFrame, size and shape.
		 * Warns and no-ops when the zone has no reference part.
		 */
		syncToPart(): Zone;
		/** Updates the zone's CFrame. Requests a tree rebuild (batched per frame). */
		setCFrame(cf: CFrame): Zone;
		/** Updates the zone's position, preserving its rotation. */
		setPosition(pos: Vector3): Zone;
		/** Updates the zone's full size (not half-size). */
		setSize(size: Vector3): Zone;
		/** Updates the zone's shape. Does not require a tree rebuild. */
		setShape(shape: ShapeType): Zone;
		/** Sets the metadata handed to Observer callbacks alongside this zone. */
		setMetadata(metadata?: unknown): Zone;
		getMetadata(): unknown;
		/** The unique internal id of the zone. */
		getId(): number;
		/** The reference BasePart, if the zone was built from one. */
		getPart(): BasePart | undefined;
		getPosition(): Vector3;
		getCFrame(): CFrame;
		/** The full size of the zone. */
		getSize(): Vector3;
		getShape(): ShapeType;
		/** Every Observer currently attached to this zone. */
		getObservers(): Array<Observer>;
		/** Whether the zone lives in the dynamic tree. */
		isDynamic(): boolean;
		/** Point-in-volume test against this zone only. */
		isPointInside(point: Vector3): boolean;
		/** Removes the zone from the tree and detaches all observers. */
		destroy(): void;
	}

	interface ZoneClass {
		/**
		 * Creates a Zone from an explicit CFrame and size.
		 * Requests a rebuild of the corresponding tree (batched per frame).
		 */
		new: (config: ZoneConfig) => Zone;
		/**
		 * Creates a Zone matching a BasePart's CFrame, size and shape.
		 * Supported shapes: Block, Ball, Cylinder, Wedge and CornerWedge; anything
		 * else (meshes, unions, trusses) falls back to Block.
		 */
		fromPart: (part: BasePart, config?: ZonePartConfig) => Zone;
		/** Creates one Zone per BasePart, all sharing the same config. */
		fromParts: (parts: Array<BasePart>, config?: ZonePartConfig) => Array<Zone>;
	}

	/**
	 * Observers are the logical bridge between Groups and Zones. They monitor
	 * subscribed groups and fire events when those entities enter or exit any zone
	 * attached to the observer.
	 */
	interface Observer {
		/** Starts monitoring a group. Only entities in subscribed groups are tracked. */
		subscribe(group: Group): Observer;
		/** Stops monitoring a group, firing exit events for its members first. */
		unsubscribe(group: Group): Observer;

		/** Updates the resolution priority used to break overlaps between observers. */
		setPriority(n: number): Observer;
		/** When disabled, the observer stops spatial checks and fires exit events. */
		setEnabled(enabled: boolean): Observer;
		/** Whether callbacks are wrapped in `task.spawn` (safe) or called inline (fast). */
		setSafety(enabled: boolean): Observer;

		isEnabled(): boolean;
		isSafe(): boolean;
		/** Tests the player's `HumanoidRootPart`; `false` if there is no character. */
		isPlayerInside(player: Player): boolean;
		/** Client only — errors when called on the server. */
		isLocalPlayerInside(): boolean;
		isEntityInside(entity: Entity): boolean;
		/** Tests a world point against every zone attached to this observer. */
		isPointInside(position: Vector3): boolean;

		/** Every tracked entity currently inside one of this observer's zones. */
		getEntitiesInside(): Array<Entity>;
		/** The unique internal id of the observer. */
		getId(): number;
		getPriority(): number;
		/** Every Zone this observer is attached to. */
		getZones(): Array<Zone>;
		/** Every Group this observer is subscribed to. */
		getGroups(): Array<Group>;

		/**
		 * Runs the callback when an entity enters. Return a function from it to run
		 * on exit. The returned function stops observing entirely.
		 */
		observe(callback: (entity: Entity, zone: Zone, metadata: unknown) => Cleanup): Disconnect;
		/** `observe`, narrowed to Player entities. */
		observePlayer(callback: (player: Player, zone: Zone) => Cleanup): Disconnect;
		/** Client only — `observe`, narrowed to the LocalPlayer. */
		observeLocalPlayer(callback: (zone: Zone) => Cleanup): Disconnect;
		/**
		 * Fires when the first member of a group arrives; the returned cleanup runs
		 * once the last member has left.
		 */
		observeGroup(callback: (group: Group, zone: Zone) => Cleanup): Disconnect;

		/** Fires when any entity from a subscribed group enters an attached zone. */
		onEntered(callback: Callback): Disconnect;
		/** Fires when an entity exits *all* zones attached to this observer. */
		onExited(callback: Callback): Disconnect;
		/** Specialized enter event for Player entities. */
		onPlayerEntered(callback: (player: Player, zone: Zone) => void): Disconnect;
		/** Specialized exit event for Player entities. */
		onPlayerExited(callback: (player: Player, zone: Zone) => void): Disconnect;
		/** Client only — specialized enter event for the LocalPlayer. */
		onLocalPlayerEntered(callback: (zone: Zone) => void): Disconnect;
		/** Client only — specialized exit event for the LocalPlayer. */
		onLocalPlayerExited(callback: (zone: Zone) => void): Disconnect;
		/** Fires when the first member of a group enters an attached zone. */
		onGroupEntered(callback: (group: Group, zone: Zone) => void): Disconnect;
		/** Fires when the last remaining member of a group exits all attached zones. */
		onGroupExited(callback: (group: Group, zone: Zone) => void): Disconnect;

		/** Disables tracking and unsubscribes the observer from all groups and zones. */
		destroy(): void;
	}

	interface ObserverClass {
		/** Creates an Observer. Observers listen for entities entering/exiting attached Zones. */
		new: (config?: ObserverConfig) => Observer;
	}

	/**
	 * Groups are collections of entities the scheduler samples. Every entity must
	 * belong to a group before an Observer can see it.
	 */
	interface Group {
		/**
		 * Adds an entity. If it already belongs to another group it is removed from
		 * that one first. The tracking strategy is detected automatically: BasePart
		 * uses `Position`, Model uses `PrimaryPart.Position` or `GetPivot()`,
		 * Attachment/Bone use `WorldPosition`, Camera uses `CFrame`, and tables are
		 * probed for `Position` / `CFrame` / `WorldPosition` / `GetPivot`.
		 */
		add(entity: Entity, metadata?: unknown): Group;
		/** Adds several entities, applying the same metadata to each. */
		addBulk(entities: Array<Entity>, metadata?: unknown): Group;
		/** Removes an entity, firing exit events for any zone it was inside. */
		remove(entity: Entity): Group;
		removeBulk(entities: Array<Entity>): Group;
		/** Removes every entity, firing exit events for each. */
		clear(): Group;

		/** Updates update rate and/or precision. Asserts on non-positive values. */
		setConfig(config: GroupTuning): Group;
		setUpdateRate(updateRate: number): Group;
		setPrecision(precision: number): Group;

		getUpdateRate(): number;
		getPrecision(): number;
		/** The unique internal id of the group. */
		getId(): number;
		/** A copy of the group's entity list. */
		getEntities(): Array<Entity>;
		/** Every Observer currently subscribed to this group. */
		getObservers(): Array<Observer>;
		getConfig(): GroupConfigSnapshot;
		contains(entity: Entity): boolean;

		/** Removes all tracked entities and detaches associated observers. */
		destroy(): void;
	}

	interface GroupClass {
		/** Creates a generic Group. */
		new: (config?: GroupConfig) => Group;
		/**
		 * Returns the singleton Group that tracks every player's `HumanoidRootPart`,
		 * handling `PlayerAdded`/`CharacterAdded` internally. Passing a config to an
		 * already-created singleton reconfigures it instead of making a new one.
		 *
		 * On the client, the local player is excluded while a `localPlayer` group exists.
		 */
		players: (config?: GroupConfig) => Group;
		/**
		 * Client only — returns the singleton Group tracking just the LocalPlayer.
		 * Destroying it hands the local player back to the `players` group, if one exists.
		 */
		localPlayer: (config?: GroupConfig) => Group;
	}
}

interface QuickZoneModule {
	readonly Zone: QuickZone.ZoneClass;
	readonly Observer: QuickZone.ObserverClass;
	readonly Group: QuickZone.GroupClass;

	/**
	 * Sets the scheduler's per-frame execution budget in milliseconds. The
	 * scheduler dispatches entity updates until the budget is spent, then yields
	 * to the next frame to avoid render stutter. Defaults to 1ms.
	 */
	setFrameBudget(ms: number): QuickZoneModule;
	/** Every Zone containing the given world point. */
	getZonesAtPoint(position: Vector3): Array<QuickZone.Zone>;
	/** Every Observer whose attached Zones contain the given world point. */
	getObserversAtPoint(position: Vector3): Array<QuickZone.Observer>;
	/** The Group the entity currently belongs to, if any. */
	getGroupOfEntity(entity: QuickZone.Entity): QuickZone.Group | undefined;
	/** Every registered Zone, static and dynamic. */
	getZones(): Array<QuickZone.Zone>;
	/** Every Observer in the system. */
	getObservers(): Array<QuickZone.Observer>;
	/** Every Group in the system, singletons included. */
	getGroups(): Array<QuickZone.Group>;
	/** A flattened list of every tracked Entity across all Groups. */
	getEntities(): Array<QuickZone.Entity>;
	/**
	 * Debug — toggles `BoxHandleAdornment` rendering for every registered Zone.
	 * Static and dynamic zones are coloured differently based on active status.
	 */
	visualize(enabled: boolean): QuickZoneModule;
}

declare const QuickZone: QuickZoneModule;

export = QuickZone;
