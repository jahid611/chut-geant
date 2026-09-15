--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local RobuxProducts = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RobuxProducts"))

local RobuxShopService = {}
local busy: { [Player]: boolean } = {}
-- Un crédit en mémoire dont la sauvegarde a échoué reste marqué : ne jamais le recréditer ni l'évincer.
local pending: { [Player]: number } = {}
local DEFER = Enum.ProductPurchaseDecision.NotProcessedYet
local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted

local function saveAndConfirm(player: Player): boolean
    if not DataService:Save(player) then
        warn("[RobuxShopService] Sauvegarde indisponible, reçu laissé en attente.")
        return false
    end
    local amount = pending[player]
    pending[player] = nil
    if amount and player.Parent == Players then
        local previous = player:GetAttribute("RobuxTetinesCreditees")
        player:SetAttribute("RobuxTetinesCreditees", (if typeof(previous) == "number" then previous else 0) + amount)
        print("[RobuxShopService] Pack crédité et sauvegardé.")
    end
    return true
end

local function grant(player: Player, purchaseId: string, pack: RobuxProducts.Pack): Enum.ProductPurchaseDecision
    -- Sauvegarder un éventuel reçu précédent avant de faire avancer la liste bornée.
    if pending[player] and not saveAndConfirm(player) then
        return DEFER
    end
    local profile = DataService:Get(player)
    if player.Parent ~= Players or profile == nil or not DataService:CanSave(player) then
        return DEFER
    end
    if table.find(profile.robuxReceipts, purchaseId) then
        -- Le marqueur peut venir d'un essai interrompu : exiger encore une sauvegarde réussie.
        return if saveAndConfirm(player) then GRANTED else DEFER
    end
    -- Aucun yield entre le marqueur, le crédit et la statistique.
    table.insert(profile.robuxReceipts, purchaseId)
    while #profile.robuxReceipts > 100 do
        table.remove(profile.robuxReceipts, 1)
    end
    BaseService:AddCash(player, pack.cash)
    DataService:AddStat(player, "robuxPurchases", 1)
    pending[player] = pack.cash
    return if saveAndConfirm(player) then GRANTED else DEFER
end

function RobuxShopService:Init(): ()
    -- Seul gestionnaire du jeu ; aucun remote et aucun événement client ne verse de monnaie.
    MarketplaceService.ProcessReceipt = function(receipt): Enum.ProductPurchaseDecision
        local pack = RobuxProducts.ByProductId(receipt.ProductId)
        if pack == nil then
            warn("[RobuxShopService] Produit inconnu, reçu laissé en attente.")
            return DEFER
        end
        local player = Players:GetPlayerByUserId(receipt.PlayerId)
        if player == nil or busy[player] or not DataService:CanSave(player) then
            return DEFER
        end
        -- BaseService initialise Cash après le chargement : sinon AddCash partirait de zéro.
        if typeof(player:GetAttribute("Cash")) ~= "number" then
            return DEFER
        end
        if typeof(receipt.PurchaseId) ~= "string" or receipt.PurchaseId == "" then
            return DEFER
        end
        busy[player] = true
        local ok, decision = pcall(grant, player, receipt.PurchaseId, pack)
        busy[player] = nil
        if not ok then
            warn("[RobuxShopService] Traitement interrompu, reçu laissé en attente.")
            return DEFER
        end
        return decision
    end
end

function RobuxShopService:Start(): ()
    Players.PlayerRemoving:Connect(function(player: Player)
        busy[player] = nil
        pending[player] = nil
    end)
end

return RobuxShopService
