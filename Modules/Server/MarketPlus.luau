local MarketplaceService = game:GetService("MarketplaceService")
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local module = {}

export type ProductType = "Gamepass" | "DeveloperProduct"

type ReceiptInfo = {
    PurchaseId:string,
    PlayerId:number,
    ProductId:number,
    CurrencySpent:number,
    CurrencyType:Enum.CurrencyType,
    PlaceIdWherePurchased:number,
}

export type ReceiptPacket = {
    Player:Player?,
    UserId:number,
    ProductId:any,
    PurchaseId:string,
    CurrencySpent:number,
    CurrencyType:Enum.CurrencyType,
    PlaceIdWherePurchased:number,
    Logs:{string},
    Receipt:ReceiptInfo,
}

export type Middleware = (packet:ReceiptPacket) -> ReceiptPacket?
export type ProductCallback = (packet:ReceiptPacket) -> boolean?

export type MarketObject = {
    Analytics:boolean,
    PromptPurchaseAsync:(self:MarketObject, Targets:{Player}, Type:ProductType, ID:any) -> (),
    RegisterProduct:(self:MarketObject, Type:ProductType, ID:any, Callback:ProductCallback) -> (),
    UseMiddleware:(self:MarketObject, Middleware:Middleware) -> (),
    UseIncoming:(self:MarketObject) -> (),
    GetPurchaseCount:(self:MarketObject, Player:Player, ID:any?) -> number,
    OwnsGamepass:(self:MarketObject, Player:Player, ID:any) -> boolean
}

type MarketInfo = {
    Gamepasses:{[any]:boolean},
    Purchases:{[any]:number},
    Spent:number,
}

type Product = {
    Type:ProductType,
    Callback:ProductCallback,
}

type MarketPrivate = MarketObject & {
    Signals:{RBXScriptConnection},
    RegisterPlayer:(self:MarketPrivate, Player:Player) -> (),
    LogPurchase:(self:MarketPrivate, packet:ReceiptPacket) -> (),
    RecordPurchase:(self:MarketPrivate, packet:ReceiptPacket) -> (),
    LogSessionSpend:(self:MarketPrivate, Player:Player) -> (),
    MarketData:{[Player]:MarketInfo},
    Products:{[any]:Product},
    Middleware:Middleware?,
}

local MarketClass = {}
MarketClass.__index = MarketClass
MarketClass.ID_Sinks = {}::{[any]:MarketPrivate}
MarketClass.Listening = false

function MarketClass.RegisterPlayer(self:MarketPrivate, Player:Player)
    if self.MarketData[Player] then return end

    self.MarketData[Player] = {
        Gamepasses = {},
        Purchases = {},
        Spent = 0,
    }
end

function MarketClass.RegisterProduct(self:MarketPrivate, Type:ProductType, ID:any, Callback:ProductCallback)
    self.Products[ID] = {
        Type = Type,
        Callback = Callback,
    }
    if Type == "DeveloperProduct" then
        MarketClass.ID_Sinks[ID] = self
    end
end

function MarketClass.UseMiddleware(self:MarketPrivate, Middleware:Middleware)
    self.Middleware = Middleware
end

function MarketClass.LogPurchase(self:MarketPrivate, packet:ReceiptPacket)
    if not self.Analytics or not packet.Player then return end
    local ok, err = pcall(function()
        AnalyticsService:LogEconomyEvent(
            packet.Player,
            Enum.AnalyticsEconomyFlowType.Sink,
            packet.CurrencyType.Name,
            packet.CurrencySpent,
            packet.CurrencySpent,
            Enum.AnalyticsEconomyTransactionType.IAP.Name,
            tostring(packet.ProductId)
        )
    end)
    if not ok then
        warn("MarketPlus: analytics failed -", err)
    end
end

function MarketClass.RecordPurchase(self:MarketPrivate, packet:ReceiptPacket)
    local Player = packet.Player
    if not Player then return end
    local data = self.MarketData[Player]
    if not data then return end
    data.Purchases[packet.ProductId] = (data.Purchases[packet.ProductId] or 0) + 1
    data.Spent += packet.CurrencySpent
end

function MarketClass.GetPurchaseCount(self:MarketPrivate, Player:Player, ID:any?):number
    local data = self.MarketData[Player]
    if not data then return 0 end
    if ID == nil then
        local total = 0
        for _, count in pairs(data.Purchases) do
            total += count
        end
        return total
    end
    return data.Purchases[ID] or 0
end

function MarketClass.OwnsGamepass(self:MarketPrivate, Player:Player, ID:any):boolean
    local data = self.MarketData[Player]
    if data and data.Gamepasses[ID] == true then
        return true
    end
    local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, Player.UserId, ID)
    if ok and owns == true then
        if data then
            data.Gamepasses[ID] = true
        end
        return true
    end
    return false
end

function MarketClass.LogSessionSpend(self:MarketPrivate, Player:Player)
    if not self.Analytics then return end
    local data = self.MarketData[Player]
    if not data or data.Spent <= 0 then return end
    local ok, err = pcall(function()
        AnalyticsService:LogCustomEvent(Player, "SessionSpend", data.Spent)
    end)
    if not ok then
        warn("MarketPlus: session spend analytics failed -", err)
    end
end

local function HandleReceipt(receipt:ReceiptInfo):Enum.ProductPurchaseDecision
    local owner = MarketClass.ID_Sinks[receipt.ProductId]
    if not owner then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local packet:ReceiptPacket = {
        Player = Players:GetPlayerByUserId(receipt.PlayerId),
        UserId = receipt.PlayerId,
        ProductId = receipt.ProductId,
        PurchaseId = receipt.PurchaseId,
        CurrencySpent = receipt.CurrencySpent,
        CurrencyType = receipt.CurrencyType,
        PlaceIdWherePurchased = receipt.PlaceIdWherePurchased,
        Logs = {},
        Receipt = receipt,
    }

    if owner.Middleware then
        local ok, result = pcall(owner.Middleware, packet)
        if not ok then
            warn("MarketPlus: middleware errored -", result)
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end
        if type(result) == "table" then
            packet = result
        end
    end

    for _, entry in ipairs(packet.Logs) do
        print(string.format("[MarketPlus][%s] %s", tostring(packet.ProductId), entry))
    end

    local finalOwner = MarketClass.ID_Sinks[packet.ProductId]
    local product = finalOwner and finalOwner.Products[packet.ProductId]
    if not finalOwner or not product then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local ok, granted = pcall(product.Callback, packet)
    if not ok then
        warn("MarketPlus: product callback errored -", granted)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    if granted == false then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    finalOwner:RecordPurchase(packet)
    finalOwner:LogPurchase(packet)
    return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MarketClass.UseIncoming(self:MarketPrivate)
    if MarketClass.Listening then return end
    MarketClass.Listening = true
    MarketplaceService.ProcessReceipt = HandleReceipt
end

function MarketClass.PromptPurchaseAsync(self:MarketPrivate, Targets:{Player}, Type:ProductType, ID:any)
    for _, Player in ipairs(Targets) do
        task.defer(function()
            if Type == "DeveloperProduct" then
                MarketplaceService:PromptProductPurchase(Player, ID)
            elseif not self:OwnsGamepass(Player, ID) then
                MarketplaceService:PromptGamePassPurchase(Player, ID)
            end
        end)
    end
end

function module.new(UseAnalytics:boolean):MarketObject
    local self:MarketPrivate = setmetatable({
        Analytics = UseAnalytics,
        MarketData = {},
        Products = {},
        Signals = {},
    }, MarketClass)

    table.insert(self.Signals, Players.PlayerRemoving:Connect(function(Player)
        self:LogSessionSpend(Player)
        self.MarketData[Player] = nil
    end))

    table.insert(self.Signals, MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(Player, GamepassId, WasPurchased)
        if not WasPurchased then return end
        local data = self.MarketData[Player]
        if data then
            data.Gamepasses[GamepassId] = true
        end
    end))

    for _, item in ipairs(Players:GetPlayers()) do
        self:RegisterPlayer(item)
    end

    table.insert(self.Signals, Players.PlayerAdded:Connect(function(Player)
        self:RegisterPlayer(Player)
    end))

    return self
end

return module
