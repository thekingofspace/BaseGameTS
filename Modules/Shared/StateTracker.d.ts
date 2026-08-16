/**
 * Type declarations for `StateTracker.luau` — a tiny observable state holder.
 *
 * `new` is declared as a property because the Luau defines it with a dot
 * (`function module.new`), so it must compile to `StateTracker.new(...)`.
 * Everything on the state object is defined with a colon on the metatable and
 * stays method syntax.
 */

declare namespace StateTracker {
	interface State<T> {
		/** The value the tracker currently holds. Read it, don't assign it. */
		currentState: T;

		/**
		 * Replaces the current state and runs every listener with
		 * `(newState, oldState)`.
		 *
		 * Throws if an `allowedStates` list was given and `state` is not in it,
		 * and does nothing when the checker (see `setChecker`) returns `false`.
		 */
		setState(state: T): void;

		/**
		 * Registers a callback run on every accepted `setState`. There is no
		 * disconnect — listeners live as long as the tracker.
		 *
		 * `oldState` is `undefined` when the callback is run through `Update`.
		 */
		listenTo(callback: (state: T, oldState: T) => void): void;

		/**
		 * Installs a guard run before each transition. Returning a falsy value
		 * rejects the change. Only one checker is held — the last call wins.
		 */
		setChecker(checker: (old: T, next: T) => boolean): void;

		/** Re-runs every listener with the current state and no old state. */
		Update(): void;
	}
}

interface StateTrackerModule {
	/**
	 * Creates a state tracker seeded with `stateDef`. When `allowedStates` is
	 * supplied, `setState` asserts the new value appears in that list.
	 */
	new: <T>(stateDef: T, allowedStates?: Array<T>) => StateTracker.State<T>;
}

declare const StateTracker: StateTrackerModule;

export = StateTracker;
