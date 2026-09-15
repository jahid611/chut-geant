--!strict

--[[
    MoonService
    Evenement « Pleine lune » : toutes les Progression.MOON_INTERVAL_SECONDS (premiere apres MOON_FIRST_DELAY),
    pendant MOON_DURATION_SECONDS, revenu x2 pour tout le serveur et plus de jouets rares
    (ToySpawnService:SetRarityBoost). Les clients recoivent MoonEvent("start" | "end", endsAt) ; l'attribut
    MoonUntil du workspace (temps serveur) sert aux joueurs qui arrivent pendant l'evenement.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local ToySpawnService = require(script.Parent:WaitForChild("ToySpawnService"))

local MoonService = {}

local active = false
local token = 0

function MoonService:IsActive(): boolean
    return active
end

local function refreshAll(): ()
    for _, player in Players:GetPlayers() do
        BaseService:RefreshIncome(player)
    end
end

function MoonService:Stop(): ()
    if not active then
        return
    end
    active = false
    token += 1
    workspace:SetAttribute("MoonUntil", nil)
    ToySpawnService:SetRarityBoost(1)
    refreshAll()
    local remote = Remotes.Get("MoonEvent") :: RemoteEvent
    remote:FireAllClients("end", 0)
end

-- Lance une pleine lune (seconds : duree, par defaut Progression.MOON_DURATION_SECONDS ; utile aux tests).
function MoonService:Trigger(seconds: number?): ()
    if active then
        return
    end
    local duration = seconds or Progression.MOON_DURATION_SECONDS
    active = true
    token += 1
    local current = token
    local endsAt = workspace:GetServerTimeNow() + duration
    workspace:SetAttribute("MoonUntil", endsAt)
    ToySpawnService:SetRarityBoost(Progression.MOON_RARITY_BOOST)
    refreshAll()
    local remote = Remotes.Get("MoonEvent") :: RemoteEvent
    remote:FireAllClients("start", endsAt)
    task.delay(duration, function()
        if token == current then
            MoonService:Stop()
        end
    end)
end

function MoonService:Init(): () end

function MoonService:Start(): ()
    BaseService:AddIncomeMultiplier(function(_: Player): number
        return if active then Progression.MOON_INCOME_MULTIPLIER else 1
    end)
    task.spawn(function()
        task.wait(Progression.MOON_FIRST_DELAY)
        while true do
            MoonService:Trigger()
            task.wait(Progression.MOON_INTERVAL_SECONDS)
        end
    end)
end

return MoonService
