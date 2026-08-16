/**
 * Type declarations for **Scythe** (checcerr | fridayqx, MPL-2.0) — a
 * data-oriented cleanup library.
 *
 * There are no objects and no metatables here: a scope is a plain integer
 * handle into module-level structure-of-arrays storage, and every API member is
 * a free function defined with a dot. That means all of them are declared as
 * properties and compile to `Scythe.add(scope, value)` — never a colon call.
 *
 * Cleanup runs LIFO (reverse insertion). Handles are generation-tagged, so
 * touching one after `destroy` raises instead of silently aliasing a newer
 * scope. Disposers may `add`/`remove`/`clean`/`destroy` their own scope, but
 * they must never yield.
 */

declare namespace Scythe {
	/**
	 * An opaque, generation-tagged integer handle to a cleanup scope.
	 *
	 * It is a plain number — cheap to store, pass and compare — but never do
	 * arithmetic on one or fabricate one: it packs a slot index and a
	 * generation counter together.
	 */
	type Scope = number;
}

interface ScytheModule {
	/**
	 * Acquires a cleanup scope. Slots are pooled with their item arrays kept
	 * warm, so in steady state this allocates nothing.
	 */
	scope: () => Scythe.Scope;

	/**
	 * Tracks `value` and returns it unchanged, so the call can be inlined into
	 * an expression. The disposal method is resolved exactly once, here:
	 *
	 * | Value | On clean |
	 * |---|---|
	 * | `RBXScriptConnection` | `:Disconnect()` |
	 * | `Instance` | `:Destroy()` |
	 * | function | called |
	 * | thread | `task.cancel()` |
	 * | table/userdata with callable `Destroy` | `:Destroy()` |
	 * | table/userdata with callable `Disconnect` | `:Disconnect()` |
	 * | another `Scope` | `Scythe.destroy()` |
	 *
	 * Throws for anything else — an uncleanable value is a leak. Adding the
	 * same value twice disposes it twice.
	 */
	add: <T>(scope: Scythe.Scope, value: T) => T;

	/**
	 * Tracks many values in one call and returns nothing. Same per-value
	 * semantics as `add` (later arguments dispose first), but the tag buffer
	 * grows once for the whole batch and the batch is atomic: if any value has
	 * no cleanup path, nothing is tracked at all.
	 */
	addBulk: (scope: Scythe.Scope, ...values: Array<unknown>) => void;

	/**
	 * Stops tracking one value WITHOUT disposing it — use when ownership moves
	 * elsewhere. Swap-removal, so the order of the remaining items may change.
	 * Identity is compared with `rawequal`, so a custom `__eq` cannot fool it.
	 * Returns whether the value was found.
	 */
	remove: (scope: Scythe.Scope, value: unknown) => boolean;

	/**
	 * Disposes everything in LIFO order and empties the scope. The handle stays
	 * valid and its capacity stays warm. Every disposer runs even if earlier
	 * ones threw; a single aggregated error is raised once the scope is empty.
	 */
	clean: (scope: Scythe.Scope) => void;

	/**
	 * Disposes everything like `clean`, then recycles the slot. The handle is
	 * dead afterwards — reusing or re-destroying it raises. Calling this from
	 * inside a disposer defers the recycle until the drain finishes.
	 */
	destroy: (scope: Scythe.Scope) => void;

	/** Live item count. One buffer read — effectively free. */
	count: (scope: Scythe.Scope) => number;

	/**
	 * Non-throwing liveness check. `false` for destroyed, stale, malformed or
	 * never-allocated handles.
	 */
	isAlive: (scope: Scythe.Scope) => boolean;
}

declare const Scythe: ScytheModule;

export = Scythe;
