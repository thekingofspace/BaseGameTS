local Players = game:GetService("Players")

export type CameraModule = {
	activeCameraController: any?,
	activeMouseLockController: any?,
	activeOcclusionModule: any?,
	activeTransparencyController: any,

	cameraSubjectChangedConn: RBXScriptConnection?,
	cameraTypeChangedConn: RBXScriptConnection?,
	connectionUtil: any?,

	currentComputerCameraMovementMode: Enum.ComputerCameraMovementMode? | Enum.DevComputerCameraMovementMode?,
	occlusionMode: Enum.DevCameraOcclusionMode?,

	ActivateCameraController: (self: CameraModule) -> (),
	ActivateOcclusionModule: (self: CameraModule, occlusionMode: Enum.DevCameraOcclusionMode) -> (),
	GetCameraMovementModeFromSettings: (self: CameraModule) -> Enum.ComputerCameraMovementMode | Enum.DevComputerCameraMovementMode,
	OnPreferredInputChanged: (self: CameraModule) -> (),
	OnCameraSubjectChanged: (self: CameraModule) -> (),
	OnCameraTypeChanged: (self: CameraModule, newCameraType: Enum.CameraType) -> (),
	OnCharacterAdded: (self: CameraModule, character: Model, player: Player) -> (),
	OnCharacterRemoving: (self: CameraModule, character: Model, player: Player) -> (),
	OnCurrentCameraChanged: (self: CameraModule) -> (),
	OnLocalPlayerCameraPropertyChanged: (self: CameraModule, propertyName: string) -> (),
	OnPlayerAdded: (self: CameraModule, player: Player) -> (),
	OnPlayerRemoving: (self: CameraModule, player: Player) -> (),
	OnMouseLockToggled: (self: CameraModule) -> (),
	OnUserGameSettingsPropertyChanged: (self: CameraModule, propertyName: string) -> (),
	ShouldUseVehicleCamera: (self: CameraModule) -> boolean,
	Update: (self: CameraModule, dt: number) -> (),
}

export type Controller = {
	Enable: (self: Controller, enabled: boolean, ...any) -> (),
	GetMoveVector: (self: Controller) -> Vector3,
	IsMoveVectorCameraRelative: (self: Controller) -> boolean,
	GetIsJumping: (self: Controller) -> boolean,
	OnRenderStepped: (self: Controller, dt: number) -> ()?,
	CleanupPath: (self: Controller) -> ()?,
	enabled: boolean?,
}

export type VehicleController = {
	Enable: (self: VehicleController, enabled: boolean, seat: BasePart?) -> (),
	Update: (self: VehicleController, moveVector: Vector3, cameraRelative: boolean, usingGamepad: boolean) -> (Vector3, boolean),
}

export type ControlModule = {
	controllers: {[any]: Controller},
	activeControlModule: any?,
	activeController: Controller?,
	touchJumpController: Controller?,
	moveFunction: (Player, Vector3, boolean) -> (),
	humanoid: Humanoid?,
	controlsEnabled: boolean,
	humanoidSeatedConn: RBXScriptConnection?,
	vehicleController: VehicleController?,
	touchControlFrame: Frame?,
	currentTorsoAngle: number,
	inputMoveVector: Vector3,
	playerGui: PlayerGui?,
	touchGui: ScreenGui?,
	playerGuiAddedConn: RBXScriptConnection?,

	GetMoveVector: (self: ControlModule) -> Vector3,
	GetEstimatedVRTorsoFrame: (self: ControlModule) -> CFrame,
	GetActiveController: (self: ControlModule) -> Controller?,
	UpdateActiveControlModuleEnabled: (self: ControlModule) -> (),
	Enable: (self: ControlModule, enable: boolean?) -> (),
	Disable: (self: ControlModule) -> (),
	SelectComputerMovementModule: (self: ControlModule) -> (any?, boolean),
	SelectTouchModule: (self: ControlModule) -> (any?, boolean),
	calculateRawMoveVector: (self: ControlModule, humanoid: Humanoid, cameraRelativeMoveVector: Vector3) -> Vector3,
	OnRenderStepped: (self: ControlModule, dt: number) -> (),
	updateVRMoveVector: (self: ControlModule, moveVector: Vector3) -> Vector3,
	OnHumanoidSeated: (self: ControlModule, active: boolean, currentSeatPart: BasePart) -> (),
	OnCharacterAdded: (self: ControlModule, char: Model) -> (),
	OnCharacterRemoving: (self: ControlModule, char: Model) -> (),
	UpdateTouchGuiVisibility: (self: ControlModule) -> (),
	SwitchToController: (self: ControlModule, controlModule: any?) -> (),
	UpdateMovementMode: (self: ControlModule) -> (),
	CreateTouchGuiContainer: (self: ControlModule) -> (),
	GetClickToMoveController: (self: ControlModule) -> Controller,
}

export type PlayerModule = {
	GetCameras: (self: PlayerModule) -> CameraModule,
	GetControls: (self: PlayerModule) -> ControlModule,
	GetClickToMoveController: (self: PlayerModule) -> any,
}

return require(Players.LocalPlayer.PlayerScripts:WaitForChild("PlayerModule")) :: PlayerModule