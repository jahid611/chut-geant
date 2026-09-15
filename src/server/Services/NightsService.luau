--!strict

--[[
    NightsService
    « Nuits » : la renaissance. Avec assez de tetines (Progression.NIGHT_BASE_COST x (nuits + 1)), le joueur passe a
    la nuit suivante :
    - il perd ses tetines, ses jouets et ses coffres (BaseService:ResetBase : 1 coffre vide, plus de coffre dore) ;
    - il garde pouvoirs, ameliorations, cosmetiques, collection et pass ;
    - il gagne +25 % de revenu permanent par nuit (BaseService:AddIncomeMultiplier) et un titre « Nuit N » au-dessus
      de la tete.
    Remote Rebirth (RemoteFunction) -> (ok, message). Attributs du joueur : Nights, NightCost, Notif_Nuits (assez de
    tetines pour la nuit suivante).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CarryService = require(script.Parent:WaitForChild("CarryService"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local TITLE_NAME = "TitreNuit"

local NightsService = {}

function NightsService:GetNights(player: Player): number
    local profile = DataService:Get(player)
    return if profile then profile.nights else 0
end

function NightsService:GetCost(player: Player): number
    return Progression.NIGHT_BASE_COST * (NightsService:GetNights(player) + 1)
end

local function refresh(player: Player): ()
    local cost = NightsService:GetCost(player)
    player:SetAttribute("Nights", NightsService:GetNights(player))
    player:SetAttribute("NightCost", cost)
    player:SetAttribute("Notif_Nuits", BaseService:GetCash(player) >= cost)
end

-- Titre « Nuit N » au-dessus de la tete (rien a la nuit 0).
local function setTitle(player: Player): ()
    local character = player.Character
    local head = if character then character:FindFirstChild("Head") else nil
    if head == nil or not head:IsA("BasePart") then
        return
    end
    local existing = head:FindFirstChild(TITLE_NAME)
    if existing then
        existing:Destroy()
    end
    local nights = NightsService:GetNights(player)
    if nights <= 0 then
        return
    end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = TITLE_NAME
    billboard.Size = UDim2.fromOffset(160, 40)
    billboard.StudsOffset = Vector3.new(0, 2.6, 0)
    billboard.MaxDistance = 140
    billboard.LightInfluence = 0
    billboard.Adornee = head
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.FredokaOne
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(200, 180, 255)
    label.Text = string.format("Nuit %d", nights)
    label.Parent = billboard
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(12, 16, 40)
    stroke.Parent = label
    billboard.Parent = head
end

function NightsService:Rebirth(player: Player): (boolean, string)
    local profile = DataService:Get(player)
    if profile == nil then
        return false, "Ton profil charge encore, réessaie."
    end
    local cost = NightsService:GetCost(player)
    if BaseService:GetCash(player) < cost then
        return false, string.format("Il te faut %d tétines pour passer à la nuit suivante.", cost)
    end
    CarryService:Drop(player, true)
    if not BaseService:ResetBase(player) then
        return false, "Ta base n'est pas prête, réessaie."
    end
    profile.nights += 1
    DataService:AddStat(player, "nights", 1)
    -- ShopService publie ces niveaux a l'arrivee : on les remet a jour apres la remise a zero des coffres.
    player:SetAttribute("Owned_Chest", nil)
    player:SetAttribute("Owned_GoldChest", nil)
    BaseService:RefreshIncome(player)
    refresh(player)
    setTitle(player)
    DataService:Save(player)
    return true,
        string.format(
            "Bienvenue dans la nuit %d ! +%d %% de tétines pour toujours.",
            profile.nights,
            math.floor(profile.nights * Progression.NIGHT_INCOME_BONUS * 100 + 0.5)
        )
end

function NightsService:Init(): () end

function NightsService:Start(): ()
    BaseService:AddIncomeMultiplier(function(player: Player): number
        return 1 + NightsService:GetNights(player) * Progression.NIGHT_INCOME_BONUS
    end)

    local remote = Remotes.Get("Rebirth") :: RemoteFunction
    remote.OnServerInvoke = function(player: Player)
        return NightsService:Rebirth(player)
    end

    local function onPlayer(player: Player): ()
        player.CharacterAdded:Connect(function(character: Model)
            character:WaitForChild("Head", 5)
            setTitle(player)
        end)
        player:GetAttributeChangedSignal("Cash"):Connect(function()
            refresh(player)
        end)
        if DataService:WaitForProfile(player) then
            refresh(player)
            BaseService:RefreshIncome(player)
            setTitle(player)
        end
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end
end

return NightsService
