--!strict

--[[
    CodeService
    Codes cadeaux (menu Parametres). RemoteFunction RedeemCode (code) -> (ok, message, cle d'icone).
    - codes : ServerScriptService.Server.Codes (hors de Shared, invisibles pour les clients) ;
    - une fois par joueur (profil DataService, champ codes) ;
    - 5 essais par minute au plus (anti-devinette) ;
    - recompenses : tetines (BaseService), XP (PassService:AddXp, pass et niveau), article (ShopService:Grant, ou
      tetines de remplacement s'il est deja possede).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Codes = require(script.Parent.Parent:WaitForChild("Codes"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local PassService = require(script.Parent:WaitForChild("PassService"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))

local MAX_ATTEMPTS = 5
local WINDOW_SECONDS = 60
local MAX_CODE_LENGTH = 24

local CodeService = {}

local attempts: { [Player]: { number } } = {}

local function formatNumber(value: number): string
    local digits = tostring(math.floor(math.abs(value)))
    local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1 ")))
    return (string.gsub(grouped, "^ ", ""))
end

-- Vrai si le joueur a encore droit a un essai dans la minute (l'essai est compte).
local function allowAttempt(player: Player): boolean
    local now = os.clock()
    local fresh: { number } = {}
    local previous: { number } = attempts[player] or {}
    for _, t in previous do
        if now - t < WINDOW_SECONDS then
            table.insert(fresh, t)
        end
    end
    if #fresh >= MAX_ATTEMPTS then
        attempts[player] = fresh
        return false
    end
    table.insert(fresh, now)
    attempts[player] = fresh
    return true
end

function CodeService:Redeem(player: Player, raw: string): (boolean, string, string)
    local profile = DataService:Get(player)
    if profile == nil then
        return false, "Ton profil charge encore, réessaie.", "bebeDort"
    end
    if not allowAttempt(player) then
        return false, "Trop d'essais : attends une minute.", "bebeDort"
    end
    local code = string.upper((string.gsub(raw, "%s", "")))
    local reward: Codes.Reward? = if #code > 0 and #code <= MAX_CODE_LENGTH then Codes[code] else nil
    if reward == nil then
        return false, "Code invalide", "bebeDort"
    end
    if profile.codes[code] then
        return false, "Déjà utilisé", "bebeDort"
    end
    profile.codes[code] = true

    local parts: { string } = {}
    local icon = "tetine"
    local cash = reward.cash or 0
    if reward.item then
        local item = Catalog.Get(reward.item)
        if item and not ShopService:Owns(player, reward.item) and ShopService:Grant(player, reward.item) then
            table.insert(parts, item.name)
            icon = item.icon
        else
            cash += reward.fallbackCash or 0
        end
    end
    if cash > 0 then
        BaseService:AddCash(player, cash)
        table.insert(parts, 1, "+" .. formatNumber(cash) .. " tétines")
    end
    if reward.xp and reward.xp > 0 then
        PassService:AddXp(player, reward.xp, "code")
        table.insert(parts, "+" .. formatNumber(reward.xp) .. " XP")
        if cash == 0 and reward.item == nil then
            icon = "etoile"
        end
    end
    DataService:Save(player)
    return true, table.concat(parts, " et ") .. " !", icon
end

function CodeService:Init(): () end

function CodeService:Start(): ()
    local remote = Remotes.Get("RedeemCode") :: RemoteFunction
    remote.OnServerInvoke = function(player: Player, code: any)
        if typeof(code) ~= "string" then
            return false, "Code invalide", "bebeDort"
        end
        return CodeService:Redeem(player, code)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        attempts[player] = nil
    end)
end

return CodeService
