--!strict
--!optimize 2

const UserInputService = game:GetService("UserInputService")
const RunService = game:GetService("RunService")
const Workspace = game:GetService("Workspace")

const Signal = require(script.Parent.signal)
const Scythe = require(script.Parent.Scythe)

export type AnySignal = Signal.Signal<...any>
export type Connection = Signal.Connection
export type InputKey = Enum.KeyCode | Enum.UserInputType
export type DispatchKey = InputKey | string
export type Device = "KeyboardMouse" | "Gamepad" | "Touch"

export type BindingTable = {
	Key: (string | InputKey)?,
	Chord: { string | InputKey }?,
	Modifiers: { string | Enum.KeyCode }?,
	Exact: boolean?,
	Sink: boolean?,
	AllowGameProcessed: boolean?,
}

export type BindingSpec = string | InputKey | BindingTable

export type BindingList = BindingSpec | { BindingSpec } | { string } | { InputKey }

export type BindOptions = {
	Hold: number?,
	Repeat: number?,
	RepeatRate: number?,
	TapTime: number?,
	DoubleTap: number?,
	Exact: boolean?,
	Sink: boolean?,
	AllowGameProcessed: boolean?,
	Enabled: boolean?,
	OnBegan: ((input: InputObject?) -> ())?,
	OnEnded: ((input: InputObject?) -> ())?,
	OnTapped: ((input: InputObject?) -> ())?,
	OnDoubleTapped: ((input: InputObject?) -> ())?,
	OnHeld: (() -> ())?,
	OnRepeated: (() -> ())?,
	OnChanged: ((value: number) -> ())?,
	WhileDown: ((delta: number) -> ())?,
}

export type Action = {
	Name: string,
	Context: string,
	Began: AnySignal,
	Ended: AnySignal,
	Tapped: AnySignal,
	DoubleTapped: AnySignal,
	Held: AnySignal,
	Repeated: AnySignal,
	Changed: AnySignal,

	IsDown: (self: Action) -> boolean,
	GetValue: (self: Action) -> number,
	GetDownTime: (self: Action) -> number,
	JustPressed: (self: Action, window: number?) -> boolean,
	Consume: (self: Action, window: number?) -> boolean,
	WhileDown: (self: Action, handler: (delta: number) -> ()) -> Connection,

	SetEnabled: (self: Action, state: boolean) -> Action,
	SetHold: (self: Action, seconds: number?) -> Action,
	SetRepeat: (self: Action, delay: number?, rate: number?) -> Action,
	SetTapTime: (self: Action, seconds: number) -> Action,
	SetDoubleTap: (self: Action, seconds: number) -> Action,

	Add: (self: Action, spec: BindingSpec, options: BindOptions?) -> Action,
	Set: (self: Action, specs: BindingList, options: BindOptions?) -> Action,
	Clear: (self: Action) -> Action,
	Restore: (self: Action) -> Action,
	GetBindings: (self: Action) -> { string },
	GetDisplay: (self: Action, separator: string?) -> string,

	Push: (self: Action, down: boolean) -> (),
	Destroy: (self: Action) -> (),
}

export type ContextOptions = {
	Priority: number?,
	Exclusive: boolean?,
	Enabled: boolean?,
}

export type Context = {
	Name: string,
	Priority: number,
	Bind: (self: Context, name: string, specs: BindingList?, options: BindOptions?) -> Action,
	Action: (self: Context, name: string) -> Action,
	GetActions: (self: Context) -> { Action },
	Enable: (self: Context) -> Context,
	Disable: (self: Context) -> Context,
	SetEnabled: (self: Context, state: boolean) -> Context,
	IsEnabled: (self: Context) -> boolean,
	SetPriority: (self: Context, priority: number) -> Context,
	SetExclusive: (self: Context, state: boolean) -> Context,
	Destroy: (self: Context) -> (),
}

export type AxisSpec = {
	Positive: BindingList?,
	Negative: BindingList?,
	Gamepad: Enum.KeyCode?,
	Component: ("X" | "Y" | "Z")?,
	Deadzone: number?,
	Invert: boolean?,
	Wheel: boolean?,
}

export type Axis = {
	Name: string,
	Changed: AnySignal,
	Get: (self: Axis) -> number,
	Destroy: (self: Axis) -> (),
}

export type VectorSpec = {
	Up: BindingList?,
	Down: BindingList?,
	Left: BindingList?,
	Right: BindingList?,
	Gamepad: Enum.KeyCode?,
	Deadzone: number?,
	Normalize: boolean?,
}

export type Vector = {
	Name: string,
	Changed: AnySignal,
	Get: (self: Vector) -> Vector2,
	Destroy: (self: Vector) -> (),
}

export type DragSpec = {
	Button: BindingSpec?,
	Threshold: number?,
	Context: Context?,
	AllowGameProcessed: boolean?,
}

export type Drag = {
	Name: string,
	Began: AnySignal,
	Changed: AnySignal,
	Ended: AnySignal,
	Clicked: AnySignal,
	IsActive: (self: Drag) -> boolean,
	GetOrigin: (self: Drag) -> Vector2,
	GetPosition: (self: Drag) -> Vector2,
	Destroy: (self: Drag) -> (),
}

export type Sequence = {
	Name: string,
	Triggered: AnySignal,
	Reset: (self: Sequence) -> (),
	Destroy: (self: Sequence) -> (),
}

export type CaptureOptions = {
	Modifiers: boolean?,
	Cancel: BindingSpec?,
	Keyboard: boolean?,
	Mouse: boolean?,
	Gamepad: boolean?,
}

const MOD_CTRL = 1
const MOD_SHIFT = 2
const MOD_ALT = 4
const MOD_META = 8

const WHEEL_UP = "MouseWheelUp"
const WHEEL_DOWN = "MouseWheelDown"

const DEFAULT_TAP_TIME = 0.25
const DEFAULT_DOUBLE_TAP = 0.3
const DEFAULT_DEADZONE = 0.15
const DEFAULT_DRAG_THRESHOLD = 6
const DEFAULT_REPEAT_RATE = 0.05
const DEFAULT_SEQUENCE_WINDOW = 0.6

const KEYCODES: { [string]: Enum.KeyCode } = {}
for _, item in Enum.KeyCode:GetEnumItems() do
	KEYCODES[string.lower(item.Name)] = item
end

const INPUTTYPES: { [string]: Enum.UserInputType } = {}
for _, item in Enum.UserInputType:GetEnumItems() do
	INPUTTYPES[string.lower(item.Name)] = item
end

const ALIASES: { [string]: string } = {
	ctrl = "leftcontrol",
	control = "leftcontrol",
	lctrl = "leftcontrol",
	rctrl = "rightcontrol",
	shift = "leftshift",
	lshift = "leftshift",
	rshift = "rightshift",
	alt = "leftalt",
	lalt = "leftalt",
	ralt = "rightalt",
	option = "leftalt",
	cmd = "leftmeta",
	command = "leftmeta",
	meta = "leftmeta",
	super = "leftmeta",
	win = "leftmeta",
	mouse1 = "mousebutton1",
	mouse2 = "mousebutton2",
	mouse3 = "mousebutton3",
	lmb = "mousebutton1",
	rmb = "mousebutton2",
	mmb = "mousebutton3",
	leftclick = "mousebutton1",
	rightclick = "mousebutton2",
	middleclick = "mousebutton3",
	wheel = "mousewheel",
	scroll = "mousewheel",
	wheelup = "mousewheelup",
	wheeldown = "mousewheeldown",
	scrollup = "mousewheelup",
	scrolldown = "mousewheeldown",
	mousemove = "mousemovement",
	esc = "escape",
	enter = "return",
	del = "delete",
	ins = "insert",
	pgup = "pageup",
	pgdn = "pagedown",
	spacebar = "space",
	plus = "equals",
	up = "up",
	down = "down",
	left = "left",
	right = "right",
	lstick = "thumbstick1",
	rstick = "thumbstick2",
	lt = "buttonl2",
	rt = "buttonr2",
	lb = "buttonl1",
	rb = "buttonr1",
	["0"] = "zero",
	["1"] = "one",
	["2"] = "two",
	["3"] = "three",
	["4"] = "four",
	["5"] = "five",
	["6"] = "six",
	["7"] = "seven",
	["8"] = "eight",
	["9"] = "nine",
	keypad0 = "keypadzero",
	keypad1 = "keypadone",
	keypad2 = "keypadtwo",
	keypad3 = "keypadthree",
	keypad4 = "keypadfour",
	keypad5 = "keypadfive",
	keypad6 = "keypadsix",
	keypad7 = "keypadseven",
	keypad8 = "keypadeight",
	keypad9 = "keypadnine",
	kp0 = "keypadzero",
	kp1 = "keypadone",
	kp2 = "keypadtwo",
	kp3 = "keypadthree",
	kp4 = "keypadfour",
	kp5 = "keypadfive",
	kp6 = "keypadsix",
	kp7 = "keypadseven",
	kp8 = "keypadeight",
	kp9 = "keypadnine",
}

const PSEUDO: { [string]: string } = {
	mousewheelup = WHEEL_UP,
	mousewheeldown = WHEEL_DOWN,
}

const MOD_BIT: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.LeftControl] = MOD_CTRL,
	[Enum.KeyCode.RightControl] = MOD_CTRL,
	[Enum.KeyCode.LeftShift] = MOD_SHIFT,
	[Enum.KeyCode.RightShift] = MOD_SHIFT,
	[Enum.KeyCode.LeftAlt] = MOD_ALT,
	[Enum.KeyCode.RightAlt] = MOD_ALT,
	[Enum.KeyCode.LeftMeta] = MOD_META,
	[Enum.KeyCode.RightMeta] = MOD_META,
}

const MOD_NAMES: { { bit: number, text: string } } = {
	{ bit = MOD_CTRL, text = "Ctrl" },
	{ bit = MOD_SHIFT, text = "Shift" },
	{ bit = MOD_ALT, text = "Alt" },
	{ bit = MOD_META, text = "Meta" },
}

const DISPLAY_NAMES: { [any]: string } = {
	[Enum.UserInputType.MouseButton1] = "LMB",
	[Enum.UserInputType.MouseButton2] = "RMB",
	[Enum.UserInputType.MouseButton3] = "MMB",
	[Enum.UserInputType.MouseWheel] = "Wheel",
	[Enum.UserInputType.MouseMovement] = "Mouse",
	[Enum.UserInputType.Touch] = "Touch",
	[Enum.KeyCode.LeftControl] = "Ctrl",
	[Enum.KeyCode.RightControl] = "RCtrl",
	[Enum.KeyCode.LeftShift] = "Shift",
	[Enum.KeyCode.RightShift] = "RShift",
	[Enum.KeyCode.LeftAlt] = "Alt",
	[Enum.KeyCode.RightAlt] = "RAlt",
	[Enum.KeyCode.Return] = "Enter",
	[Enum.KeyCode.Escape] = "Esc",
	[Enum.KeyCode.Space] = "Space",
	[Enum.KeyCode.Thumbstick1] = "L-Stick",
	[Enum.KeyCode.Thumbstick2] = "R-Stick",
	[WHEEL_UP] = "Wheel Up",
	[WHEEL_DOWN] = "Wheel Down",
	[Enum.KeyCode.Zero] = "0",
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6",
	[Enum.KeyCode.Seven] = "7",
	[Enum.KeyCode.Eight] = "8",
	[Enum.KeyCode.Nine] = "9",
	[Enum.KeyCode.KeypadZero] = "Num 0",
	[Enum.KeyCode.KeypadOne] = "Num 1",
	[Enum.KeyCode.KeypadTwo] = "Num 2",
	[Enum.KeyCode.KeypadThree] = "Num 3",
	[Enum.KeyCode.KeypadFour] = "Num 4",
	[Enum.KeyCode.KeypadFive] = "Num 5",
	[Enum.KeyCode.KeypadSix] = "Num 6",
	[Enum.KeyCode.KeypadSeven] = "Num 7",
	[Enum.KeyCode.KeypadEight] = "Num 8",
	[Enum.KeyCode.KeypadNine] = "Num 9",
}

const SIGNAL_FIELDS: { [string]: boolean } = {
	Began = true,
	Ended = true,
	Tapped = true,
	DoubleTapped = true,
	Held = true,
	Repeated = true,
	Changed = true,
}

const GAMEPAD_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
	[Enum.UserInputType.Gamepad5] = true,
	[Enum.UserInputType.Gamepad6] = true,
	[Enum.UserInputType.Gamepad7] = true,
	[Enum.UserInputType.Gamepad8] = true,
}

const IS_CLIENT = RunService:IsClient()
const STEP_SIGNAL: RBXScriptSignal = if IS_CLIENT then RunService.RenderStepped else RunService.Heartbeat

const pressed: { [DispatchKey]: boolean } = {}
const analog: { [DispatchKey]: Vector3 } = {}
const bindingsByKey: { [DispatchKey]: { any } } = {}
const dirtyKeys: { [DispatchKey]: boolean } = {}
const watchers: { [DispatchKey]: { any } } = {}
const contexts: { [string]: any } = {}
const contextList: { any } = {}
const allActions: { any } = {}
const sequences: { any } = {}
const drags: { any } = {}
const activeList: { any } = {}

local modMask = 0
local orderSeed = 0
local exclusiveFloor = -math.huge
local activeCount = 0
local stepConnection: RBXScriptConnection? = nil
local enabled = true
local typing = false
local device: Device = "KeyboardMouse"
local sensitivity = 1
local capturing: any = nil
local listenerScope: Scythe.Scope? = nil

const InputController = {}

InputController.DeviceChanged = Signal.new()
InputController.MouseMoved = Signal.new()
InputController.WheelMoved = Signal.new()

const function resolveToken(token: string): DispatchKey?
	const trimmed = string.gsub(string.lower(token), "%s", "")
	const name = ALIASES[trimmed] or trimmed
	const pseudo = PSEUDO[name]
	if pseudo ~= nil then
		return pseudo
	end
	const code = KEYCODES[name]
	if code ~= nil then
		return code
	end
	return INPUTTYPES[name]
end

const function keyName(key: DispatchKey): string
	if type(key) == "string" then
		return key
	end
	return (key :: EnumItem).Name
end

const function keyDisplay(key: DispatchKey): string
	return DISPLAY_NAMES[key] or keyName(key)
end

const function modBitOf(key: DispatchKey): number
	if type(key) == "string" then
		return 0
	end
	return MOD_BIT[key :: Enum.KeyCode] or 0
end

const function parseString(text: string): (number, { DispatchKey })
	const tokens = string.split(text, "+")
	const keys: { DispatchKey } = {}
	local mods = 0
	const count = #tokens

	for index = 1, count do
		const token = tokens[index]
		if token == "" then
			continue
		end
		const key = resolveToken(token)
		if key == nil then
			error(`InputController: unknown input token '{token}' in '{text}'`, 4)
		end
		const bit = modBitOf(key)
		if bit ~= 0 and index < count then
			mods = bit32.bor(mods, bit)
		else
			table.insert(keys, key)
		end
	end

	if #keys == 0 then
		error(`InputController: binding '{text}' resolves to no primary key`, 4)
	end

	return mods, keys
end

const function coerceKey(value: string | InputKey): DispatchKey
	if type(value) == "string" then
		const key = resolveToken(value)
		if key == nil then
			error(`InputController: unknown input token '{value}'`, 4)
		end
		return key
	end
	return value
end

const function parseSpec(spec: BindingSpec): (number, { DispatchKey }, BindingTable?)
	const kind = typeof(spec)

	if kind == "string" then
		local mods, keys = parseString(spec :: string)
		return mods, keys, nil
	end

	if kind == "EnumItem" then
		return 0, { spec :: InputKey }, nil
	end

	if kind ~= "table" then
		error(`InputController: cannot parse a binding of type '{kind}'`, 4)
	end

	const declaration = spec :: BindingTable
	local mods = 0
	const keys: { DispatchKey } = {}

	if declaration.Modifiers ~= nil then
		for _, entry in declaration.Modifiers do
			const bit = modBitOf(coerceKey(entry))
			if bit == 0 then
				error("InputController: Modifiers only accepts Ctrl, Shift, Alt or Meta keys", 4)
			end
			mods = bit32.bor(mods, bit)
		end
	end

	if declaration.Key ~= nil then
		table.insert(keys, coerceKey(declaration.Key))
	end

	if declaration.Chord ~= nil then
		for _, entry in declaration.Chord do
			table.insert(keys, coerceKey(entry))
		end
	end

	if #keys == 0 then
		error("InputController: binding table needs a Key or a Chord", 4)
	end

	return mods, keys, declaration
end

const function bindingText(mods: number, keys: { DispatchKey }, separator: string, pretty: boolean): string
	const parts: { string } = {}

	for _, entry in MOD_NAMES do
		if bit32.btest(mods, entry.bit) then
			table.insert(parts, entry.text)
		end
	end

	for _, key in keys do
		table.insert(parts, if pretty then keyDisplay(key) else keyName(key))
	end

	return table.concat(parts, separator)
end

const function markDirty(key: DispatchKey)
	dirtyKeys[key] = true
end

const function compareBindings(a: any, b: any): boolean
	const left = a.context.priority
	const right = b.context.priority
	if left == right then
		return a.order < b.order
	end
	return left > right
end

const function refreshExclusiveFloor()
	local floor = -math.huge
	for _, context in contextList do
		if context.enabled and context.exclusive and context.priority > floor then
			floor = context.priority
		end
	end
	exclusiveFloor = floor
end

local step: (delta: number) -> ()

const function markActive(record: any)
	if record.activeIndex ~= 0 then
		return
	end
	activeCount += 1
	activeList[activeCount] = record
	record.activeIndex = activeCount
	if stepConnection == nil then
		stepConnection = STEP_SIGNAL:Connect(step)
	end
end

const function unmarkActive(record: any)
	const index = record.activeIndex
	if index == 0 then
		return
	end
	const last = activeList[activeCount]
	activeList[index] = last
	last.activeIndex = index
	activeList[activeCount] = nil
	activeCount -= 1
	record.activeIndex = 0
	if activeCount == 0 and stepConnection ~= nil then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

const function wantsFrame(record: any): boolean
	if not record.down then
		return false
	end
	if record.holdPending then
		return true
	end
	if record.repeatRate > 0 then
		return true
	end
	const while_ = record.whileSignal
	return while_ ~= false and (while_ :: AnySignal):HasConnections()
end

function step(delta: number)
	const now = os.clock()

	for index = activeCount, 1, -1 do
		const record = activeList[index]

		if record.down then
			if record.holdPending and now >= record.holdAt then
				record.holdPending = false
				record.holdFired = true
				const held = rawget(record, "Held") :: AnySignal?
				if held ~= nil then
					held:Fire()
				end
			end

			if record.repeatRate > 0 and now >= record.nextRepeat then
				record.nextRepeat = now + record.repeatRate
				const repeated = rawget(record, "Repeated") :: AnySignal?
				if repeated ~= nil then
					repeated:Fire()
				end
			end

			const while_ = record.whileSignal
			if while_ ~= false and (while_ :: AnySignal):HasConnections() then
				(while_ :: AnySignal):Fire(delta)
			end
		end

		if not wantsFrame(record) then
			unmarkActive(record)
		end
	end
end

const function fireChanged(record: any, value: number)
	if record.value == value then
		return
	end
	record.value = value
	const changed = rawget(record, "Changed") :: AnySignal?
	if changed ~= nil then
		changed:Fire(value)
	end
end

const function beginAction(record: any, input: InputObject?)
	record.holds += 1
	if record.holds > 1 then
		return
	end

	const now = os.clock()
	record.down = true
	record.pressedAt = now
	record.holdFired = false
	fireChanged(record, 1)

	const began = rawget(record, "Began") :: AnySignal?
	if began ~= nil then
		began:Fire(input)
	end

	if now - record.lastPress <= record.doubleWindow then
		record.lastPress = -math.huge
		const double = rawget(record, "DoubleTapped") :: AnySignal?
		if double ~= nil then
			double:Fire(input)
		end
	else
		record.lastPress = now
	end

	if record.holdTime > 0 then
		record.holdPending = true
		record.holdAt = now + record.holdTime
	end

	if record.repeatRate > 0 then
		record.nextRepeat = now + record.repeatDelay
	end

	if wantsFrame(record) then
		markActive(record)
	end
end

const function endAction(record: any, input: InputObject?)
	record.holds -= 1
	if record.holds > 0 then
		return
	end

	record.holds = 0
	const now = os.clock()
	record.down = false
	record.releasedAt = now
	record.holdPending = false
	fireChanged(record, 0)

	const ended = rawget(record, "Ended") :: AnySignal?
	if ended ~= nil then
		ended:Fire(input)
	end

	if not record.holdFired and now - record.pressedAt <= record.tapTime then
		const tapped = rawget(record, "Tapped") :: AnySignal?
		if tapped ~= nil then
			tapped:Fire(input)
		end
	end

	unmarkActive(record)
end

const function chordSatisfied(binding: any, trigger: DispatchKey): boolean
	const keys = binding.keys
	for index = 1, #keys do
		const key = keys[index]
		if key ~= trigger and not pressed[key] then
			return false
		end
	end
	return true
end

const function notifyWatchers(key: DispatchKey)
	const list = watchers[key]
	if list == nil then
		return
	end
	for index = 1, #list do
		const node = list[index]
		node.refresh(node)
	end
end

const function feedSequences(key: DispatchKey)
	const now = os.clock()

	for index = 1, #sequences do
		const node = sequences[index]

		if node.index > 0 and now - node.lastAt > node.window then
			node.index = 0
		end

		if key == node.keys[node.index + 1] then
			node.index += 1
			node.lastAt = now
			if node.index == node.length then
				node.index = 0
				node.Triggered:Fire()
			end
		elseif key == node.keys[1] then
			node.index = 1
			node.lastAt = now
		else
			node.index = 0
		end
	end
end

const function dispatch(key: DispatchKey, input: InputObject?, gameProcessed: boolean, began: boolean)
	const list = bindingsByKey[key]
	if list == nil then
		return
	end

	if dirtyKeys[key] then
		dirtyKeys[key] = nil
		table.sort(list, compareBindings)
	end

	const floor = exclusiveFloor
	const blocked = gameProcessed or typing

	for index = 1, #list do
		const binding = list[index]
		const context = binding.context

		if not context.enabled or context.priority < floor then
			continue
		end

		const action = binding.action
		if not action.enabled then
			continue
		end

		if began then
			if blocked and not binding.processed then
				continue
			end
			if binding.down then
				continue
			end

			const masked = bit32.band(modMask, binding.filter)
			if binding.exact then
				if masked ~= binding.mods then
					continue
				end
			elseif bit32.band(masked, binding.mods) ~= binding.mods then
				continue
			end

			if binding.chord and not chordSatisfied(binding, key) then
				continue
			end

			binding.down = true
			beginAction(action, input)

			if binding.sink or context.exclusive then
				break
			end
		elseif binding.down then
			binding.down = false
			endAction(action, input)
		end
	end
end

const function releaseKey(key: DispatchKey, input: InputObject?)
	if not pressed[key] then
		return
	end
	pressed[key] = nil
	const bit = modBitOf(key)
	if bit ~= 0 then
		modMask = bit32.band(modMask, bit32.bnot(bit))
	end
	dispatch(key, input, false, false)
	notifyWatchers(key)
end

const function releaseAll()
	const keys: { DispatchKey } = {}
	for key in pressed do
		table.insert(keys, key)
	end
	for _, key in keys do
		releaseKey(key, nil)
	end

	for _, action in allActions do
		if action.holds > 0 then
			action.holds = 1
			endAction(action, nil)
		end
	end

	modMask = 0
	table.clear(analog)
end

const function dispatchKeyOf(input: InputObject): DispatchKey
	const code = input.KeyCode
	if code.Value ~= 0 then
		return code
	end
	return input.UserInputType
end

const function updateDevice(inputType: Enum.UserInputType)
	local next_: Device
	if GAMEPAD_TYPES[inputType] then
		next_ = "Gamepad"
	elseif inputType == Enum.UserInputType.Touch then
		next_ = "Touch"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseWheel
	then
		next_ = "KeyboardMouse"
	else
		return
	end

	if next_ ~= device then
		device = next_
		InputController.DeviceChanged:Fire(next_)
	end
end

const function captureFrom(input: InputObject): boolean
	const session = capturing
	if session == nil then
		return false
	end

	const key = dispatchKeyOf(input)
	if modBitOf(key) ~= 0 and session.modifiers then
		return true
	end

	const inputType = input.UserInputType
	if inputType == Enum.UserInputType.Keyboard and not session.keyboard then
		return false
	end
	if not session.mouse and (inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.MouseButton2 or inputType == Enum.UserInputType.MouseButton3) then
		return false
	end
	if GAMEPAD_TYPES[inputType] and not session.gamepad then
		return false
	end

	capturing = nil

	if session.cancel ~= nil and key == session.cancel then
		session.callback(nil)
		return true
	end

	const mods = if session.modifiers then modMask else 0
	session.callback(bindingText(mods, { key }, "+", false))
	return true
end

const function onInputBegan(input: InputObject, gameProcessed: boolean)
	if not enabled then
		return
	end

	const key = dispatchKeyOf(input)
	pressed[key] = true

	const bit = modBitOf(key)
	if bit ~= 0 then
		modMask = bit32.bor(modMask, bit)
	end

	updateDevice(input.UserInputType)

	if captureFrom(input) then
		return
	end

	if not gameProcessed and not typing then
		feedSequences(key)
	end

	dispatch(key, input, gameProcessed, true)
	notifyWatchers(key)
end

const function onInputEnded(input: InputObject, _gameProcessed: boolean)
	const key = dispatchKeyOf(input)
	pressed[key] = nil

	const bit = modBitOf(key)
	if bit ~= 0 then
		modMask = bit32.band(modMask, bit32.bnot(bit))
	end

	dispatch(key, input, false, false)
	notifyWatchers(key)
end

const function updateDrags(position: Vector2, delta: Vector2)
	for index = 1, #drags do
		const node = drags[index]
		if not node.holding then
			continue
		end

		node.position = position

		if node.active then
			node.Changed:Fire(position, delta, position - node.origin)
		elseif (position - node.origin).Magnitude >= node.threshold then
			node.active = true
			node.Began:Fire(node.origin)
			node.Changed:Fire(position, delta, position - node.origin)
		end
	end
end

const function onInputChanged(input: InputObject, gameProcessed: boolean)
	if not enabled then
		return
	end

	const inputType = input.UserInputType

	if inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.Touch then
		const raw = input.Delta
		const position = Vector2.new(input.Position.X, input.Position.Y)
		const delta = Vector2.new(raw.X * sensitivity, raw.Y * sensitivity)
		analog[Enum.UserInputType.MouseMovement] = raw
		if #drags > 0 then
			updateDrags(position, delta)
		end
		InputController.MouseMoved:Fire(position, delta)
		return
	end

	if inputType == Enum.UserInputType.MouseWheel then
		const amount = input.Position.Z
		InputController.WheelMoved:Fire(amount)
		if gameProcessed or typing then
			return
		end
		const key = if amount > 0 then WHEEL_UP else WHEEL_DOWN
		dispatch(key, input, gameProcessed, true)
		dispatch(key, input, gameProcessed, false)
		dispatch(Enum.UserInputType.MouseWheel, input, gameProcessed, true)
		dispatch(Enum.UserInputType.MouseWheel, input, gameProcessed, false)
		return
	end

	const key = dispatchKeyOf(input)
	analog[key] = input.Position

	const list = bindingsByKey[key]
	if list ~= nil then
		const value = if input.Position.Z ~= 0 then input.Position.Z else input.Position.Magnitude
		for index = 1, #list do
			const binding = list[index]
			if binding.context.enabled and binding.action.enabled then
				fireChanged(binding.action, value)
			end
		end
	end

	notifyWatchers(key)
	updateDevice(inputType)
end

const function ensureListeners()
	if listenerScope ~= nil or not IS_CLIENT then
		return
	end

	const scope = Scythe.scope()
	listenerScope = scope

	Scythe.addBulk(
		scope,
		UserInputService.InputBegan:Connect(onInputBegan),
		UserInputService.InputEnded:Connect(onInputEnded),
		UserInputService.InputChanged:Connect(onInputChanged),
		UserInputService.WindowFocusReleased:Connect(releaseAll),
		UserInputService.TextBoxFocused:Connect(function()
			typing = true
		end),
		UserInputService.TextBoxFocusReleased:Connect(function()
			typing = false
		end),
		UserInputService.LastInputTypeChanged:Connect(updateDevice)
	)
end

const ActionMethods = {}

const ActionMeta = {
	__index = function(self: any, key: any): any
		if SIGNAL_FIELDS[key] then
			const created = Signal.new()
			rawset(self, key, created)
			return created
		end
		return ActionMethods[key]
	end,
	__tostring = function(self: any): string
		return `Action<{self.Context}/{self.Name}>`
	end,
}

const function removeBinding(binding: any)
	const action = binding.action

	if binding.down then
		binding.down = false
		endAction(action, nil)
	end

	for _, key in binding.keys do
		const list = bindingsByKey[key]
		if list == nil then
			continue
		end
		const index = table.find(list, binding)
		if index ~= nil then
			table.remove(list, index)
			if #list == 0 then
				bindingsByKey[key] = nil
				dirtyKeys[key] = nil
			end
		end
	end
end

const function addBinding(action: any, spec: BindingSpec, options: BindOptions?): any
	local mods, keys, declaration = parseSpec(spec)

	local filter = -1
	for _, key in keys do
		const bit = modBitOf(key)
		if bit ~= 0 then
			filter = bit32.band(filter, bit32.bnot(bit))
		end
	end

	orderSeed += 1

	const exact = if declaration ~= nil and declaration.Exact ~= nil
		then declaration.Exact
		elseif options ~= nil and options.Exact ~= nil then options.Exact
		else true

	const sink = if declaration ~= nil and declaration.Sink ~= nil
		then declaration.Sink
		elseif options ~= nil and options.Sink ~= nil then options.Sink
		else false

	const processed = if declaration ~= nil and declaration.AllowGameProcessed ~= nil
		then declaration.AllowGameProcessed
		elseif options ~= nil and options.AllowGameProcessed ~= nil then options.AllowGameProcessed
		else false

	const binding = {
		keys = keys,
		mods = mods,
		filter = bit32.band(filter, 0xF),
		exact = exact,
		sink = sink,
		processed = processed,
		chord = #keys > 1,
		order = orderSeed,
		down = false,
		action = action,
		context = action.context,
		text = bindingText(mods, keys, "+", false),
	}

	for _, key in keys do
		local list = bindingsByKey[key]
		if list == nil then
			list = {}
			bindingsByKey[key] = list
		end
		table.insert(list, binding)
		markDirty(key)
	end

	table.insert(action.bindings, binding)
	ensureListeners()

	return binding
end

const function applyOptions(action: any, options: BindOptions?)
	if options == nil then
		return
	end

	if options.Hold ~= nil then
		action.holdTime = options.Hold
	end
	if options.Repeat ~= nil then
		action.repeatDelay = options.Repeat
		action.repeatRate = options.RepeatRate or DEFAULT_REPEAT_RATE
	end
	if options.TapTime ~= nil then
		action.tapTime = options.TapTime
	end
	if options.DoubleTap ~= nil then
		action.doubleWindow = options.DoubleTap
	end
	if options.Enabled ~= nil then
		action.enabled = options.Enabled
	end

	const public = action :: any
	if options.OnBegan ~= nil then
		public.Began:Connect(options.OnBegan)
	end
	if options.OnEnded ~= nil then
		public.Ended:Connect(options.OnEnded)
	end
	if options.OnTapped ~= nil then
		public.Tapped:Connect(options.OnTapped)
	end
	if options.OnDoubleTapped ~= nil then
		public.DoubleTapped:Connect(options.OnDoubleTapped)
	end
	if options.OnHeld ~= nil then
		public.Held:Connect(options.OnHeld)
	end
	if options.OnRepeated ~= nil then
		public.Repeated:Connect(options.OnRepeated)
	end
	if options.OnChanged ~= nil then
		public.Changed:Connect(options.OnChanged)
	end
	if options.WhileDown ~= nil then
		ActionMethods.WhileDown(action, options.WhileDown)
	end
end

function ActionMethods.IsDown(self: any): boolean
	return self.down
end

function ActionMethods.GetValue(self: any): number
	return self.value
end

function ActionMethods.GetDownTime(self: any): number
	if not self.down then
		return 0
	end
	return os.clock() - self.pressedAt
end

function ActionMethods.JustPressed(self: any, window: number?): boolean
	return os.clock() - self.pressedAt <= (window or 0.2)
end

function ActionMethods.Consume(self: any, window: number?): boolean
	const stamp = self.pressedAt
	if stamp == self.consumed then
		return false
	end
	if os.clock() - stamp > (window or 0.2) then
		return false
	end
	self.consumed = stamp
	return true
end

function ActionMethods.WhileDown(self: any, handler: (delta: number) -> ()): Connection
	local signal: any = self.whileSignal
	if signal == false then
		signal = Signal.new()
		self.whileSignal = signal
	end
	const connection = signal:Connect(handler)
	if wantsFrame(self) then
		markActive(self)
	end
	return connection
end

function ActionMethods.SetEnabled(self: any, state: boolean): any
	if self.enabled == state then
		return self
	end
	self.enabled = state
	if not state and self.holds > 0 then
		for _, binding in self.bindings do
			binding.down = false
		end
		self.holds = 1
		endAction(self, nil)
	end
	return self
end

function ActionMethods.SetHold(self: any, seconds: number?): any
	self.holdTime = seconds or 0
	return self
end

function ActionMethods.SetRepeat(self: any, delay: number?, rate: number?): any
	if delay == nil then
		self.repeatDelay = 0
		self.repeatRate = 0
	else
		self.repeatDelay = delay
		self.repeatRate = rate or DEFAULT_REPEAT_RATE
	end
	return self
end

function ActionMethods.SetTapTime(self: any, seconds: number): any
	self.tapTime = seconds
	return self
end

function ActionMethods.SetDoubleTap(self: any, seconds: number): any
	self.doubleWindow = seconds
	return self
end

function ActionMethods.Add(self: any, spec: BindingSpec, options: BindOptions?): any
	addBinding(self, spec, options)
	return self
end

function ActionMethods.Clear(self: any): any
	for index = #self.bindings, 1, -1 do
		removeBinding(self.bindings[index])
		self.bindings[index] = nil
	end
	return self
end

function ActionMethods.Set(self: any, specs: BindingList, options: BindOptions?): any
	ActionMethods.Clear(self)

	if typeof(specs) == "table" and (specs :: any).Key == nil and (specs :: any).Chord == nil and (specs :: any).Modifiers == nil then
		for _, spec in specs :: { BindingSpec } do
			addBinding(self, spec, options)
		end
	else
		addBinding(self, specs :: BindingSpec, options)
	end

	return self
end

function ActionMethods.Restore(self: any): any
	return ActionMethods.Set(self, self.defaults)
end

function ActionMethods.GetBindings(self: any): { string }
	const out = table.create(#self.bindings) :: { string }
	for index, binding in self.bindings do
		out[index] = binding.text
	end
	return out
end

function ActionMethods.GetDisplay(self: any, separator: string?): string
	const bindings = self.bindings
	if #bindings == 0 then
		return "-"
	end
	const out = table.create(#bindings) :: { string }
	for index, binding in bindings do
		out[index] = bindingText(binding.mods, binding.keys, " + ", true)
	end
	return table.concat(out, separator or " / ")
end

function ActionMethods.Push(self: any, down: boolean)
	if down then
		if self.pushed then
			return
		end
		self.pushed = true
		beginAction(self, nil)
	elseif self.pushed then
		self.pushed = false
		endAction(self, nil)
	end
end

function ActionMethods.Destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true

	ActionMethods.Clear(self)

	unmarkActive(self)

	const index = table.find(allActions, self)
	if index ~= nil then
		table.remove(allActions, index)
	end

	self.context.actions[self.Name] = nil

	for field in SIGNAL_FIELDS do
		const signal = rawget(self, field) :: AnySignal?
		if signal ~= nil then
			signal:Destroy()
		end
	end

	const while_ = self.whileSignal
	if while_ ~= false then
		(while_ :: AnySignal):Destroy()
		self.whileSignal = false
	end
end

const ContextMethods = {}
const ContextMeta = {
	__index = ContextMethods,
	__tostring = function(self: any): string
		return `Context<{self.Name}>`
	end,
}

const function createAction(context: any, name: string): any
	const record = setmetatable({
		Name = name,
		Context = context.Name,

		context = context,
		bindings = {},
		defaults = {},
		enabled = true,
		destroyed = false,
		down = false,
		pushed = false,
		holds = 0,
		value = 0,
		pressedAt = -math.huge,
		releasedAt = -math.huge,
		lastPress = -math.huge,
		consumed = -math.huge,
		tapTime = DEFAULT_TAP_TIME,
		doubleWindow = DEFAULT_DOUBLE_TAP,
		holdTime = 0,
		holdAt = 0,
		holdPending = false,
		holdFired = false,
		repeatDelay = 0,
		repeatRate = 0,
		nextRepeat = 0,
		whileSignal = false :: any,
		activeIndex = 0,
	}, ActionMeta)

	context.actions[name] = record
	table.insert(allActions, record)

	return record
end

function ContextMethods.Action(self: any, name: string): any
	const existing = self.actions[name]
	if existing ~= nil then
		return existing
	end
	return createAction(self, name)
end

function ContextMethods.Bind(self: any, name: string, specs: any, options: BindOptions?): any
	const action = ContextMethods.Action(self, name)

	if specs ~= nil then
		ActionMethods.Set(action, specs, options)
		table.clear(action.defaults)
		for index, binding in action.bindings do
			action.defaults[index] = binding.text
		end
	end

	applyOptions(action, options)

	return action
end

function ContextMethods.GetActions(self: any): { any }
	const out = {}
	for _, action in self.actions do
		table.insert(out, action)
	end
	return out
end

function ContextMethods.SetEnabled(self: any, state: boolean): any
	if self.enabled == state then
		return self
	end
	self.enabled = state

	if not state then
		for _, action in self.actions do
			if action.holds > 0 then
				for _, binding in action.bindings do
					binding.down = false
				end
				action.holds = 1
				endAction(action, nil)
			end
		end
	end

	refreshExclusiveFloor()
	return self
end

function ContextMethods.Enable(self: any): any
	return ContextMethods.SetEnabled(self, true)
end

function ContextMethods.Disable(self: any): any
	return ContextMethods.SetEnabled(self, false)
end

function ContextMethods.IsEnabled(self: any): boolean
	return self.enabled
end

function ContextMethods.SetPriority(self: any, priority: number): any
	if self.priority == priority then
		return self
	end
	self.priority = priority
	self.Priority = priority

	for key in bindingsByKey do
		markDirty(key)
	end

	refreshExclusiveFloor()
	return self
end

function ContextMethods.SetExclusive(self: any, state: boolean): any
	self.exclusive = state
	refreshExclusiveFloor()
	return self
end

function ContextMethods.Destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true

	for _, action in ContextMethods.GetActions(self) do
		ActionMethods.Destroy(action)
	end

	contexts[self.Name] = nil
	const index = table.find(contextList, self)
	if index ~= nil then
		table.remove(contextList, index)
	end

	refreshExclusiveFloor()
end

function InputController.Context(name: string, options: ContextOptions?): Context
	const existing = contexts[name]
	if existing ~= nil then
		if options ~= nil then
			if options.Priority ~= nil then
				ContextMethods.SetPriority(existing, options.Priority)
			end
			if options.Exclusive ~= nil then
				ContextMethods.SetExclusive(existing, options.Exclusive)
			end
			if options.Enabled ~= nil then
				ContextMethods.SetEnabled(existing, options.Enabled)
			end
		end
		return existing
	end

	const priority = if options ~= nil and options.Priority ~= nil then options.Priority else 0

	const context = setmetatable({
		Name = name,
		Priority = priority,

		priority = priority,
		exclusive = if options ~= nil then options.Exclusive == true else false,
		enabled = if options ~= nil and options.Enabled ~= nil then options.Enabled else true,
		destroyed = false,
		actions = {},
	}, ContextMeta)

	contexts[name] = context
	table.insert(contextList, context)
	refreshExclusiveFloor()

	return (context :: any) :: Context
end

const DefaultContext = InputController.Context("Default")

function InputController.Bind(name: string, specs: BindingList?, options: BindOptions?): Action
	return (DefaultContext :: any):Bind(name, specs, options)
end

function InputController.Action(name: string): Action
	return (DefaultContext :: any):Action(name)
end

function InputController.Find(name: string, context: string?): Action?
	if context ~= nil then
		const holder = contexts[context]
		return if holder ~= nil then holder.actions[name] else nil
	end
	for _, holder in contextList do
		const action = holder.actions[name]
		if action ~= nil then
			return action
		end
	end
	return nil
end

const function collectKeys(value: BindingList?, out: { DispatchKey })
	if value == nil then
		return
	end

	if typeof(value) == "table" and (value :: any).Key == nil and (value :: any).Chord == nil then
		for _, entry in value :: { BindingSpec } do
			local _, keys = parseSpec(entry)
			for _, key in keys do
				table.insert(out, key)
			end
		end
		return
	end

	local _, keys = parseSpec(value :: BindingSpec)
	for _, key in keys do
		table.insert(out, key)
	end
end

const function anyDown(keys: { DispatchKey }): boolean
	for index = 1, #keys do
		if pressed[keys[index]] then
			return true
		end
	end
	return false
end

const function watch(keys: { DispatchKey }, node: any)
	for _, key in keys do
		local list = watchers[key]
		if list == nil then
			list = {}
			watchers[key] = list
		end
		table.insert(list, node)
	end
end

const function unwatch(keys: { DispatchKey }, node: any)
	for _, key in keys do
		const list = watchers[key]
		if list == nil then
			continue
		end
		const index = table.find(list, node)
		if index ~= nil then
			table.remove(list, index)
			if #list == 0 then
				watchers[key] = nil
			end
		end
	end
end

const function applyDeadzone(value: number, deadzone: number): number
	const magnitude = math.abs(value)
	if magnitude <= deadzone then
		return 0
	end
	return math.sign(value) * ((magnitude - deadzone) / (1 - deadzone))
end

const AxisMethods = {}
const AxisMeta = { __index = AxisMethods }

const function refreshAxis(node: any)
	local value = 0

	if anyDown(node.positive) then
		value += 1
	end
	if anyDown(node.negative) then
		value -= 1
	end

	const stick = node.gamepad
	if stick ~= nil then
		const raw = analog[stick]
		if raw ~= nil then
			value += applyDeadzone((raw :: any)[node.component], node.deadzone)
		end
	end

	value = math.clamp(value, -1, 1)
	if node.invert then
		value = -value
	end

	if value ~= node.value then
		node.value = value
		node.Changed:Fire(value)
	end
end

function AxisMethods.Get(self: any): number
	return self.value
end

function AxisMethods.Destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true
	unwatch(self.keys, self)
	self.Changed:Destroy()
end

function InputController.Axis(name: string, spec: AxisSpec): Axis
	const positive: { DispatchKey } = {}
	const negative: { DispatchKey } = {}
	collectKeys(spec.Positive, positive)
	collectKeys(spec.Negative, negative)

	const keys: { DispatchKey } = table.clone(positive)
	for _, key in negative do
		table.insert(keys, key)
	end
	if spec.Gamepad ~= nil then
		table.insert(keys, spec.Gamepad)
	end

	const node = setmetatable({
		Name = name,
		Changed = Signal.new(),

		positive = positive,
		negative = negative,
		keys = keys,
		gamepad = spec.Gamepad,
		component = spec.Component or "X",
		deadzone = spec.Deadzone or DEFAULT_DEADZONE,
		invert = spec.Invert == true,
		value = 0,
		destroyed = false,
		refresh = refreshAxis,
	}, AxisMeta)

	watch(keys, node)
	ensureListeners()

	return (node :: any) :: Axis
end

const VectorMethods = {}
const VectorMeta = { __index = VectorMethods }

const function refreshVector(node: any)
	local x = 0
	local y = 0

	if anyDown(node.right) then
		x += 1
	end
	if anyDown(node.left) then
		x -= 1
	end
	if anyDown(node.up) then
		y += 1
	end
	if anyDown(node.down) then
		y -= 1
	end

	const stick = node.gamepad
	if stick ~= nil then
		const raw = analog[stick]
		if raw ~= nil then
			x += applyDeadzone(raw.X, node.deadzone)
			y += applyDeadzone(raw.Y, node.deadzone)
		end
	end

	local result = Vector2.new(x, y)
	const magnitude = result.Magnitude

	if magnitude > 1 or (node.normalize and magnitude > 0) then
		result /= magnitude
	end

	if result ~= node.value then
		node.value = result
		node.Changed:Fire(result)
	end
end

function VectorMethods.Get(self: any): Vector2
	return self.value
end

function VectorMethods.Destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true
	unwatch(self.keys, self)
	self.Changed:Destroy()
end

function InputController.Vector(name: string, spec: VectorSpec): Vector
	const up: { DispatchKey } = {}
	const down: { DispatchKey } = {}
	const left: { DispatchKey } = {}
	const right: { DispatchKey } = {}
	collectKeys(spec.Up, up)
	collectKeys(spec.Down, down)
	collectKeys(spec.Left, left)
	collectKeys(spec.Right, right)

	const keys: { DispatchKey } = {}
	for _, group in { up, down, left, right } do
		for _, key in group do
			table.insert(keys, key)
		end
	end
	if spec.Gamepad ~= nil then
		table.insert(keys, spec.Gamepad)
	end

	const node = setmetatable({
		Name = name,
		Changed = Signal.new(),

		up = up,
		down = down,
		left = left,
		right = right,
		keys = keys,
		gamepad = spec.Gamepad,
		deadzone = spec.Deadzone or DEFAULT_DEADZONE,
		normalize = spec.Normalize == true,
		value = Vector2.zero,
		destroyed = false,
		refresh = refreshVector,
	}, VectorMeta)

	watch(keys, node)
	ensureListeners()

	return (node :: any) :: Vector
end

const DragMethods = {}
const DragMeta = { __index = DragMethods }

function DragMethods.IsActive(self: any): boolean
	return self.active
end

function DragMethods.GetOrigin(self: any): Vector2
	return self.origin
end

function DragMethods.GetPosition(self: any): Vector2
	return self.position
end

function DragMethods.Destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true

	const index = table.find(drags, self)
	if index ~= nil then
		table.remove(drags, index)
	end

	ActionMethods.Destroy(self.action)
	self.Began:Destroy()
	self.Changed:Destroy()
	self.Ended:Destroy()
	self.Clicked:Destroy()
end

function InputController.Drag(name: string, spec: DragSpec?): Drag
	const declaration: DragSpec = spec or {}
	const context = (declaration.Context :: any) or DefaultContext

	const node = setmetatable({
		Name = name,
		Began = Signal.new(),
		Changed = Signal.new(),
		Ended = Signal.new(),
		Clicked = Signal.new(),

		threshold = declaration.Threshold or DEFAULT_DRAG_THRESHOLD,
		origin = Vector2.zero,
		position = Vector2.zero,
		holding = false,
		active = false,
		destroyed = false,
		action = nil,
	}, DragMeta)

	const action = ContextMethods.Bind(context, `__Drag/{name}`, declaration.Button or "MouseButton1", {
		AllowGameProcessed = declaration.AllowGameProcessed,
	})
	node.action = action

	;(action :: any).Began:Connect(function()
		const position = UserInputService:GetMouseLocation()
		node.origin = position
		node.position = position
		node.holding = true
		node.active = false
	end)

	;(action :: any).Ended:Connect(function()
		if not node.holding then
			return
		end
		node.holding = false
		if node.active then
			node.active = false
			node.Ended:Fire(node.position, node.position - node.origin)
		else
			node.Clicked:Fire(node.position)
		end
	end)

	table.insert(drags, node)
	ensureListeners()

	return (node :: any) :: Drag
end

const SequenceMethods = {}
const SequenceMeta = { __index = SequenceMethods }

function SequenceMethods.Reset(self: any)
	self.index = 0
end

function SequenceMethods.Destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true
	const index = table.find(sequences, self)
	if index ~= nil then
		table.remove(sequences, index)
	end
	self.Triggered:Destroy()
end

function InputController.Sequence(name: string, specs: { BindingSpec }, window: number?): Sequence
	const keys: { DispatchKey } = {}
	for _, spec in specs do
		local _, parsed = parseSpec(spec)
		table.insert(keys, parsed[#parsed])
	end

	const node = setmetatable({
		Name = name,
		Triggered = Signal.new(),

		keys = keys,
		length = #keys,
		index = 0,
		lastAt = 0,
		window = window or DEFAULT_SEQUENCE_WINDOW,
		destroyed = false,
	}, SequenceMeta)

	table.insert(sequences, node)
	ensureListeners()

	return (node :: any) :: Sequence
end

function InputController.Capture(callback: (binding: string?) -> (), options: CaptureOptions?): () -> ()
	const declaration: CaptureOptions = options or {}
	const cancelSpec = declaration.Cancel
	local cancelKey: DispatchKey = Enum.KeyCode.Escape

	if cancelSpec ~= nil then
		local _, keys = parseSpec(cancelSpec)
		cancelKey = keys[1]
	end

	capturing = {
		callback = callback,
		modifiers = declaration.Modifiers ~= false,
		keyboard = declaration.Keyboard ~= false,
		mouse = declaration.Mouse ~= false,
		gamepad = declaration.Gamepad ~= false,
		cancel = cancelKey,
	}

	const session = capturing
	ensureListeners()

	return function()
		if capturing == session then
			capturing = nil
		end
	end
end

function InputController.Rebind(action: Action, index: number?, options: CaptureOptions?): () -> ()
	const record = action :: any
	const slot = index or 1

	return InputController.Capture(function(binding: string?)
		if binding == nil then
			return
		end
		const bindings = ActionMethods.GetBindings(record)
		bindings[slot] = binding
		ActionMethods.Set(record, bindings :: any)
	end, options)
end

function InputController.Parse(spec: BindingSpec): string
	local mods, keys = parseSpec(spec)
	return bindingText(mods, keys, "+", false)
end

function InputController.Display(spec: BindingSpec, separator: string?): string
	local mods, keys = parseSpec(spec)
	return bindingText(mods, keys, separator or " + ", true)
end

function InputController.IsDown(name: string): boolean
	const action = InputController.Find(name)
	return action ~= nil and (action :: any).down
end

function InputController.IsKeyDown(key: string | InputKey): boolean
	return pressed[coerceKey(key)] == true
end

function InputController.GetAnalog(key: string | InputKey): Vector3
	return analog[coerceKey(key)] or Vector3.zero
end

function InputController.GetModifiers(): number
	return modMask
end

function InputController.IsModifierDown(name: string): boolean
	const key = coerceKey(name)
	const bit = modBitOf(key)
	if bit == 0 then
		return false
	end
	return bit32.btest(modMask, bit)
end

function InputController.GetDevice(): Device
	return device
end

function InputController.HasGamepad(): boolean
	return UserInputService.GamepadEnabled
end

function InputController.HasTouch(): boolean
	return UserInputService.TouchEnabled
end

function InputController.HasKeyboard(): boolean
	return UserInputService.KeyboardEnabled
end

function InputController.HasMouse(): boolean
	return UserInputService.MouseEnabled
end

function InputController.IsTyping(): boolean
	return typing
end

function InputController.GetMousePosition(): Vector2
	return UserInputService:GetMouseLocation()
end

function InputController.GetMouseDelta(): Vector2
	return UserInputService:GetMouseDelta() * sensitivity
end

function InputController.SetSensitivity(value: number)
	sensitivity = value
end

function InputController.GetSensitivity(): number
	return sensitivity
end

function InputController.SetMouseBehavior(behavior: Enum.MouseBehavior)
	UserInputService.MouseBehavior = behavior
end

function InputController.LockMouse(center: boolean?)
	UserInputService.MouseBehavior = if center == false then Enum.MouseBehavior.LockCurrentPosition else Enum.MouseBehavior.LockCenter
end

function InputController.UnlockMouse()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

function InputController.SetMouseIconEnabled(state: boolean)
	UserInputService.MouseIconEnabled = state
end

function InputController.GetMouseRay(depth: number?): Ray
	const camera = Workspace.CurrentCamera
	if camera == nil then
		return Ray.new(Vector3.zero, Vector3.zero)
	end
	const position = UserInputService:GetMouseLocation()
	const unit = camera:ViewportPointToRay(position.X, position.Y)
	return Ray.new(unit.Origin, unit.Direction * (depth or 1000))
end

function InputController.MouseRaycast(params: RaycastParams?, depth: number?): RaycastResult?
	const ray = InputController.GetMouseRay(depth)
	if ray.Direction.Magnitude == 0 then
		return nil
	end
	return Workspace:Raycast(ray.Origin, ray.Direction, params)
end

const TOUCH_SOURCES: { [string]: string } = {
	Tap = "TouchTap",
	LongPress = "TouchLongPress",
	Pan = "TouchPan",
	Pinch = "TouchPinch",
	Rotate = "TouchRotate",
	Swipe = "TouchSwipe",
	Started = "TouchStarted",
	Moved = "TouchMoved",
	Ended = "TouchEnded",
}

InputController.Touch = setmetatable({}, {
	__index = function(self: any, key: string): any
		const source = TOUCH_SOURCES[key]
		if source == nil then
			return nil
		end
		const wrapped = Signal.wrap((UserInputService :: any)[source])
		rawset(self, key, wrapped)
		return wrapped
	end,
})

function InputController.SetEnabled(state: boolean)
	if enabled == state then
		return
	end
	enabled = state
	if not state then
		releaseAll()
	end
end

function InputController.IsEnabled(): boolean
	return enabled
end

function InputController.ReleaseAll()
	releaseAll()
end

function InputController.Serialize(): { [string]: { [string]: { string } } }
	const out: { [string]: { [string]: { string } } } = {}

	for _, context in contextList do
		const entries: { [string]: { string } } = {}
		local populated = false
		for name, action in context.actions do
			if string.sub(name, 1, 7) ~= "__Drag/" then
				entries[name] = ActionMethods.GetBindings(action)
				populated = true
			end
		end
		if populated then
			out[context.Name] = entries
		end
	end

	return out
end

function InputController.Deserialize(data: { [string]: { [string]: { string } } })
	for contextName, entries in data do
		const context = contexts[contextName]
		if context == nil then
			continue
		end
		for name, bindings in entries do
			const action = context.actions[name]
			if action ~= nil then
				ActionMethods.Set(action, bindings :: any)
			end
		end
	end
end

function InputController.ResetBindings(context: string?)
	for _, holder in contextList do
		if context ~= nil and holder.Name ~= context then
			continue
		end
		for _, action in holder.actions do
			ActionMethods.Restore(action)
		end
	end
end

function InputController.Destroy()
	releaseAll()

	for index = #contextList, 1, -1 do
		ContextMethods.Destroy(contextList[index])
	end

	for index = #sequences, 1, -1 do
		SequenceMethods.Destroy(sequences[index])
	end

	for index = #drags, 1, -1 do
		DragMethods.Destroy(drags[index])
	end

	if stepConnection ~= nil then
		stepConnection:Disconnect()
		stepConnection = nil
	end

	if listenerScope ~= nil then
		Scythe.destroy(listenerScope)
		listenerScope = nil
	end
end

return InputController
