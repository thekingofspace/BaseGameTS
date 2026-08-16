/**
 * Type declarations for `ClientModule.luau`.
 *
 * The module does not define anything of its own — it requires Roblox's stock
 * `PlayerModule` out of `Players.LocalPlayer.PlayerScripts` and re-exports it
 * under a hand-written type. So the value you get back IS the PlayerModule, not
 * a wrapper: `ClientModule.GetControls()` is the entry point, and requiring it
 * on the server (or before `LocalPlayer` exists) will yield forever.
 *
 * Every member below is written `(self: X, ...)` in the Luau, so they are all
 * declared as methods and compile to colon calls. `moveFunction` is the one
 * exception — it is a plain function-valued field, so it stays a property.
 *
 * Fields the Luau types as `any` are `unknown` here; narrow them at the call
 * site if you need to reach into a specific stock controller.
 */

declare namespace ClientModule {
	interface CameraModule {
		activeCameraController: unknown;
		activeMouseLockController: unknown;
		activeOcclusionModule: unknown;
		activeTransparencyController: unknown;

		cameraSubjectChangedConn: RBXScriptConnection | undefined;
		cameraTypeChangedConn: RBXScriptConnection | undefined;
		connectionUtil: unknown;

		currentComputerCameraMovementMode:
			| Enum.ComputerCameraMovementMode
			| Enum.DevComputerCameraMovementMode
			| undefined;
		occlusionMode: Enum.DevCameraOcclusionMode | undefined;

		ActivateCameraController(): void;
		ActivateOcclusionModule(occlusionMode: Enum.DevCameraOcclusionMode): void;
		GetCameraMovementModeFromSettings():
			| Enum.ComputerCameraMovementMode
			| Enum.DevComputerCameraMovementMode;
		OnPreferredInputChanged(): void;
		OnCameraSubjectChanged(): void;
		OnCameraTypeChanged(newCameraType: Enum.CameraType): void;
		OnCharacterAdded(character: Model, player: Player): void;
		OnCharacterRemoving(character: Model, player: Player): void;
		OnCurrentCameraChanged(): void;
		OnLocalPlayerCameraPropertyChanged(propertyName: string): void;
		OnPlayerAdded(player: Player): void;
		OnPlayerRemoving(player: Player): void;
		OnMouseLockToggled(): void;
		OnUserGameSettingsPropertyChanged(propertyName: string): void;
		ShouldUseVehicleCamera(): boolean;
		Update(dt: number): void;
	}

	/** One of the stock movement controllers (keyboard, touch, gamepad, ...). */
	interface Controller {
		enabled: boolean | undefined;

		Enable(enabled: boolean, ...args: Array<unknown>): void;
		GetMoveVector(): Vector3;
		IsMoveVectorCameraRelative(): boolean;
		GetIsJumping(): boolean;
		/** Only present on controllers that need per-frame work. */
		OnRenderStepped?(dt: number): void;
		/** Only present on the click-to-move controller. */
		CleanupPath?(): void;
	}

	interface VehicleController {
		Enable(enabled: boolean, seat?: BasePart): void;
		/** Returns `(moveVector, cameraRelative)`. */
		Update(
			moveVector: Vector3,
			cameraRelative: boolean,
			usingGamepad: boolean,
		): LuaTuple<[Vector3, boolean]>;
	}

	interface ControlModule {
		controllers: Map<unknown, Controller>;
		activeControlModule: unknown;
		activeController: Controller | undefined;
		touchJumpController: Controller | undefined;
		/** Plain function field, not a method — called as `moveFunction(...)`. */
		moveFunction: (player: Player, moveVector: Vector3, relativeToCamera: boolean) => void;
		humanoid: Humanoid | undefined;
		controlsEnabled: boolean;
		humanoidSeatedConn: RBXScriptConnection | undefined;
		vehicleController: VehicleController | undefined;
		touchControlFrame: Frame | undefined;
		currentTorsoAngle: number;
		inputMoveVector: Vector3;
		playerGui: PlayerGui | undefined;
		touchGui: ScreenGui | undefined;
		playerGuiAddedConn: RBXScriptConnection | undefined;

		GetMoveVector(): Vector3;
		GetEstimatedVRTorsoFrame(): CFrame;
		GetActiveController(): Controller | undefined;
		UpdateActiveControlModuleEnabled(): void;
		Enable(enable?: boolean): void;
		Disable(): void;
		/** Returns `(controlModule, success)`. */
		SelectComputerMovementModule(): LuaTuple<[unknown, boolean]>;
		/** Returns `(controlModule, success)`. */
		SelectTouchModule(): LuaTuple<[unknown, boolean]>;
		calculateRawMoveVector(humanoid: Humanoid, cameraRelativeMoveVector: Vector3): Vector3;
		OnRenderStepped(dt: number): void;
		updateVRMoveVector(moveVector: Vector3): Vector3;
		OnHumanoidSeated(active: boolean, currentSeatPart: BasePart): void;
		OnCharacterAdded(char: Model): void;
		OnCharacterRemoving(char: Model): void;
		UpdateTouchGuiVisibility(): void;
		SwitchToController(controlModule?: unknown): void;
		UpdateMovementMode(): void;
		CreateTouchGuiContainer(): void;
		GetClickToMoveController(): Controller;
	}

	interface PlayerModule {
		GetCameras(): CameraModule;
		GetControls(): ControlModule;
		GetClickToMoveController(): unknown;
	}
}

declare const ClientModule: ClientModule.PlayerModule;

export = ClientModule;
