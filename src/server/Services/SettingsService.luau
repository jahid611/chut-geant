--!strict

--[[
    SettingsService
    Reglages du joueur choisis dans le menu Parametres, sauvegardes dans son profil (DataService, champ settings) et
    publies en attributs du joueur a la connexion et a chaque changement :
    - musicVolume (0 a 1)     -> ReglageMusique
    - sfxVolume (0 a 1)       -> ReglageEffets
    - showNames (booleen)     -> ReglageNoms (noms, niveaux et titres au-dessus des tetes)
    - reducedEffects (booleen)-> EffetsReduits (moins de particules, lu par les controleurs)
    Remote Settings (key, value), valeurs verifiees et bornees.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local DEFAULTS: { [string]: number | boolean } = {
    musicVolume = 1,
    sfxVolume = 1,
    showNames = true,
    reducedEffects = false,
}

local ATTRIBUTES: { [string]: string } = {
    musicVolume = "ReglageMusique",
    sfxVolume = "ReglageEffets",
    showNames = "ReglageNoms",
    reducedEffects = "EffetsReduits",
}

local SettingsService = {}

-- Valeur acceptee pour ce reglage (type du defaut, nombres bornes a 0..1), sinon nil.
local function sanitize(key: string, value: any): (number | boolean)?
    local default = DEFAULTS[key]
    if default == nil or typeof(value) ~= typeof(default) then
        return nil
    end
    if typeof(value) == "number" then
        if value ~= value then
            return nil
        end
        return math.clamp(value, 0, 1)
    end
    return value
end

local function onPlayer(player: Player): ()
    local profile = DataService:WaitForProfile(player)
    if profile == nil or player.Parent == nil then
        return
    end
    for key, default in DEFAULTS do
        local value = sanitize(key, profile.settings[key])
        player:SetAttribute(ATTRIBUTES[key], if value ~= nil then value else default)
    end
end

function SettingsService:Init(): () end

function SettingsService:Start(): ()
    local remote = Remotes.Get("Settings") :: RemoteEvent
    remote.OnServerEvent:Connect(function(player: Player, key: any, value: any)
        if typeof(key) ~= "string" then
            return
        end
        local clean = sanitize(key, value)
        local profile = DataService:Get(player)
        if clean == nil or profile == nil then
            return
        end
        profile.settings[key] = clean
        player:SetAttribute(ATTRIBUTES[key], clean)
    end)
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end
end

return SettingsService
