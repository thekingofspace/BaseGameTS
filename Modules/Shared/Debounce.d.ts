/**
 * Type declarations for `Debounce.luau`.
 *
 * A Debounce owns any number of categories; a category is a keyed cooldown
 * table. Keys are not stored — the arguments you pass are hashed into a single
 * number, so `(player, "Dash")` and `(otherPlayer, "Dash")` are separate
 * entries. Instances hash by `ClassName` + `Name`, everything else by its
 * `typeof` and `tostring`.
 *
 * `new` is declared as a property because the Luau defines it with a dot
 * (`function module.new`), so it compiles to `Debounce.new()`. Everything on
 * the Debounce/DebounceCategory objects takes `self`, so those stay methods.
 */

declare namespace Debounce {
	interface DebounceCategory {
		/**
		 * `true` when nothing is on cooldown for this key — an expired entry is
		 * cleared as a side effect. Throws once the category is destroyed.
		 */
		Check(...key: Array<unknown>): boolean;
		/**
		 * Puts the key on cooldown for `duration` seconds (`os.clock` based).
		 * A duration of zero or less clears the entry instead.
		 */
		Set(duration: number, ...key: Array<unknown>): void;
		/** Clears one key, or every key in the category when called with no args. */
		Clear(...key: Array<unknown>): void;
		/** Empties the category and detaches it from its owner. Idempotent. */
		Destroy(): void;
	}

	interface Debounce {
		/** Creates a category owned by this Debounce. Throws once destroyed. */
		Create(): DebounceCategory;
		/** Destroys every category this Debounce created. Idempotent. */
		Destroy(): void;
	}
}

interface DebounceModule {
	/** Creates an empty Debounce that owns no categories yet. */
	new: () => Debounce.Debounce;
}

declare const Debounce: DebounceModule;

export = Debounce;
