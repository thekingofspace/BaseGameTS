--!strict
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Shared = require(script.Parent.Shared)
local Pigeon = require(script.Parent.Parent.Pigeon)
local signal = require(script.Parent.Parent.signal)

type AssetRecord = {
    Id: string,
    Original: Instance,
    Staged: Instance?,
    Confirmed: boolean,
}

type PlayerState = {
    ById: {[string]: AssetRecord},
    ByObject: {[Instance]: AssetRecord},
}

type TrackedObject = {
    Connection: RBXScriptConnection,
    Refs: number,
}

local module = {}

module.OnConfirmed = signal.new("Deffered") :: signal.Signal<Player, Instance>
module.OnRemoved = signal.new("Deffered") :: signal.Signal<Player, Instance>

local Player_States: {[Player]: PlayerState} = {}
local Tracked_Objects: {[Instance]: TrackedObject} = {}
local Persistent_Objects: {[Instance]: boolean} = {}

local Replication_Pigeon = Pigeon.new(Shared.PIGEON_NAME)

local function normalizeTargets(targets: Player | {Player}): {Player}
    if typeof(targets) == "Instance" then
        return { (targets :: any) :: Player }
    end
    return targets :: {Player}
end

local function getPlayerState(player: Player): PlayerState?
    local state = Player_States[player]
    if state then
        return state
    end
    if not player:IsDescendantOf(Players) then
        return nil
    end

    state = { ById = {}, ByObject = {} }
    Player_States[player] = state
    return state
end

local function getReceiverFolder(player: Player): Folder?
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
        or player:WaitForChild("PlayerGui", 10)
    if not playerGui then
        return nil
    end

    local existing = playerGui:FindFirstChild(Shared.RECEIVER_NAME)
    if existing and existing:IsA("Folder") then
        return existing
    end

    local folder = Instance.new("Folder")
    folder.Name = Shared.RECEIVER_NAME
    folder.Parent = playerGui
    return folder
end

local function untrackObject(object: Instance)
    local tracked = Tracked_Objects[object]
    if not tracked then
        return
    end
    tracked.Refs -= 1
    if tracked.Refs <= 0 then
        tracked.Connection:Disconnect()
        Tracked_Objects[object] = nil
    end
end

local function removeRecord(player: Player, state: PlayerState, record: AssetRecord, notifyClient: boolean)
    state.ById[record.Id] = nil
    state.ByObject[record.Original] = nil

    if record.Staged then
        record.Staged:Destroy()
        record.Staged = nil
    end
    if notifyClient then
        Replication_Pigeon:BroadcastTo({ player }, Shared.MSG_REVOKE, record.Id)
    end

    untrackObject(record.Original)
    module.OnRemoved:Fire(player, record.Original)
end

local function onOriginalDestroyed(object: Instance)
    Persistent_Objects[object] = nil
    for player, state in Player_States do
        local record = state.ByObject[object]
        if record then
            removeRecord(player, state, record, true)
        end
    end

    local tracked = Tracked_Objects[object]
    if tracked then
        tracked.Connection:Disconnect()
        Tracked_Objects[object] = nil
    end
end

local function trackObject(object: Instance)
    local tracked = Tracked_Objects[object]
    if tracked then
        tracked.Refs += 1
        return
    end
    Tracked_Objects[object] = {
        Refs = 1,
        Connection = object.Destroying:Once(function()
            onOriginalDestroyed(object)
        end),
    }
end

local function stageForPlayer(player: Player, state: PlayerState, record: AssetRecord)
    local receiver = getReceiverFolder(player)
    if state.ById[record.Id] ~= record then
        return
    end
    if not receiver then
        warn(string.format(
            "[ReplicationPP] No PlayerGui for %s; cannot replicate %s",
            player.Name,
            record.Original:GetFullName()
        ))
        removeRecord(player, state, record, false)
        return
    end

    local staged = record.Original:Clone()
    if not staged then
        warn(string.format(
            "[ReplicationPP] %s is not Archivable; cannot replicate it to %s",
            record.Original:GetFullName(),
            player.Name
        ))
        removeRecord(player, state, record, false)
        return
    end

    staged:SetAttribute(Shared.ATTR_ID, record.Id)
    staged:SetAttribute(Shared.ATTR_DESCENDANTS, #staged:GetDescendants())
    record.Staged = staged
    staged.Parent = receiver
end

function module.ReplicateAsset(targets: Player | {Player}, object: Instance)
    for _, player in normalizeTargets(targets) do
        local state = getPlayerState(player)
        if not state or state.ByObject[object] then
            continue
        end

        local record: AssetRecord = {
            Id = HttpService:GenerateGUID(false),
            Original = object,
            Staged = nil,
            Confirmed = false,
        }
        state.ById[record.Id] = record
        state.ByObject[object] = record
        trackObject(object)

        task.spawn(stageForPlayer, player, state, record)
    end
end

function module.ReplicateToAll(object: Instance, persistent: boolean?)
    if persistent and not Persistent_Objects[object] then
        Persistent_Objects[object] = true
        trackObject(object)
    end
    module.ReplicateAsset(Players:GetPlayers(), object)
end

function module.UnReplicate(targets: Player | {Player}, object: Instance)
    for _, player in normalizeTargets(targets) do
        local state = Player_States[player]
        local record = state and state.ByObject[object]
        if record then
            removeRecord(player, state, record, true)
        end
    end
end

function module.UnReplicateAll(object: Instance)
    if Persistent_Objects[object] then
        Persistent_Objects[object] = nil
        untrackObject(object)
    end
    for player, state in Player_States do
        local record = state.ByObject[object]
        if record then
            removeRecord(player, state, record, true)
        end
    end
end

function module.IsReplicated(player: Player, object: Instance): boolean
    local state = Player_States[player]
    local record = state and state.ByObject[object]
    return record ~= nil and record.Confirmed
end

function module.IsPending(player: Player, object: Instance): boolean
    local state = Player_States[player]
    local record = state and state.ByObject[object]
    return record ~= nil and not record.Confirmed
end

function module.GetReplicatedPlayers(object: Instance): {Player}
    local holders = {}
    for player, state in Player_States do
        local record = state.ByObject[object]
        if record and record.Confirmed then
            table.insert(holders, player)
        end
    end
    return holders
end

Replication_Pigeon:On(Shared.MSG_CLAIM, function(player: Player, id: unknown)
    if typeof(id) ~= "string" then
        return
    end
    local state = Player_States[player]
    local record = state and state.ById[id]
    if not record or record.Confirmed then
        return
    end

    record.Confirmed = true
    if record.Staged then
        record.Staged:Destroy()
        record.Staged = nil
    end
    module.OnConfirmed:Fire(player, record.Original)
end)

Replication_Pigeon:On(Shared.MSG_REMOVE, function(player: Player, id: unknown)
    if typeof(id) ~= "string" then
        return
    end
    local state = Player_States[player]
    local record = state and state.ById[id]
    if record then
        removeRecord(player, state :: PlayerState, record, false)
    end
end)

Players.PlayerAdded:Connect(function(player)
    for object in Persistent_Objects do
        module.ReplicateAsset(player, object)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    local state = Player_States[player]
    if not state then
        return
    end
    Player_States[player] = nil
    for _, record in state.ById do
        untrackObject(record.Original)
    end
end)

return module
