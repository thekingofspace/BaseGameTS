/**
 * Type declarations for `InputController.luau` — a binding-based input layer
 * over `UserInputService`.
 *
 * Bindings are written as strings (`"LeftShift+E"`, `"lmb"`, `"wheelup"`) or as
 * `BindingTable`s, and are grouped into named contexts that can be enabled,
 * prioritised, and made exclusive. Actions expose signals plus polling helpers;
 * `Axis`/`Vector`/`Drag`/`Sequence` are higher-level readers built on the same
 * dispatch.
 *
 * Every module-level member is defined with a dot and takes no `self`, so they
 * are all properties and compile to `InputController.Bind(...)`. Everything on
 * the Action/Context/Axis/Vector/Drag/Sequence objects takes `self`, so those
 * stay method syntax and compile to colon calls.
 *
 * Signal payloads are typed here from the module's actual `Fire` calls; the
 * Luau only says `AnySignal`.
 */

import Signal = require("./signal");

declare namespace InputController {
	/** The loose signal type the Luau uses for every event field. */
	type AnySignal = Signal.Signal<Array<unknown>>;
	type Connection = Signal.Connection;

	/** Anything the engine can report as a discrete input. */
	type InputKey = Enum.KeyCode | Enum.UserInputType;

	/**
	 * A resolved key. Strings appear for the pseudo-keys the module synthesises
	 * itself: `"MouseWheelUp"` and `"MouseWheelDown"`.
	 */
	type DispatchKey = InputKey | string;

	type Device = "KeyboardMouse" | "Gamepad" | "Touch";

	/** The long form of a binding, when a plain string is not enough. */
	interface BindingTable {
		/** The trigger key, as an enum or a name/alias (`"e"`, `"lmb"`, `"esc"`). */
		Key?: string | InputKey;
		/** Every key that must be down; the last one is the trigger. */
		Chord?: Array<string | InputKey>;
		/** Modifier keys required alongside `Key`. */
		Modifiers?: Array<string | Enum.KeyCode>;
		/** Require exactly these modifiers — extra ones block the trigger. */
		Exact?: boolean;
		/** Stop lower-priority contexts from seeing this key. */
		Sink?: boolean;
		/** Fire even when the engine already consumed the input (chat, text boxes). */
		AllowGameProcessed?: boolean;
	}

	/**
	 * One binding: a string such as `"Ctrl+Shift+S"` or `"MouseWheelUp"`, a raw
	 * `Enum.KeyCode`/`Enum.UserInputType`, or a `BindingTable`.
	 */
	type BindingSpec = string | InputKey | BindingTable;

	/** One binding, or a list of them. */
	type BindingList = BindingSpec | Array<BindingSpec>;

	interface BindOptions {
		/** Seconds held before `Held` fires. */
		Hold?: number;
		/** Seconds held before `Repeated` starts firing. */
		Repeat?: number;
		/** Seconds between `Repeated` fires once repeating starts. */
		RepeatRate?: number;
		/** Longest press still counted as a tap. Defaults to `0.25`. */
		TapTime?: number;
		/** Longest gap between two taps for `DoubleTapped`. Defaults to `0.3`. */
		DoubleTap?: number;
		/** Require exactly the listed modifiers. */
		Exact?: boolean;
		/** Stop lower-priority contexts from seeing these keys. */
		Sink?: boolean;
		/** Fire even when the engine already consumed the input. */
		AllowGameProcessed?: boolean;
		/** Start the action disabled. */
		Enabled?: boolean;

		/** Shorthand for connecting the matching signal at bind time. */
		OnBegan?: (input: InputObject | undefined) => void;
		OnEnded?: (input: InputObject | undefined) => void;
		OnTapped?: (input: InputObject | undefined) => void;
		OnDoubleTapped?: (input: InputObject | undefined) => void;
		OnHeld?: () => void;
		OnRepeated?: () => void;
		OnChanged?: (value: number) => void;
		/** Runs every frame while the action is down, with the frame delta. */
		WhileDown?: (delta: number) => void;
	}

	interface Action {
		readonly Name: string;
		/** Name of the context that owns this action. */
		readonly Context: string;

		/** Fires when any binding goes down. */
		readonly Began: Signal.Signal<[InputObject | undefined]>;
		/** Fires when the action releases. */
		readonly Ended: Signal.Signal<[InputObject | undefined]>;
		/** Fires on release, when the press was shorter than the tap time. */
		readonly Tapped: Signal.Signal<[InputObject | undefined]>;
		/** Fires on the second tap inside the double-tap window. */
		readonly DoubleTapped: Signal.Signal<[InputObject | undefined]>;
		/** Fires once the hold duration elapses. */
		readonly Held: Signal.Signal<[]>;
		/** Fires repeatedly at the repeat rate while held. */
		readonly Repeated: Signal.Signal<[]>;
		/** Fires with the analog value for wheel/trigger/thumbstick bindings. */
		readonly Changed: Signal.Signal<[number]>;

		IsDown(): boolean;
		/** Latest analog value; `1`/`0` for digital bindings. */
		GetValue(): number;
		/** Seconds the action has been down, or `0` when it is up. */
		GetDownTime(): number;
		/** True if the action went down within the last `window` seconds. */
		JustPressed(window?: number): boolean;
		/** `JustPressed`, but also clears the press so it cannot be consumed twice. */
		Consume(window?: number): boolean;
		/** Runs `handler(delta)` every frame while down. Disconnect to stop. */
		WhileDown(handler: (delta: number) => void): Connection;

		SetEnabled(state: boolean): Action;
		SetHold(seconds?: number): Action;
		SetRepeat(delay?: number, rate?: number): Action;
		SetTapTime(seconds: number): Action;
		SetDoubleTap(seconds: number): Action;

		/** Adds one more binding, keeping the existing ones. */
		Add(spec: BindingSpec, options?: BindOptions): Action;
		/** Replaces every binding with `specs`. */
		Set(specs: BindingList, options?: BindOptions): Action;
		/** Removes every binding; the action object stays alive. */
		Clear(): Action;
		/** Restores the bindings the action was originally created with. */
		Restore(): Action;
		/** Current bindings in the round-trippable `Parse` form. */
		GetBindings(): Array<string>;
		/** Current bindings formatted for display (`"Ctrl + S"`). */
		GetDisplay(separator?: string): string;

		/** Drives the action from code, as if a key went down or up. */
		Push(down: boolean): void;
		/** Unbinds everything and removes the action from its context. */
		Destroy(): void;
	}

	interface ContextOptions {
		/** Higher wins when an exclusive context is active. Defaults to `0`. */
		Priority?: number;
		/** Suppress every context below this one's priority. */
		Exclusive?: boolean;
		/** Defaults to `true`. */
		Enabled?: boolean;
	}

	interface Context {
		readonly Name: string;
		readonly Priority: number;

		/** Creates (or re-binds) a named action inside this context. */
		Bind(name: string, specs?: BindingList, options?: BindOptions): Action;
		/** Fetches an action by name, creating an unbound one if needed. */
		Action(name: string): Action;
		GetActions(): Array<Action>;
		Enable(): Context;
		Disable(): Context;
		SetEnabled(state: boolean): Context;
		IsEnabled(): boolean;
		SetPriority(priority: number): Context;
		SetExclusive(state: boolean): Context;
		/** Destroys every action in the context and unregisters it. */
		Destroy(): void;
	}

	interface AxisSpec {
		/** Bindings that push the axis toward `+1`. */
		Positive?: BindingList;
		/** Bindings that push the axis toward `-1`. */
		Negative?: BindingList;
		/** Gamepad control read for the analog value (a thumbstick or trigger). */
		Gamepad?: Enum.KeyCode;
		/** Which component of the gamepad input to read. */
		Component?: "X" | "Y" | "Z";
		/** Analog values below this magnitude read as zero. Defaults to `0.15`. */
		Deadzone?: number;
		/** Negate the result. */
		Invert?: boolean;
		/** Drive the axis from the mouse wheel. */
		Wheel?: boolean;
	}

	interface Axis {
		readonly Name: string;
		/** Fires with the new value whenever the axis moves. */
		readonly Changed: Signal.Signal<[number]>;
		/** Current value, normally in `[-1, 1]`. */
		Get(): number;
		Destroy(): void;
	}

	interface VectorSpec {
		Up?: BindingList;
		Down?: BindingList;
		Left?: BindingList;
		Right?: BindingList;
		/** Thumbstick read for the analog value. */
		Gamepad?: Enum.KeyCode;
		/** Defaults to `0.15`. */
		Deadzone?: number;
		/** Clamp the result to unit length. */
		Normalize?: boolean;
	}

	interface Vector {
		readonly Name: string;
		readonly Changed: Signal.Signal<[Vector2]>;
		Get(): Vector2;
		Destroy(): void;
	}

	interface DragSpec {
		/** Button that starts the drag. Defaults to `"MouseButton1"`. */
		Button?: BindingSpec;
		/** Pixels of movement before the drag counts as started. Defaults to `6`. */
		Threshold?: number;
		/** Context the internal button binding lives in. Defaults to `"Default"`. */
		Context?: Context;
		AllowGameProcessed?: boolean;
	}

	interface Drag {
		readonly Name: string;
		/** Fires with the origin once the threshold is crossed. */
		readonly Began: Signal.Signal<[Vector2]>;
		/** Fires with `(position, delta, totalFromOrigin)` each move. */
		readonly Changed: Signal.Signal<[Vector2, Vector2, Vector2]>;
		/** Fires with `(position, totalFromOrigin)` on release after a drag. */
		readonly Ended: Signal.Signal<[Vector2, Vector2]>;
		/** Fires with the position on release when the threshold was never crossed. */
		readonly Clicked: Signal.Signal<[Vector2]>;
		IsActive(): boolean;
		GetOrigin(): Vector2;
		GetPosition(): Vector2;
		Destroy(): void;
	}

	interface Sequence {
		readonly Name: string;
		/** Fires when the full key sequence completes inside the window. */
		readonly Triggered: Signal.Signal<[]>;
		/** Drops any partial progress. */
		Reset(): void;
		Destroy(): void;
	}

	interface CaptureOptions {
		/** Include held modifiers in the captured binding. Defaults to `true`. */
		Modifiers?: boolean;
		/** Binding that cancels the capture. Defaults to `Escape`. */
		Cancel?: BindingSpec;
		/** Accept keyboard keys. Defaults to `true`. */
		Keyboard?: boolean;
		/** Accept mouse buttons. Defaults to `true`. */
		Mouse?: boolean;
		/** Accept gamepad buttons. Defaults to `true`. */
		Gamepad?: boolean;
	}

	/**
	 * `UserInputService`'s touch events, wrapped as signals. Each one is created
	 * lazily on first access; any other key reads as `undefined`.
	 */
	interface TouchSignals {
		readonly Tap: Signal.Signal<[Array<Vector2>, boolean]>;
		readonly LongPress: Signal.Signal<[Array<Vector2>, Enum.UserInputState, boolean]>;
		readonly Pan: Signal.Signal<
			[Array<Vector2>, Vector2, Vector2, Enum.UserInputState, boolean]
		>;
		readonly Pinch: Signal.Signal<[Array<Vector2>, number, number, Enum.UserInputState, boolean]>;
		readonly Rotate: Signal.Signal<
			[Array<Vector2>, number, number, Enum.UserInputState, boolean]
		>;
		readonly Swipe: Signal.Signal<[Enum.SwipeDirection, number, boolean]>;
		readonly Started: Signal.Signal<[InputObject, boolean]>;
		readonly Moved: Signal.Signal<[InputObject, boolean]>;
		readonly Ended: Signal.Signal<[InputObject, boolean]>;
	}

	/** `{ [contextName]: { [actionName]: bindings } }`. */
	type SerializedBindings = Record<string, Record<string, Array<string>>>;
}

interface InputControllerModule {
	// -------------------------------------------------------- Global signals

	/** Fires with the new device whenever the active input device changes. */
	readonly DeviceChanged: Signal.Signal<[InputController.Device]>;
	/** Fires with `(position, delta)` on mouse movement; delta is sensitivity-scaled. */
	readonly MouseMoved: Signal.Signal<[Vector2, Vector2]>;
	/** Fires with the wheel amount (`+1`/`-1`). */
	readonly WheelMoved: Signal.Signal<[number]>;
	/** Lazily wrapped `UserInputService` touch events. */
	readonly Touch: InputController.TouchSignals;

	// -------------------------------------------------------- Contexts and actions

	/**
	 * Fetches a context by name, creating it if needed. Passing `options` for an
	 * existing context applies them to it.
	 */
	Context: (name: string, options?: InputController.ContextOptions) => InputController.Context;
	/** `Context("Default"):Bind(...)`. */
	Bind: (
		name: string,
		specs?: InputController.BindingList,
		options?: InputController.BindOptions,
	) => InputController.Action;
	/** `Context("Default"):Action(...)`. */
	Action: (name: string) => InputController.Action;
	/**
	 * Looks up an existing action by name — inside `context` when given,
	 * otherwise across every context. Does not create one.
	 */
	Find: (name: string, context?: string) => InputController.Action | undefined;

	// -------------------------------------------------------- Composite readers

	/** A `-1..1` axis from opposing bindings and/or a gamepad control. */
	Axis: (name: string, spec: InputController.AxisSpec) => InputController.Axis;
	/** A 2D vector from four directional bindings and/or a thumbstick. */
	Vector: (name: string, spec: InputController.VectorSpec) => InputController.Vector;
	/** A click-and-drag reader built on a hidden button binding. */
	Drag: (name: string, spec?: InputController.DragSpec) => InputController.Drag;
	/**
	 * Fires once the listed bindings are pressed in order, each within `window`
	 * seconds of the last. `window` defaults to `0.6`.
	 */
	Sequence: (
		name: string,
		specs: Array<InputController.BindingSpec>,
		window?: number,
	) => InputController.Sequence;

	// -------------------------------------------------------- Rebinding

	/**
	 * Listens for the next input and hands it back in `Parse` form, or
	 * `undefined` if the capture was cancelled. Returns a function that cancels
	 * the capture. Only one capture runs at a time.
	 */
	Capture: (
		callback: (binding: string | undefined) => void,
		options?: InputController.CaptureOptions,
	) => () => void;
	/**
	 * `Capture`, wired to overwrite binding slot `index` (default `1`) of
	 * `action`. Returns the cancel function.
	 */
	Rebind: (
		action: InputController.Action,
		index?: number,
		options?: InputController.CaptureOptions,
	) => () => void;

	/** Normalises a spec into the canonical `"Ctrl+S"` string. */
	Parse: (spec: InputController.BindingSpec) => string;
	/** Formats a spec for display (`"Ctrl + S"`), using friendly key names. */
	Display: (spec: InputController.BindingSpec, separator?: string) => string;

	// -------------------------------------------------------- Polling

	/** Whether the named action is currently down. */
	IsDown: (name: string) => boolean;
	/** Whether a raw key is down, by enum or name/alias. */
	IsKeyDown: (key: string | InputController.InputKey) => boolean;
	/** Latest analog position for a key; `Vector3.zero` when there is none. */
	GetAnalog: (key: string | InputController.InputKey) => Vector3;
	/** Bitmask of held modifiers: Ctrl `1`, Shift `2`, Alt `4`, Meta `8`. */
	GetModifiers: () => number;
	/** Whether a modifier is held, by name (`"ctrl"`, `"shift"`, ...). */
	IsModifierDown: (name: string) => boolean;

	// -------------------------------------------------------- Device

	/** The device the last input came from. */
	GetDevice: () => InputController.Device;
	HasGamepad: () => boolean;
	HasTouch: () => boolean;
	HasKeyboard: () => boolean;
	HasMouse: () => boolean;
	/** True while the player is typing into a text box. */
	IsTyping: () => boolean;

	// -------------------------------------------------------- Mouse

	GetMousePosition: () => Vector2;
	/** Frame mouse delta, scaled by the module's sensitivity. */
	GetMouseDelta: () => Vector2;
	/** Multiplier applied to `GetMouseDelta`. Defaults to `1`. */
	SetSensitivity: (value: number) => void;
	GetSensitivity: () => number;
	SetMouseBehavior: (behavior: Enum.MouseBehavior) => void;
	/** Locks to centre; pass `false` to lock at the current position instead. */
	LockMouse: (center?: boolean) => void;
	UnlockMouse: () => void;
	SetMouseIconEnabled: (state: boolean) => void;
	/** Ray through the cursor, `depth` studs long (default `1000`). */
	GetMouseRay: (depth?: number) => Ray;
	/** Raycasts along `GetMouseRay`. */
	MouseRaycast: (params?: RaycastParams, depth?: number) => RaycastResult | undefined;

	// -------------------------------------------------------- Lifecycle

	/** Disabling releases everything currently held. */
	SetEnabled: (state: boolean) => void;
	IsEnabled: () => boolean;
	/** Ends every held action as if the keys were released. */
	ReleaseAll: () => void;

	/** Snapshots every context's bindings. Internal drag bindings are skipped. */
	Serialize: () => InputController.SerializedBindings;
	/** Applies a `Serialize` snapshot. Unknown contexts and actions are ignored. */
	Deserialize: (data: InputController.SerializedBindings) => void;
	/** Restores original bindings — for one context, or all of them. */
	ResetBindings: (context?: string) => void;
	/** Tears down every context, sequence, drag and engine listener. */
	Destroy: () => void;
}

declare const InputController: InputControllerModule;

export = InputController;
