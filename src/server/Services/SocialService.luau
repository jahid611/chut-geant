--!strict

--[[
    SocialService
    Bonus de revenu pour jouer ensemble : +10 % par ami present sur le serveur (Progression.FRIEND_MAX au plus) et
    +10 % pour les membres du groupe Roblox du jeu (Progression.GROUP_ID, 0 = desactive).
    Recalcule a chaque arrivee et depart (les appels Roblox peuvent attendre : jamais dans le calcul du revenu).
    Attributs du joueur : FriendsHere, InGroup, SocialBonus (fraction) ; affiches dans le menu Classement.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))

local SocialService = {}

local bonusOf: { [Player]: number } = {}
local inGroup: { [Player]: boolean } = {}

function SocialService:GetBonus(player: Player): number
    return bonusOf[player] or 0
end

local function recompute(player: Player): ()
    if player.Parent == nil then
        return
    end
    local friends = 0
    for _, other in Players:GetPlayers() do
        if other ~= player then
            local ok, result = pcall(function()
                return player:IsFriendsWithAsync(other.UserId)
            end)
            if ok and result == true then
                friends += 1
            end
        end
    end
    friends = math.min(friends, Progression.FRIEND_MAX)
    local member = inGroup[player] == true
    local bonus = friends * Progression.FRIEND_BONUS + (if member then Progression.GROUP_BONUS else 0)
    bonusOf[player] = bonus
    player:SetAttribute("FriendsHere", friends)
    player:SetAttribute("InGroup", member)
    player:SetAttribute("SocialBonus", bonus)
    BaseService:RefreshIncome(player)
end

local function recomputeAll(): ()
    for _, player in Players:GetPlayers() do
        task.spawn(recompute, player)
    end
end

function SocialService:Init(): () end

function SocialService:Start(): ()
    BaseService:AddIncomeMultiplier(function(player: Player): number
        return 1 + SocialService:GetBonus(player)
    end)

    local function onPlayer(player: Player): ()
        if Progression.GROUP_ID ~= 0 then
            local ok, result = pcall(function()
                return player:IsInGroupAsync(Progression.GROUP_ID)
            end)
            inGroup[player] = ok and result == true
        end
        recomputeAll()
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        bonusOf[player] = nil
        inGroup[player] = nil
        task.defer(recomputeAll)
    end)
end

return SocialService
