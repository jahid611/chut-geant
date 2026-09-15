--!strict

--[[
    RecordsService
    Records de la nuit (idee 18 du carnet docs/IDEES.md), propres a ce serveur et remis a zero a son redemarrage :
    - plus gros vol : le jouet depose au plus gros revenu par seconde (joueur, jouet, revenu) ;
    - plus longue nuit calme : la plus longue periode sans reveil du bebe (secondes, mise a jour en direct) ;
    - plus de propulsions : le joueur le plus souvent attrape ;
    - plus de jouets deposes : le joueur qui a le plus rempli son coffre.
    Publie en attributs de workspace (Record*) : RecordsController les affiche sur le tableau du mur du fond.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Toys = require(Shared:WaitForChild("Toys"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local GiantService = require(script.Parent:WaitForChild("GiantService"))

local CALM_PUBLISH_SECONDS = 1

local RecordsService = {}

local catches: { [Player]: number } = {}
local deposits: { [Player]: number } = {}
local bestTheft = 0
local bestCalm = 0
local calmSince = os.clock()
local wasSleeping = true

local function nameOf(player: Player): string
    return player.DisplayName
end

-- Meilleur compteur d'une table joueur -> nombre, publie sous `prefix` (Nom et valeur).
local function publishBest(counts: { [Player]: number }, prefix: string): ()
    local bestPlayer: Player? = nil
    local best = 0
    for player, count in counts do
        if count > best then
            best = count
            bestPlayer = player
        end
    end
    workspace:SetAttribute(prefix .. "Nom", if bestPlayer then nameOf(bestPlayer) else nil)
    workspace:SetAttribute(prefix, if bestPlayer then best else nil)
end

local function onDeposited(player: Player, toyId: string, mutation: string?): ()
    deposits[player] = (deposits[player] or 0) + 1
    publishBest(deposits, "RecordVols")
    local def = Toys.Get(toyId)
    local income = Toys.Income(toyId, mutation)
    if def and income > bestTheft then
        bestTheft = income
        workspace:SetAttribute("RecordVolNom", nameOf(player))
        workspace:SetAttribute("RecordVolJouet", def.displayName)
        workspace:SetAttribute("RecordVolRevenu", income)
    end
end

local function onCaught(player: Player, _reason: string): ()
    catches[player] = (catches[player] or 0) + 1
    publishBest(catches, "RecordPropulsions")
end

function RecordsService:Init(): () end

function RecordsService:Start(): ()
    BaseService.ToyDeposited:Connect(onDeposited)
    GiantService.Caught:Connect(onCaught)
    -- Un joueur qui part garde son record affiche (attributs inchanges) tant qu'un autre ne le bat pas.
    Players.PlayerRemoving:Connect(function(player: Player)
        catches[player] = nil
        deposits[player] = nil
    end)

    local elapsed = 0
    RunService.Heartbeat:Connect(function(dt: number)
        elapsed += dt
        if elapsed < CALM_PUBLISH_SECONDS then
            return
        end
        elapsed = 0
        local sleeping = GiantService:GetState() == "Sleeping"
        local now = os.clock()
        if sleeping and not wasSleeping then
            calmSince = now
        end
        wasSleeping = sleeping
        if sleeping then
            local calm = math.floor(now - calmSince)
            if calm > bestCalm then
                bestCalm = calm
                workspace:SetAttribute("RecordCalme", bestCalm)
            end
        end
    end)
end

return RecordsService
