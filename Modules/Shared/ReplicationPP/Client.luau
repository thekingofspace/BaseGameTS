--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(script.Parent.Shared)
local Pigeon = require(script.Parent.Parent.Pigeon)
local signal = require(script.Parent.Parent.signal)

local STREAM_TIMEOUT = 10

local module = {}

module.OnReplication = signal.new("Deffered") :: signal.Signal<Instance>
module.OnUnReplication = signal.new("Deffered") :: signal.Signal<Instance>

local LocalPlayer = Players.LocalPlayer

local Assets_By_Id: {[string]: Instance} = {}
local Ids_By_Asset: {[Instance]: string} = {}
local Waiting_Threads: {[string]: {thread}} = {}
local Processing_Staged: {[Instance]: boolean} = {}
local Pending_Revokes: {[string]: boolean} = {}
local Bound_Receiver: Instance? = nil

-- A revoke can arrive before its asset finishes registering (staging streams
-- in asynchronously, and a whole backlog can be waiting when this module first
-- loads). Remember such revokes so registration is aborted when it completes,
-- instead of silently dropping the revoke and leaking a stale asset.
local function markRevoked(id: string)
    Pending_Revokes[id] = true
    task.delay(STREAM_TIMEOUT * 2, function()
        Pending_Revokes[id] = nil
    end)
end

local function consumeRevoke(id: string): boolean
    if Pending_Revokes[id] then
        Pending_Revokes[id] = nil
        return true
    end
    return false
end

local Asset_Folder: Folder
do
    local existing = ReplicatedStorage:FindFirstChild(Shared.ASSETS_NAME)
    if existing and existing:IsA("Folder") then
        Asset_Folder = existing
    else
        Asset_Folder = Instance.new("Folder")
        Asset_Folder.Name = Shared.ASSETS_NAME
        Asset_Folder.Parent = ReplicatedStorage
    end
end

-- Init() marks this client ready on the channel; until it lands the server
-- buffers its revokes instead of sending them.
local Replication_Pigeon = Pigeon.new(Shared.PIGEON_NAME):Init()

local function resumeWaiting(name: string, asset: Instance)
    local waiting = Waiting_Threads[name]
    if not waiting then
        return
    end
    Waiting_Threads[name] = nil
    for _, thread in waiting do
        task.spawn(thread, asset)
    end
end

local function waitForDescendants(staged: Instance, expected: number): boolean
    local deadline = os.clock() + STREAM_TIMEOUT
    while #staged:GetDescendants() < expected do
        if staged.Parent == nil then
            return false
        end
        if os.clock() > deadline then
            warn(string.format(
                "[ReplicationPP] %s still has %d/%d descendants after %ds; registering it anyway",
                staged.Name,
                #staged:GetDescendants(),
                expected,
                STREAM_TIMEOUT
            ))
            break
        end
        task.wait()
    end
    return staged.Parent ~= nil
end

local function registerAsset(staged: Instance, id: string)
    local asset = staged:Clone()
    asset:SetAttribute(Shared.ATTR_ID, nil)
    asset:SetAttribute(Shared.ATTR_DESCENDANTS, nil)

    Assets_By_Id[id] = asset
    Ids_By_Asset[asset] = id

    asset.Destroying:Once(function()
        Assets_By_Id[id] = nil
        Ids_By_Asset[asset] = nil
        Replication_Pigeon:Emit(Shared.MSG_REMOVE, id)
        module.OnUnReplication:Fire(asset)
    end)

    asset.Parent = Asset_Folder
    Replication_Pigeon:Emit(Shared.MSG_CLAIM, id)

    resumeWaiting(asset.Name, asset)
    module.OnReplication:Fire(asset)
end

local function onStagedChild(staged: Instance)
    if Processing_Staged[staged] then
        return
    end
    Processing_Staged[staged] = true

    task.spawn(function()
        local id = staged:GetAttribute(Shared.ATTR_ID)
        if typeof(id) ~= "string" then
            Processing_Staged[staged] = nil
            return
        end

        -- Revoked before we even began loading it (backlog from before this
        -- module was ready): abort and tell the server to drop its staged copy.
        if consumeRevoke(id) then
            Processing_Staged[staged] = nil
            Replication_Pigeon:Emit(Shared.MSG_REMOVE, id)
            return
        end

        local complete = true
        local expected = staged:GetAttribute(Shared.ATTR_DESCENDANTS)
        if typeof(expected) == "number" and expected > 0 then
            complete = waitForDescendants(staged, expected)
        end

        Processing_Staged[staged] = nil

        -- Revoke may have arrived while we were streaming descendants.
        if consumeRevoke(id) then
            Replication_Pigeon:Emit(Shared.MSG_REMOVE, id)
            return
        end

        if complete and staged.Parent ~= nil then
            registerAsset(staged, id)
        end
    end)
end

local function bindReceiver(receiver: Instance)
    if Bound_Receiver == receiver then
        return
    end
    Bound_Receiver = receiver

    receiver.ChildAdded:Connect(onStagedChild)
    for _, child in receiver:GetChildren() do
        onStagedChild(child)
    end
end

function module.GetAssetFolder(): Folder
    return Asset_Folder
end

function module.GetAsset(name: string): Instance?
    return Asset_Folder:FindFirstChild(name)
end

function module.GetAssets(): {Instance}
    return Asset_Folder:GetChildren()
end

function module.AwaitAsset(name: string, timeout: number?): Instance?
    local existing = Asset_Folder:FindFirstChild(name)
    if existing then
        return existing
    end

    local thread = coroutine.running()
    local waiting = Waiting_Threads[name]
    if not waiting then
        waiting = {}
        Waiting_Threads[name] = waiting
    end
    table.insert(waiting, thread)

    local timer: thread? = nil
    if timeout then
        timer = task.delay(timeout, function()
            local current = Waiting_Threads[name]
            if current then
                local index = table.find(current, thread)
                if index then
                    table.remove(current, index)
                end
                if #current == 0 then
                    Waiting_Threads[name] = nil
                end
            end
            task.spawn(thread)
        end)
    end

    local asset = coroutine.yield() :: Instance?
    if timer and coroutine.status(timer) == "suspended" then
        task.cancel(timer)
    end
    return asset
end

Replication_Pigeon:On(Shared.MSG_REVOKE, function(id: unknown)
    if typeof(id) ~= "string" then
        return
    end
    local asset = Assets_By_Id[id]
    if asset then
        asset:Destroy()
    else
        -- No local copy yet: it is still streaming/registering (or was staged
        -- before this module loaded). Defer the revoke until it lands.
        markRevoked(id)
    end
end)

do
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    playerGui.ChildAdded:Connect(function(child)
        if child.Name == Shared.RECEIVER_NAME then
            bindReceiver(child)
        end
    end)

    local existing = playerGui:FindFirstChild(Shared.RECEIVER_NAME)
    if existing then
        bindReceiver(existing)
    end
end

return module
