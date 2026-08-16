/**
 * Type declarations for **Blackbox** — the vendored logging / telemetry
 * framework in `ReplicatedStorage.Shared.Blackbox`.
 *
 * Requiring the module auto-runs `Blackbox.Start()`, which installs the console
 * sink, the global error guard and the `BindToClose` flush. Call `Start` again
 * with options to configure it; the extra setup only happens once.
 *
 * Call-syntax note: everything the Luau defines with a dot (`function Blackbox.Info`,
 * `function Guard.Spawn`, ...) is declared here as a **property with an arrow type**
 * so it compiles to `Blackbox.Info(...)`. Everything that takes `self`
 * (`Logger:Info`, `Fault:Wrap`, the memory sink's `Query`, ...) is declared as a
 * **method** so it compiles to a colon call.
 */

declare namespace Blackbox {
	// ────────────────────────────── Levels ──────────────────────────────

	/** The built-in level names. `Level.Register` can add more at runtime. */
	type LevelName = "TRACE" | "DEBUG" | "INFO" | "WARN" | "ERROR" | "FATAL" | "OFF";

	interface LevelModule {
		readonly TRACE: number;
		readonly DEBUG: number;
		readonly INFO: number;
		readonly WARN: number;
		readonly ERROR: number;
		readonly FATAL: number;
		readonly OFF: number;

		/** Name for a numeric level, e.g. `35` → `"INFO+5"`. */
		NameOf: (value: number) => string;
		/** Level names are matched case-insensitively. Returns `undefined` for unknown input. */
		Resolve: (level?: LevelName | string | number) => number | undefined;
		/** Like `Resolve`, but raises for an unknown level. */
		Expect: (level: LevelName | string | number, context?: string) => number;
		/** Adds a custom level. Raises if the name is already taken by a different value. */
		Register: (name: string, value: number) => void;
		/** A copy of every registered `name → value` pair. */
		All: () => Record<string, number>;
	}

	// ────────────────────────────── Traces ──────────────────────────────

	/** One frame of a captured stack. */
	interface TraceFrame {
		Source: string;
		Line: number;
		Name: string | undefined;
		/** `"Lua"`, or `"C"` for frames whose source is `[C]`. */
		What: string;
	}

	interface Trace {
		Frames: Array<TraceFrame>;
		/** The original traceback text, when the trace came from `FromTraceback`. */
		Raw: string | undefined;
	}

	/** The `Trace.luau` helpers, exposed on the module as `Blackbox.Stack`. */
	interface TraceModule {
		/** Captures the current stack, skipping Blackbox's own frames. */
		Capture: (skip?: number, limit?: number) => Trace;
		/** `"source:line"` of the caller, or `undefined` if unavailable. */
		Location: (skip?: number) => string | undefined;
		/** Parses a Roblox traceback string into frames. */
		FromTraceback: (raw: string) => Trace;
		/** Renders a trace as indented `at name (source:line)` lines. */
		Format: (trace?: Trace, indent?: string) => string;
		/** Flattens a trace to `"source:line:name"` strings for transport. */
		ToWire: (trace?: Trace) => Array<string> | undefined;
		/** Rebuilds a trace from `ToWire` output. */
		FromWire: (packed?: Array<string>) => Trace | undefined;
		/** Strips numbers, hex and uuids out of a message so it can be grouped. */
		Normalize: (message: string) => string;
		/** Stable hash of the normalized message plus the top three frames. */
		Fingerprint: (message: string, trace?: Trace, salt?: string) => string;
	}

	// ────────────────────────────── Faults ──────────────────────────────

	/** A structured error. Faults carry a kind, details, a trace and an optional cause chain. */
	interface Fault {
		/** Dotted kind, e.g. `"Network.Timeout"`. */
		Kind: string;
		Message: string;
		Details: Record<string, unknown>;
		Trace: Trace | undefined;
		/** The fault this one wrapped, if any. */
		Cause: Fault | undefined;
		/** `os.time()` when the fault was created. */
		Time: number;
		/** `os.clock()` when the fault was created. */
		Clock: number;
		Retryable: boolean;
		/** Set once a `Catch`/`Match` handler has dealt with the fault. */
		Handled: boolean;
		Fingerprint: string;

		/** True for an exact kind match or for any dotted child of `kind`. */
		Is(kind: string): boolean;
		/** Wraps this fault in a new one that keeps it as `Cause`. */
		Wrap(kind: string, message?: string, details?: Record<string, unknown>): Fault;
		/** Adds one detail key and returns the same fault, so calls can chain. */
		Detail(key: string, value: unknown): Fault;
		/** The deepest `Cause` in the chain. */
		Root(): Fault;
		/** This fault followed by every cause, outermost first. */
		Chain(): Array<Fault>;
		/** Multi-line render of the whole chain plus the trace. */
		ToString(): string;
		/** Sanitized plain table, safe to serialize or send over the wire. */
		ToTable(): Record<string, unknown>;
		/** Raises this fault. Never returns. */
		Throw(): never;
	}

	/** The result of `Try`/`Retry` — either the returned values or a fault. */
	interface Attempt {
		Ok(): boolean;
		/** The fault, or `undefined` when the call succeeded. */
		Fault(): Fault | undefined;
		/** First returned value. */
		Value<T = unknown>(): T | undefined;
		/** Every returned value. */
		Values(): LuaTuple<Array<unknown>>;

		/** Handles the fault only when its kind matches; the handler's returns replace the values. */
		Catch(kind: string, handler: (fault: Fault) => unknown): Attempt;
		/** Handles any fault; the handler's returns replace the values. */
		Catch(handler: (fault: Fault) => unknown): Attempt;
		/**
		 * Dispatches on fault kind — longest matching kind wins, with the
		 * `Default` key used as the fallback.
		 */
		Match(handlers: Record<string, (fault: Fault) => unknown>): Attempt;
		/** Always runs. A raise inside `fn` turns a successful attempt into a failed one. */
		Finally(fn: (ok: boolean, fault: Fault | undefined) => void): Attempt;

		/** Returns the values, or rethrows if the fault was never handled. */
		Unwrap(): LuaTuple<Array<unknown>>;
		/** Returns the values, or the given fallbacks if the attempt failed. */
		UnwrapOr(...fallbacks: Array<unknown>): LuaTuple<Array<unknown>>;
		/** Rethrows the fault, if there is one. */
		Rethrow(): void;
	}

	interface RetryOptions {
		/** Total tries, including the first. Defaults to `3`. */
		Attempts?: number;
		/** Seconds before the second try. Defaults to `0.5`. */
		Delay?: number;
		/** Delay multiplier between tries. Defaults to `2`. */
		Backoff?: number;
		/** Delay ceiling in seconds. Defaults to `30`. */
		MaxDelay?: number;
		/** Random spread applied to each delay, as a fraction. Defaults to `0.25`. */
		Jitter?: number;
		/** Return `false` to stop retrying early. */
		RetryIf?: (fault: Fault, attempt: number) => boolean;
		/** Called before each wait. */
		OnRetry?: (fault: Fault, attempt: number, delay: number) => void;
	}

	/** `Fault.luau`, exposed on the module as `Blackbox.Faults`. */
	interface FaultsModule {
		/** Creates a fault; `skip` drops that many frames from the captured trace. */
		new: (
			kind: string,
			message?: string,
			details?: Record<string, unknown>,
			skip?: number,
		) => Fault;
		IsFault: (value: unknown) => value is Fault;
		/** Turns anything raised — string, table, fault — into a fault. */
		Coerce: (value: unknown, skip?: number, defaultKind?: string) => Fault;
		/** Creates a fault and raises it. Never returns. */
		Throw: (kind: string, message?: string, details?: Record<string, unknown>) => never;
		/** Runs `fn` under `xpcall` and wraps the outcome in an `Attempt`. */
		Try: <A extends Array<unknown>>(fn: (...args: A) => unknown, ...args: A) => Attempt;
		/** Raises a fault of `kind` when `condition` is falsy; otherwise returns it. */
		Assert: <T>(
			condition: T,
			kind: string,
			message?: string,
			details?: Record<string, unknown>,
		) => T;
		/** Raises a fault of `kind` when `value` is nil; otherwise returns it. */
		Expect: <T>(value: T | undefined, kind: string, message?: string) => T;
		/** Retries `fn` with backoff; `fn` receives the 1-based attempt number first. */
		Retry: <A extends Array<unknown>>(
			options: RetryOptions,
			fn: (attempt: number, ...args: A) => unknown,
			...args: A
		) => Attempt;
		/** Wraps a function so every call returns an `Attempt` instead of raising. */
		Protect: <A extends Array<unknown>>(
			fn: (...args: A) => unknown,
		) => (...args: A) => Attempt;
		/** The metatable shared by every fault. Internal — exposed for advanced use. */
		readonly Meta: object;
	}

	// ────────────────────────── Entries and sinks ──────────────────────────

	interface Breadcrumb {
		Message: string;
		Category: string;
		Fields: Record<string, unknown> | undefined;
		Clock: number;
	}

	/** One log record, as handed to every sink. */
	interface Entry {
		Level: number;
		LevelName: string;
		/** Dotted name of the logger that produced the entry (`""` for the root). */
		Logger: string;
		Message: string;
		/** Logger fields, ambient span fields and global tags, already merged. */
		Fields: Record<string, unknown> | undefined;
		Fault: Fault | undefined;
		Trace: Trace | undefined;
		/** Attached once the entry is at or above the configured breadcrumb level. */
		Breadcrumbs: Array<Breadcrumb> | undefined;
		Time: number;
		Clock: number;
		Fingerprint: string;
		TraceId: string | undefined;
		SpanId: string | undefined;
		/** Name of the span that was open when the entry was written. */
		Span: string | undefined;
		Context: "Server" | "Client";
		/** How many duplicates the throttler folded into this entry. */
		Count: number;
	}

	/**
	 * A log destination. `Write` (and the optional `Filter`/`Flush`/`Close`) take
	 * `self`, so write them as methods when you build your own sink.
	 */
	interface Sink {
		Name: string;
		/** Entries below this level are skipped. */
		Level: number;
		Enabled: boolean;
		Write(entry: Entry): void;
		/** Return `false` to drop the entry. */
		Filter?(entry: Entry): boolean;
		Flush?(): void;
		Close?(): void;
	}

	/**
	 * A per-logger hook. Return `false` to stop the entry before it reaches any
	 * sink; anything else lets it through.
	 */
	type Hook = (entry: Entry) => boolean | void;

	interface ConsoleOptions {
		ShowTime?: boolean;
		ShowLevel?: boolean;
		ShowLogger?: boolean;
		ShowFields?: boolean;
		/** Prints the enclosing span name. Defaults to on in Studio. */
		ShowSpan?: boolean;
		/** Puts fields, faults and traces on their own lines. Defaults to on in Studio. */
		Multiline?: boolean;
		/** Prefixes each line with a per-level glyph. */
		Glyphs?: boolean;
		Traceback?: boolean;
		/** Routes output through `TestService`. Defaults to on in Studio. */
		UseTestService?: boolean;
	}

	/** Filter passed to the memory sink's `Query`/`Dump`. */
	interface Query {
		/** Minimum level. */
		Level?: string | number;
		/** Prefix match against the entry's logger name. */
		Logger?: string;
		/** Case-insensitive plain-text search over the message. */
		Text?: string;
		Fingerprint?: string;
		TraceId?: string;
		/** `os.time()` floor. */
		Since?: number;
		/** Defaults to `100`. */
		Limit?: number;
	}

	/** A repeated message, as returned by `Top`. */
	interface Frequency {
		Fingerprint: string;
		Count: number;
		Message: string;
		Level: string;
	}

	/** A ring-buffered sink that keeps entries in memory so they can be queried. */
	interface MemorySink extends Sink {
		/** Newest first. */
		Query(query?: Query): Array<Entry>;
		/** Every retained entry, oldest first. */
		All(): Array<Entry>;
		/** The most frequent fingerprints, highest count first. `limit` defaults to `10`. */
		Top(limit?: number): Array<Frequency>;
		/** Renders matching entries the way the console sink would. */
		Dump(query?: Query): string;
		Clear(): void;
		Count(): number;
		Resize(capacity: number): void;
	}

	/** `Sinks/Console.luau`, reachable as `Blackbox.Sinks.ConsoleModule`. */
	interface ConsoleSinkModule {
		/** True while the console sink is printing — used to ignore its own output. */
		Emitting: boolean;
		/** Consumes a remembered render so `LogService.MessageOut` echoes are dropped. */
		WasEmitted: (text: string) => boolean;
		/** Formats an entry exactly the way the console sink prints it. */
		Render: (entry: Entry, options?: ConsoleOptions) => string;
		/** Prefer `Blackbox.Sinks.Console`. */
		new: (options?: ConsoleOptions) => Sink;
	}

	/** `Sinks/Memory.luau`, reachable as `Blackbox.Sinks.MemoryModule`. */
	interface MemorySinkModule {
		/** Prefer `Blackbox.Sinks.Memory`. Capacity defaults to `512`. */
		new: (capacity?: number, level?: string | number) => MemorySink;
	}

	interface SinksModule {
		readonly ConsoleModule: ConsoleSinkModule;
		readonly MemoryModule: MemorySinkModule;

		/** A sink that prints to the output window (or `TestService`). */
		Console: (options?: ConsoleOptions) => Sink;
		/** A sink that retains entries in a ring buffer. Capacity defaults to `512`. */
		Memory: (capacity?: number, level?: string | number) => MemorySink;
		/** A sink that forwards every entry to your callback. */
		Callback: (
			name: string,
			callback: (entry: Entry) => void,
			level?: string | number,
		) => Sink;
		/** Wraps a sink so only entries passing `predicate` reach it. */
		Filtered: (sink: Sink, predicate: (entry: Entry) => boolean) => Sink;
	}

	// ────────────────────────────── Loggers ──────────────────────────────

	/** An open span. Always `Stop` it — the ambient stack is only popped there. */
	interface SpanHandle {
		readonly Id: string;
		readonly Name: string;
		readonly TraceId: string;
		/** Closes the span, logs it at DEBUG and returns the elapsed seconds. */
		Stop(fields?: Record<string, unknown>): number;
		/** Adds fields to this span and to the ambient context. */
		Annotate(fields: Record<string, unknown>): void;
	}

	interface Logger {
		/** Dotted path; the root logger's name is `""`. */
		readonly Name: string;
		/** Level override for this logger. `undefined` means inherit from the parent. */
		Level: number | undefined;

		Trace(message: string, fields?: Record<string, unknown>): void;
		Debug(message: string, fields?: Record<string, unknown>): void;
		Info(message: string, fields?: Record<string, unknown>): void;
		Warn(message: string, fields?: Record<string, unknown>): void;
		Error(message: string, fields?: Record<string, unknown>): void;
		/** Also flushes every sink and runs the `OnFatal` handlers. */
		Fatal(message: string, fields?: Record<string, unknown>): void;

		/** Coerces anything raised into a fault, logs it and returns it. */
		Exception(err: unknown, message?: string, fields?: Record<string, unknown>): Fault;
		/** Logs at an arbitrary level. Raises if the level is unknown. */
		Log(level: string | number, message: string, fields?: Record<string, unknown>): void;
		/** Logs at ERROR and returns `false` when `condition` is falsy. Never raises. */
		Ensure(condition: unknown, message: string, fields?: Record<string, unknown>): boolean;

		/** Gets or creates the registered `Name.name` child logger. */
		Child(name: string, fields?: Record<string, unknown>): Logger;
		/** An unregistered view of this logger that adds `fields` to every entry. */
		With(fields: Record<string, unknown>): Logger;

		/** Pass no level to clear the override and inherit again. Returns this logger. */
		SetLevel(level?: string | number): Logger;
		/** The level actually in force, walking up to the global config. */
		EffectiveLevel(): number;
		IsEnabled(level: string | number): boolean;

		/** Attaches a sink to this logger and its children. Returns the sink. */
		AddSink(sink: Sink): Sink;
		/** Removes a sink by reference or by name; closes it if it has `Close`. */
		RemoveSink(sink: Sink | string): boolean;
		/** Adds a hook and returns the function that removes it again. */
		Use(hook: Hook): () => void;

		/** Records a breadcrumb; they ride along on the next error-level entry. */
		Breadcrumb(message: string, category?: string, fields?: Record<string, unknown>): void;
		/** Opens a timed span and pushes it onto the ambient context. */
		Span(name: string, fields?: Record<string, unknown>): SpanHandle;
		/** Runs `fn` inside a span. Logs and rethrows if it raises. */
		Scope<A extends Array<unknown>, R>(name: string, fn: (...args: A) => R, ...args: A): R;
		/** Times `fn`, logs how long it took, and rethrows if it raises. */
		Time<A extends Array<unknown>, R>(name: string, fn: (...args: A) => R, ...args: A): R;

		/** Flushes every sink reachable from this logger. */
		Flush(): void;
		/** Closes this logger's sinks and stops it from emitting anything else. */
		Destroy(): void;
	}

	// ────────────────────────────── Config ──────────────────────────────

	interface Config {
		/** Minimum level that gets logged. Defaults to DEBUG in Studio, INFO live. */
		Level?: string | number;
		Console?: ConsoleOptions;
		/** Entries at or above this level capture a stack trace. Defaults to ERROR. */
		TraceLevel?: string | number;
		/** Entries at or above this level carry the breadcrumb buffer. Defaults to ERROR. */
		BreadcrumbLevel?: string | number;
		/** Breadcrumb ring size. Defaults to `32`. */
		BreadcrumbLimit?: number;
		/** History ring size. Defaults to `256`. */
		HistoryLimit?: number;
		/** Serializer depth limit. Defaults to `4`. */
		MaxDepth?: number;
		/** Serializer per-table entry limit. Defaults to `24`. */
		MaxEntries?: number;
		/** Serializer string limit. Defaults to `512`. */
		MaxStringLength?: number;
		/** Field-name substrings whose values get replaced with `<redacted>`. */
		RedactKeys?: Array<string>;
		/** Collapses repeat messages inside `DedupeWindow`. Defaults to `true`. */
		Dedupe?: boolean;
		/** Dedupe window in seconds. Defaults to `5`. */
		DedupeWindow?: number;
		/** Entries per second per logger. Defaults to `60`; `0` disables the limiter. */
		RateLimit?: number;
		/** Token-bucket burst size. Defaults to `120`. */
		RateBurst?: number;
		/** Per-level keep fraction, keyed by level name, e.g. `{ DEBUG: 0.1 }`. */
		Sample?: Record<string, number>;
		/** Hooks `ScriptContext.Error`. Defaults to `true`. */
		CaptureGlobalErrors?: boolean;
		/** Mirrors `LogService.MessageOut` into the log. Defaults to `false`. */
		CaptureOutput?: boolean;
		/** Fields merged into every entry, everywhere. */
		Tags?: Record<string, unknown>;
	}

	/** `Config` plus the one-time setup switches `Start` understands. */
	interface StartOptions extends Config {
		/** Extra sinks to attach to the root logger. */
		Sinks?: Array<Sink>;
		/** Skips the default console sink. */
		NoConsole?: boolean;
		/** Skips the global error / output capture. */
		NoGuard?: boolean;
		/** Skips the `game:BindToClose` flush. */
		NoBindToClose?: boolean;
	}

	// ────────────────────────────── Serialize ──────────────────────────────

	interface SerializeOptions {
		MaxDepth?: number;
		MaxEntries?: number;
		MaxStringLength?: number;
		/** Set `false` to keep values of redacted keys. Defaults to `true`. */
		Redact?: boolean;
		/** Indent string; set it to render multi-line. */
		Indent?: string;
	}

	interface SerializeModule {
		/** FNV-1a hash, rendered as eight hex characters. */
		Hash: (text: string) => string;
		/** One-line render of any value, cycle- and depth-safe. */
		Inspect: (value: unknown, options?: SerializeOptions) => string;
		/** Like `Inspect`, but indented across multiple lines. */
		Pretty: (value: unknown, options?: SerializeOptions) => string;
		/** Renders a field table as space-separated `key=value` pairs. */
		Fields: (fields?: Record<string, unknown>, options?: SerializeOptions) => string;
		/** Deep copy reduced to plain, JSON-safe values. */
		Sanitize: (value: unknown, options?: SerializeOptions) => unknown;
	}

	// ────────────────────────────── Metrics ──────────────────────────────

	interface HistogramSummary {
		Count: number;
		Sum: number;
		Min: number;
		Max: number;
		Mean: number;
		P50: number;
		P95: number;
		P99: number;
	}

	interface MetricsSnapshot {
		Counters: Record<string, number>;
		Gauges: Record<string, number>;
		Histograms: Record<string, HistogramSummary>;
	}

	/** A running timer. `Stop` records the elapsed seconds as an observation. */
	interface Stopwatch {
		readonly Name: string;
		/** Seconds since the start. Does not record anything. */
		Elapsed(): number;
		/** Records the elapsed seconds and returns them. Repeat calls are no-ops. */
		Stop(): number;
	}

	interface MetricsModule {
		/** Builds the `name{tag=value,...}` key used to store a metric. */
		Key: (name: string, tags?: Record<string, unknown>) => string;
		/** Adds `delta` (default `1`) to a counter and returns the new total. */
		Increment: (name: string, delta?: number, tags?: Record<string, unknown>) => number;
		/** Current counter value, or `0`. */
		Counter: (name: string, tags?: Record<string, unknown>) => number;
		/** Sets a gauge. */
		Set: (name: string, value: number, tags?: Record<string, unknown>) => void;
		/** Current gauge value, or `undefined` when it was never set. */
		Gauge: (name: string, tags?: Record<string, unknown>) => number | undefined;
		/** Records one sample into a histogram (reservoir of 256 samples). */
		Observe: (name: string, value: number, tags?: Record<string, unknown>) => void;
		/** Quantiles for a histogram, or `undefined` when nothing was observed. */
		Summary: (
			name: string,
			tags?: Record<string, unknown>,
		) => HistogramSummary | undefined;
		/** Starts a stopwatch that records into the histogram called `name`. */
		Start: (name: string, tags?: Record<string, unknown>) => Stopwatch;
		/** Times `fn`, then rethrows if it raised (also bumping `name.failed`). */
		Time: <A extends Array<unknown>, R>(
			name: string,
			fn: (...args: A) => R,
			...args: A
		) => R;
		/** Copy of every counter, gauge and histogram summary. */
		Snapshot: () => MetricsSnapshot;
		/** Human-readable dump of everything recorded so far. */
		Format: () => string;
		/** Drops every counter, gauge and histogram. */
		Reset: () => void;
	}

	// ────────────────────────────── Ambient ──────────────────────────────

	/** One entry on the per-thread span stack. */
	interface AmbientFrame {
		Name: string;
		SpanId: string;
		TraceId: string;
		Fields: Record<string, unknown> | undefined;
		Started: number;
	}

	/** A captured span stack, as handed between threads by `Capture`/`Adopt`/`Wear`. */
	type AmbientStack = Array<AmbientFrame>;

	/** Per-thread span context. Blackbox reads it to stamp trace and span ids on entries. */
	interface AmbientModule {
		/** Eight hex characters, optionally prefixed. */
		NewId: (prefix?: string) => string;
		/** Pushes a frame onto the running thread's stack. Prefer `Logger:Span`. */
		Push: (
			name: string,
			fields?: Record<string, unknown>,
			traceId?: string,
		) => AmbientFrame;
		/** Pops down to and including `frame`, or just the top frame when omitted. */
		Pop: (frame?: AmbientFrame) => AmbientFrame | undefined;
		/** The innermost open frame on this thread. */
		Current: () => AmbientFrame | undefined;
		TraceId: () => string | undefined;
		/** Every open frame's fields, merged outermost-first. */
		Fields: () => Record<string, unknown> | undefined;
		/** Adds fields to the innermost open frame. */
		Annotate: (fields: Record<string, unknown>) => void;
		/** The open span names joined with `" > "`. */
		Path: () => string | undefined;
		/** Copies this thread's stack so another thread can adopt it. */
		Capture: () => AmbientStack | undefined;
		/** Replaces the running thread's stack. Pass nothing to clear it. */
		Adopt: (captured?: AmbientStack) => void;
		/** Runs `fn` under a captured stack, then restores the previous one. */
		Wear: <A extends Array<unknown>, R>(
			captured: AmbientStack | undefined,
			fn: (...args: A) => R,
			...args: A
		) => R;
		/** Drops this thread's stack. */
		Clear: () => void;
	}

	// ────────────────────────────── Ring ──────────────────────────────

	/** A fixed-size ring buffer. */
	interface Ring<T> {
		/** How many values fit before the oldest start dropping. */
		readonly Capacity: number;
		Push(value: T): void;
		/** Up to `limit` values, oldest first. */
		Snapshot(limit?: number): Array<T>;
		/** Up to `limit` values, newest first. */
		Recent(limit?: number): Array<T>;
		Count(): number;
		/** How many values have been overwritten since the last `Clear`. */
		Dropped(): number;
		Clear(): void;
		/** Keeps the newest values that still fit. */
		Resize(capacity: number): void;
		/** Visits oldest to newest; return `false` to stop early. */
		Each(visit: (value: T, index: number) => boolean | void): void;
	}

	interface RingModule {
		/** Capacity must be at least `1`. */
		new: <T>(capacity: number) => Ring<T>;
	}

	// ────────────────────────────── Guard ──────────────────────────────

	/** A point-in-time view of the running place. */
	interface Snapshot {
		Context: string;
		PlaceId: number;
		PlaceVersion: number;
		JobId: string;
		/** Seconds since Blackbox loaded. */
		Uptime: number;
		Players: number;
		MemoryMb: number | undefined;
		Fps: number | undefined;
	}

	interface DumpOptions {
		/** How many recent entries to include. Defaults to `40`. */
		Entries?: number;
		/** Minimum level for the included entries. */
		Level?: string | number;
		/** Set `false` to leave the metrics section out. */
		Metrics?: boolean;
	}

	/** Crash capture, safe task spawning and the flight-recorder dump. */
	interface GuardModule {
		Snapshot: () => Snapshot;
		/** The full flight-recorder report: place info, top messages, metrics, recent entries. */
		Dump: (options?: DumpOptions) => string;
		/** Hooks `ScriptContext.Error` / `LogService.MessageOut`. Returns `false` if already installed. */
		Install: (logger?: Logger) => boolean;
		/** Disconnects everything `Install` hooked up. */
		Uninstall: () => void;
		/** Server only. Logs and flushes on shutdown. */
		BindToClose: (logger?: Logger) => void;
		/** One-line status summary. */
		Status: () => string;

		/** `task.spawn` that carries the span context over and logs anything raised. */
		Spawn: <A extends Array<unknown>>(fn: (...args: A) => void, ...args: A) => thread;
		/** `task.defer` that carries the span context over and logs anything raised. */
		Defer: <A extends Array<unknown>>(fn: (...args: A) => void, ...args: A) => thread;
		/** `task.delay` that carries the span context over and logs anything raised. */
		Delay: <A extends Array<unknown>>(
			seconds: number,
			fn: (...args: A) => void,
			...args: A
		) => thread;
		/** Connects a handler that logs instead of raising. */
		Connect: (signal: RBXScriptSignal, fn: Callback, name?: string) => RBXScriptConnection;
		/** Wraps a function so raises are logged and swallowed. The wrapper returns nothing. */
		Wrap: <A extends Array<unknown>>(
			fn: (...args: A) => void,
			name?: string,
		) => (...args: A) => void;
	}
}

interface BlackboxModule {
	// ── Sub-modules ──

	/** Level names and numbers (`TRACE` = 10 … `OFF` = 1000). */
	readonly Level: Blackbox.LevelModule;
	/** Sink constructors, plus the raw console and memory sink modules. */
	readonly Sinks: Blackbox.SinksModule;
	/** Counters, gauges, histograms and stopwatches. */
	readonly Metrics: Blackbox.MetricsModule;
	/** Value rendering and redaction. */
	readonly Serialize: Blackbox.SerializeModule;
	/** Stack capture and formatting — this is `Trace.luau`, exposed as `Stack`. */
	readonly Stack: Blackbox.TraceModule;
	/** Per-thread span context. */
	readonly Ambient: Blackbox.AmbientModule;
	/** Crash capture, safe spawning and the flight-recorder dump. */
	readonly Guard: Blackbox.GuardModule;
	/** Ring buffer constructor. */
	readonly Ring: Blackbox.RingModule;
	/** The fault helpers, unwrapped. */
	readonly Faults: Blackbox.FaultsModule;

	// ── Shared objects ──

	/** The in-memory sink every entry is written to, queryable at runtime. */
	readonly History: Blackbox.MemorySink;
	/** The root logger. Its methods take `self`, so they compile to colon calls. */
	readonly Root: Blackbox.Logger;

	// ── Loggers and configuration ──

	/** Gets or creates the logger at a dotted path. No path returns the root logger. */
	Get: (path?: string) => Blackbox.Logger;
	/** Applies configuration. Safe to call more than once. */
	Configure: (options: Blackbox.Config) => void;
	/** Shorthand for `Configure({ Level: level })`. */
	SetLevel: (level: string | number) => void;
	/** The global minimum level currently in force. */
	EffectiveLevel: () => number;
	/**
	 * Configures Blackbox and performs one-time setup: the console sink, the
	 * error guard and the shutdown flush. Called automatically on require, so
	 * later calls only re-apply configuration. Returns the root logger.
	 */
	Start: (options?: Blackbox.StartOptions) => Blackbox.Logger;

	// ── Root-logger shorthands ──

	/** Logs at TRACE through the root logger. */
	Trace: (message: string, fields?: Record<string, unknown>) => void;
	/** Logs at DEBUG through the root logger. */
	Debug: (message: string, fields?: Record<string, unknown>) => void;
	/** Logs at INFO through the root logger. */
	Info: (message: string, fields?: Record<string, unknown>) => void;
	/** Logs at WARN through the root logger. */
	Warn: (message: string, fields?: Record<string, unknown>) => void;
	/** Logs at ERROR through the root logger. */
	Error: (message: string, fields?: Record<string, unknown>) => void;
	/** Logs at FATAL, flushes every sink and runs the `OnFatal` handlers. */
	Fatal: (message: string, fields?: Record<string, unknown>) => void;
	/** Coerces anything raised into a fault, logs it and returns it. */
	Exception: (
		err: unknown,
		message?: string,
		fields?: Record<string, unknown>,
	) => Blackbox.Fault;
	/** Records a breadcrumb; they ride along on the next error-level entry. */
	Breadcrumb: (
		message: string,
		category?: string,
		fields?: Record<string, unknown>,
	) => void;
	/** Opens a timed span on the root logger. Always `Stop` the handle. */
	Span: (name: string, fields?: Record<string, unknown>) => Blackbox.SpanHandle;
	/** Runs `fn` inside a span on the root logger. Logs and rethrows if it raises. */
	Scope: <A extends Array<unknown>, R>(
		name: string,
		fn: (...args: A) => R,
		...args: A
	) => R;
	/** Flushes every sink on the root logger. */
	Flush: () => void;

	// ── Faults ──

	/** Creates a fault without raising it. */
	Fault: (
		kind: string,
		message?: string,
		details?: Record<string, unknown>,
	) => Blackbox.Fault;
	/** Creates a fault and raises it. Never returns. */
	Throw: (kind: string, message?: string, details?: Record<string, unknown>) => never;
	/** Turns anything raised — string, table, fault — into a fault. */
	Coerce: (value: unknown, skip?: number, defaultKind?: string) => Blackbox.Fault;
	IsFault: (value: unknown) => value is Blackbox.Fault;
	/** Runs `fn` under `xpcall` and wraps the outcome in an `Attempt`. */
	Try: <A extends Array<unknown>>(
		fn: (...args: A) => unknown,
		...args: A
	) => Blackbox.Attempt;
	/** Retries `fn` with backoff; `fn` receives the 1-based attempt number first. */
	Retry: <A extends Array<unknown>>(
		options: Blackbox.RetryOptions,
		fn: (attempt: number, ...args: A) => unknown,
		...args: A
	) => Blackbox.Attempt;
	/** Raises a fault of `kind` when `condition` is falsy; otherwise returns it. */
	Assert: <T>(
		condition: T,
		kind: string,
		message?: string,
		details?: Record<string, unknown>,
	) => T;
	/** Raises a fault of `kind` when `value` is nil; otherwise returns it. */
	Expect: <T>(value: T | undefined, kind: string, message?: string) => T;
	/** Wraps a function so every call returns an `Attempt` instead of raising. */
	Protect: <A extends Array<unknown>>(
		fn: (...args: A) => unknown,
	) => (...args: A) => Blackbox.Attempt;

	// ── Guarded scheduling (re-exported from `Guard`) ──

	/** `task.spawn` that carries the span context over and logs anything raised. */
	Spawn: <A extends Array<unknown>>(fn: (...args: A) => void, ...args: A) => thread;
	/** `task.defer` that carries the span context over and logs anything raised. */
	Defer: <A extends Array<unknown>>(fn: (...args: A) => void, ...args: A) => thread;
	/** `task.delay` that carries the span context over and logs anything raised. */
	Delay: <A extends Array<unknown>>(
		seconds: number,
		fn: (...args: A) => void,
		...args: A
	) => thread;
	/** Connects a handler that logs instead of raising. */
	Connect: (signal: RBXScriptSignal, fn: Callback, name?: string) => RBXScriptConnection;
	/** Wraps a function so raises are logged and swallowed. The wrapper returns nothing. */
	Wrap: <A extends Array<unknown>>(
		fn: (...args: A) => void,
		name?: string,
	) => (...args: A) => void;

	// ── Diagnostics ──

	/** Searches the history buffer. Newest first, capped by `Query.Limit` (default 100). */
	Query: (query?: Blackbox.Query) => Array<Blackbox.Entry>;
	/** The most frequent messages, highest count first. `limit` defaults to `10`. */
	Top: (limit?: number) => Array<Blackbox.Frequency>;
	/** The full flight-recorder report: place info, top messages, metrics, recent entries. */
	Dump: (options?: Blackbox.DumpOptions) => string;
	/** One-line status summary. */
	Status: () => string;
	/** A point-in-time view of the running place. */
	Snapshot: () => Blackbox.Snapshot;
	/** Registers a handler for FATAL entries. Returns the function that removes it. */
	OnFatal: (handler: (entry: Blackbox.Entry) => void) => () => void;
	/** Empties the history buffer, the breadcrumbs and the throttler state. */
	Clear: () => void;
}

declare const Blackbox: BlackboxModule;

export = Blackbox;
