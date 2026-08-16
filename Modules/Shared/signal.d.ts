/**
 * Type declarations for `signal.luau`.
 *
 * `new` and `wrap` are declared as properties (not methods) because the Luau
 * defines them with a dot — they must compile to `Signal.new(...)`. Everything
 * on the Signal/Connection objects takes `self`, so those stay method syntax
 * and compile to colon calls.
 */

declare namespace Signal {
	interface Connection {
		/** Removes this connection from its signal so the callback no longer runs. */
		Disconnect(): void;
		/**
		 * Wraps the callback in extra logic; the wrapper gets the original
		 * callback plus the fired args and decides if/how to run it.
		 * Stacks — newest runs outermost.
		 */
		Extend(wrapper: (original: Callback, ...args: Array<unknown>) => unknown): Connection;
		readonly src: Callback;
	}

	/**
	 * Runs before listeners on Fire/Invoke. Return `true` plus the args to
	 * forward, or `false` to block the fire.
	 */
	type MiddlewareFunction = (
		...args: Array<unknown>
	) => LuaTuple<[boolean, ...Array<unknown>]>;

	/** Note the spelling — `"Deffered"` is the literal the module compares against. */
	type Mode = "Deffered" | "Serial";

	interface Signal<T extends Array<unknown> = Array<unknown>> {
		/**
		 * `"Deffered"` runs listener threads via `task.defer`; `"Serial"` runs
		 * them one after another, which can lead to long waits.
		 */
		Mode: Mode;

		/** Runs the callback every time the signal fires. */
		Connect(sink: (...args: T) => unknown): Connection;
		/** Runs the callback on the next fire only, then disconnects. */
		Once(sink: (...args: T) => unknown): Connection;

		/** Fires all listeners (and resumes `Await`-ing threads) with the given args. */
		Fire(...args: T): void;

		/** Fires serially and returns the last non-empty value returned by a listener. */
		Invoke(...args: T): unknown;
		/** Fires serially and returns every non-empty return, packed, in a list. */
		InvokePersitent(...args: T): Array<Array<unknown>>;

		/** Adds middleware that can transform or block fires; runs in the order added. */
		Use(middleware: MiddlewareFunction): void;
		/** Forwards every fire into `target`; disconnect the returned connection to stop. */
		Pipe(target: Signal<T>): Connection;
		/** True if anything is currently connected. */
		HasConnections(): boolean;

		/** Yields until the next fire, returning its args. */
		Await(): LuaTuple<T>;
		/** Like `Await`, but resumes with no values after `timeout` seconds. */
		AwaitFor(timeout: number): LuaTuple<T>;

		/** Disconnects everything, clears middleware, unhooks any wrapped RBXScriptSignal. */
		Destroy(): void;
	}
}

interface SignalModule {
	/** Creates a new signal. Defaults to `"Serial"` mode. */
	new: <T extends Array<unknown> = Array<unknown>>(Mode?: Signal.Mode) => Signal.Signal<T>;
	/** Wraps an `RBXScriptSignal` so it can be piped/extended like a native signal. */
	wrap: <T extends Array<unknown> = Array<unknown>>(
		rbxSignal: RBXScriptSignal,
		Mode?: Signal.Mode,
	) => Signal.Signal<T>;
}

declare const Signal: SignalModule;

export = Signal;
