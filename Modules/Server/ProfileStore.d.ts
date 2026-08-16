/**
 * Type declarations for **ProfileStore** (MAD STUDIO, by loleris).
 *
 * WARNINGS for values stored in `Profile.Data`:
 * - No numeric tables with gaps, and no mixed number/string keyed tables.
 * - Index tables by numbers and strings only.
 * - Never reference Instances, userdata (Vector3, Color3, CFrame...) or functions.
 *   Serialize userdata before storing it.
 */

declare namespace ProfileStore {
	/** Returned by every `Connect` call. */
	interface Connection {
		Disconnect(): void;
	}

	/**
	 * ProfileStore's own signal implementation — this is NOT an `RBXScriptSignal`,
	 * so it has no `Wait()`/`Once()` in its documented API.
	 */
	interface Signal<F extends Callback> {
		Connect(listener: F): Connection;
	}

	type DataStoreState = "NotReady" | "NoInternet" | "NoAccess" | "Access";

	/** Reason passed to `Profile.OnLastSave`. */
	type LastSaveReason = "Manual" | "External" | "Shutdown";

	type ConstantName =
		| "AUTO_SAVE_PERIOD"
		| "LOAD_REPEAT_PERIOD"
		| "FIRST_LOAD_REPEAT"
		| "SESSION_STEAL"
		| "ASSUME_DEAD"
		| "START_SESSION_TIMEOUT"
		| "CRITICAL_STATE_ERROR_COUNT"
		| "CRITICAL_STATE_ERROR_EXPIRE"
		| "CRITICAL_STATE_EXPIRE"
		| "MAX_MESSAGE_QUEUE";

	interface StartSessionParams {
		/** Disregard an existing session lock. */
		Steal?: boolean;
		/**
		 * Cancel condition. If this returns `true`, ProfileStore stops trying to
		 * start the session and returns `undefined`.
		 */
		Cancel?: () => boolean;
	}

	interface Session {
		PlaceId: number;
		JobId: string;
	}

	interface Profile<T extends object> {
		/**
		 * While the profile session is active, changes to this table are guaranteed
		 * to be saved.
		 */
		Data: T;
		/**
		 * Last snapshot of `Data` successfully saved to the DataStore. Useful for
		 * correct developer product receipt handling.
		 */
		readonly LastSavedData: T;
		/** `os.time()` timestamp of the first profile session. */
		readonly FirstSessionTime: number;
		/** Number of times a session has been started for this profile. */
		readonly SessionLoadCount: number;
		/** Set while this profile is in use by a server; `undefined` once released. */
		readonly Session: Session | undefined;
		/** Writable table saved automatically and once the profile is released. */
		RobloxMetaData: Record<string, unknown>;
		/** User ids associated with this profile. Mutate via `AddUserId`/`RemoveUserId`. */
		readonly UserIds: ReadonlyArray<number>;
		/** Changes before the `OnAfterSave` signal fires. */
		readonly KeyInfo: DataStoreKeyInfo;

		/** Fires right before changes to `Data` are saved to the DataStore. */
		readonly OnSave: Signal<() => void>;
		/** Fires right before the final save for this session. */
		readonly OnLastSave: Signal<(reason: LastSaveReason) => void>;
		/** Fires when the profile session is terminated on this server. */
		readonly OnSessionEnd: Signal<() => void>;
		/** Fires after a successful save, with `LastSavedData`. */
		readonly OnAfterSave: Signal<(lastSavedData: T) => void>;

		readonly ProfileStore: Store<T>;
		/** DataStore key. */
		readonly Key: string;

		/**
		 * When `true`, changes to `Data` are guaranteed to save. The guarantee is
		 * only valid until your code yields (e.g. `task.wait()`).
		 */
		IsActive(): boolean;
		/** Fills in missing `[string_key] = value` pairs from the store's template. */
		Reconcile(): void;
		/** Call once the server is finished with this profile, e.g. when the player leaves. */
		EndSession(): void;
		/** Associates a user id with the profile (GDPR compliance). */
		AddUserId(userId: number): void;
		/** Removes a user id association (safe to call when not present). */
		RemoveUserId(userId: number): void;
		/**
		 * Registers a handler for messages sent via `MessageAsync`. Call
		 * `processed()` to discard the message from the profile's cache —
		 * otherwise other handlers will also receive it.
		 */
		MessageHandler<M = unknown>(fn: (message: M, processed: () => void) => void): void;
		/** Immediately saves profile data via an `UpdateAsync` call, if the session is active. */
		Save(): void;
		/**
		 * Forcefully saves changes. Only valid for profiles loaded through
		 * `GetAsync` or `VersionQuery` (view mode).
		 */
		SetAsync(): void;
	}

	interface VersionQuery<T extends object> {
		/** Yields. The returned profile is in view mode, like `GetAsync` results. */
		NextAsync(): Profile<T> | undefined;
	}

	/** The methods shared by a live store and its `.Mock` counterpart. */
	interface StoreMethods<T extends object> {
		/** DataStore name. */
		readonly Name: string;
		/** Yields. Returns `undefined` if the session could not be started. */
		StartSessionAsync(profileKey: string, params?: StartSessionParams): Profile<T> | undefined;
		/** Yields. Sends a message to the profile; returns whether it succeeded. */
		MessageAsync(profileKey: string, message: object): boolean;
		/** Yields. Reads a profile without starting a session — it will not autosave. */
		GetAsync(profileKey: string, version?: string): Profile<T> | undefined;
		VersionQuery(
			profileKey: string,
			sortDirection?: Enum.SortDirection,
			minDate?: DateTime | number,
			maxDate?: DateTime | number,
		): VersionQuery<T>;
		/** Yields. Permanently removes profile data with no way to recover it. */
		RemoveAsync(profileKey: string): boolean;
	}

	/** A ProfileStore object, as returned by `ProfileStore.New`. */
	interface Store<T extends object> extends StoreMethods<T> {
		/**
		 * Mirrors the store's methods, but queries a mock DataStore with no
		 * relation to the real one.
		 */
		readonly Mock: StoreMethods<T>;
	}
}

interface ProfileStoreModule {
	/** Set to `true` after a `game:BindToClose()` trigger. */
	readonly IsClosing: boolean;
	/** Set to `true` when ProfileStore hits too many consecutive errors. */
	readonly IsCriticalState: boolean;
	/** Most ProfileStore errors are caught and passed to this signal. */
	readonly OnError: ProfileStore.Signal<
		(message: string, storeName: string, profileKey: string) => void
	>;
	/** Fires when a DataStore key held data that wasn't a valid ProfileStore profile. */
	readonly OnOverwrite: ProfileStore.Signal<(storeName: string, profileKey: string) => void>;
	readonly OnCriticalToggle: ProfileStore.Signal<(isCritical: boolean) => void>;
	/**
	 * ProfileStore's access to the DataStore. Starts as `"NotReady"` and
	 * eventually settles on one of the other three values.
	 */
	readonly DataStoreState: ProfileStore.DataStoreState;

	/**
	 * Creates a ProfileStore object for the given DataStore name. Profiles
	 * default to a hard copy of `template` when no data was saved previously.
	 *
	 * Declared as a property, not a method — ProfileStore defines it with a dot
	 * (`function ProfileStore.New`), so it must compile to `ProfileStore.New(...)`.
	 */
	New: <T extends object>(storeName: string, template?: T) => ProfileStore.Store<T>;

	/** Overrides one of ProfileStore's internal timing constants. */
	SetConstant: (name: ProfileStore.ConstantName, value: number) => void;
}

declare const ProfileStore: ProfileStoreModule;

export = ProfileStore;
