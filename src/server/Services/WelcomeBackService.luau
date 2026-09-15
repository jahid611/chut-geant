--!strict

--[[
    WelcomeBackService
    Recompense de retour (idee 8 du carnet docs/IDEES.md) : un joueur qui revient apres plus de 24 h d'absence
    trouve un coffre cadeau a ouvrir.
    - 24 h a 72 h : 3 000 tetines + 150 XP ;
    - plus de 72 h : 15 000 tetines + 500 XP + un cosmetique qu'il n'a pas encore (sinon 5 000 tetines de plus).

    Date de derniere presence dans profile.daily.lastSeen (os.time, mise a jour a l'arrivee puis chaque minute) ; une
    recompense non ouverte reste dans profile.daily.welcomePending jusqu'a l'ouverture, meme si le joueur repart.
    Attributs publies : WelcomeBackTier (1 ou 2), WelcomeBackHours (heures d'absence).
    Remote WelcomeBack (RemoteFunction) : ("claim") -> (ok, recompense { cash, xp, cosmetic? } ou message).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local PassService = require(script.Parent:WaitForChild("PassService"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))

local HOUR = 3600
local SHORT_ABSENCE = 24 * HOUR
local LONG_ABSENCE = 72 * HOUR
local REWARDS: { { cash: number, xp: number } } = {
    { cash = 3000, xp = 150 },
    { cash = 15000, xp = 500 },
}
-- Cosmetique offert apres une longue absence : le premier que le joueur ne possede pas.
local GIFT_COSMETICS = { "TrailStars", "DanceJoy", "TrailHearts", "DanceRobot" }
local NO_COSMETIC_CASH = 5000
local TOUCH_SECONDS = 60

local WelcomeBackService = {}

local function dailyOf(player: Player): { [string]: any }?
    local profile = DataService:Get(player)
    return if profile then profile.daily :: any else nil
end

local function publish(player: Player, tier: number?, hours: number?): ()
    player:SetAttribute("WelcomeBackTier", tier)
    player:SetAttribute("WelcomeBackHours", hours)
end

local function onPlayer(player: Player): ()
    local profile = DataService:WaitForProfile(player)
    if profile == nil or player.Parent == nil then
        return
    end
    local daily = profile.daily :: any
    local now = os.time()
    local tier: number? = if typeof(daily.welcomePending) == "number" then daily.welcomePending else nil
    local hours: number? = if typeof(daily.welcomeHours) == "number" then daily.welcomeHours else nil
    local lastSeen = daily.lastSeen
    if tier == nil and typeof(lastSeen) == "number" then
        local away = now - lastSeen
        if away >= LONG_ABSENCE then
            tier = 2
        elseif away >= SHORT_ABSENCE then
            tier = 1
        end
        if tier then
            hours = math.floor(away / HOUR)
            daily.welcomePending = tier
            daily.welcomeHours = hours
        end
    end
    daily.lastSeen = now
    if tier then
        publish(player, tier, hours)
    end
end

function WelcomeBackService:Claim(player: Player): (boolean, any)
    local daily = dailyOf(player)
    if daily == nil then
        return false, "Ton profil charge encore, réessaie."
    end
    local tier = daily.welcomePending
    if typeof(tier) ~= "number" or REWARDS[tier] == nil then
        return false, "Rien à ouvrir."
    end
    daily.welcomePending = nil
    daily.welcomeHours = nil
    publish(player, nil, nil)

    local reward = REWARDS[tier]
    local cash = reward.cash
    local cosmetic: string? = nil
    if tier == 2 then
        for _, id in GIFT_COSMETICS do
            if not ShopService:Owns(player, id) and ShopService:Grant(player, id) then
                cosmetic = id
                break
            end
        end
        if cosmetic == nil then
            cash += NO_COSMETIC_CASH
        end
    end
    BaseService:AddCash(player, cash)
    PassService:AddXp(player, reward.xp, "retour")
    DataService:Save(player)
    return true, { cash = cash, xp = reward.xp, cosmetic = cosmetic }
end

function WelcomeBackService:Init(): () end

function WelcomeBackService:Start(): ()
    local remote = Remotes.Get("WelcomeBack") :: RemoteFunction
    remote.OnServerInvoke = function(player: Player, action: any)
        if action ~= "claim" then
            return false, "Requête invalide."
        end
        return WelcomeBackService:Claim(player)
    end

    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end

    -- Derniere presence tenue a jour pendant la partie (le profil est retire au depart du joueur).
    task.spawn(function()
        while true do
            task.wait(TOUCH_SECONDS)
            local now = os.time()
            for _, player in Players:GetPlayers() do
                local daily = dailyOf(player)
                if daily then
                    daily.lastSeen = now
                end
            end
        end
    end)
end

return WelcomeBackService
