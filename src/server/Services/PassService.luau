--!strict

--[[
    PassService
    Pass de saison (Shared/Retention) : 30 paliers, XP gagnee en jouant.

    XP : quetes (QuestService), roue et connexion (DailyService), chaque jouet vole (stat stolen), chaque minute
    jouee (stat playSeconds). Piste gratuite : tetines, et un cosmetique aux paliers 10, 20 et 30 (rembourse en
    tetines s'il est deja possede). Piste premium : affichee mais verrouillee (« Bientôt », pas de vente Robux).

    Profil : pass = { season, xp, claimed = { ["10"] = true } } ; une nouvelle saison repart a zero.
    Client : attribut Pass_State (JSON : season, xp, claimed) et remote PassState ; pastille Notif_Pass quand un
    palier atteint n'est pas recupere. ClaimPass (tier, premium) -> (ok, message).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Retention = require(Shared:WaitForChild("Retention"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))

type PassData = { season: number, xp: number, claimed: { [string]: boolean } }

local PassService = {}

-- (player: Player, amount: number, source: string?) chaque gain d'XP, meme pass complet : LevelService en fait
-- monter le niveau du joueur. Toute l'XP du jeu passe par AddXp.
local xpGained = Instance.new("BindableEvent")
PassService.XpGained = xpGained.Event

local function formatNumber(value: number): string
    local digits = tostring(math.floor(math.abs(value)))
    local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1 ")))
    return (string.gsub(grouped, "^ ", ""))
end

local function passOf(player: Player): PassData?
    local profile = DataService:Get(player)
    if profile == nil then
        return nil
    end
    local raw = profile.pass :: any
    if raw.season ~= Retention.PASS_SEASON or typeof(raw.xp) ~= "number" or typeof(raw.claimed) ~= "table" then
        profile.pass = { season = Retention.PASS_SEASON, xp = 0, claimed = {} }
    end
    return profile.pass :: any
end

-- Paliers atteints pour une quantite d'XP.
function PassService:TierOf(xp: number): number
    return math.min(math.floor(xp / Retention.PASS_XP_PER_TIER), Retention.PASS_TIERS)
end

local function push(player: Player): ()
    local pass = passOf(player)
    if pass == nil then
        return
    end
    local claimed: { number } = {}
    for key in pass.claimed do
        local tier = tonumber(key)
        if tier then
            table.insert(claimed, tier)
        end
    end
    local tier = PassService:TierOf(pass.xp)
    local pending = false
    for t = 1, tier do
        if not pass.claimed[tostring(t)] then
            pending = true
            break
        end
    end
    local state = { season = pass.season, xp = pass.xp, claimed = claimed }
    player:SetAttribute("Pass_State", HttpService:JSONEncode(state))
    player:SetAttribute("Notif_Pass", pending)
    local remote = Remotes.Get("PassState") :: RemoteEvent
    remote:FireClient(player, state)
end

function PassService:AddXp(player: Player, amount: number, source: string?): ()
    local pass = passOf(player)
    if pass == nil or amount <= 0 then
        return
    end
    pass.xp = math.min(pass.xp + math.floor(amount), Retention.PASS_TIERS * Retention.PASS_XP_PER_TIER)
    push(player)
    xpGained:Fire(player, math.floor(amount), source)
end

function PassService:Claim(player: Player, tier: number, premium: boolean): (boolean, string)
    if premium then
        return false, "Le pass premium arrive bientôt !"
    end
    local pass = passOf(player)
    if pass == nil then
        return false, "Ton profil charge encore, réessaie."
    end
    if tier < 1 or tier > Retention.PASS_TIERS or tier ~= math.floor(tier) then
        return false, "Palier inconnu."
    end
    if tier > PassService:TierOf(pass.xp) then
        return false, string.format("Atteins d'abord le palier %d.", tier)
    end
    local key = tostring(tier)
    if pass.claimed[key] then
        return false, "Déjà récupéré."
    end
    pass.claimed[key] = true

    local message: string
    local cosmeticId = Retention.PASS_COSMETICS[tier]
    if cosmeticId then
        local item = Catalog.Get(cosmeticId)
        if ShopService:Grant(player, cosmeticId) then
            message = string.format("Palier %d : %s !", tier, if item then item.name else cosmeticId)
        else
            BaseService:AddCash(player, Retention.PASS_COSMETIC_REFUND)
            message = string.format(
                "Palier %d : déjà possédé, +%s tétines !",
                tier,
                formatNumber(Retention.PASS_COSMETIC_REFUND)
            )
        end
    else
        local cash = Retention.PassFreeCash(tier)
        BaseService:AddCash(player, cash)
        message = string.format("Palier %d : +%s tétines !", tier, formatNumber(cash))
    end
    push(player)
    return true, message
end

function PassService:Init(): () end

function PassService:Start(): ()
    local claim = Remotes.Get("ClaimPass") :: RemoteFunction
    claim.OnServerInvoke = function(player: Player, tier: any, premium: any)
        if typeof(tier) ~= "number" then
            return false, "Requête invalide."
        end
        return PassService:Claim(player, tier, premium == true)
    end

    DataService.StatChanged:Connect(function(player: Player, key: string, _total: number, added: number)
        if key == "stolen" then
            PassService:AddXp(player, added * Retention.PASS_XP_PER_TOY)
        elseif key == "playSeconds" then
            PassService:AddXp(player, added / 60 * Retention.PASS_XP_PER_MINUTE)
        end
    end)

    local function onPlayer(player: Player): ()
        if DataService:WaitForProfile(player) then
            push(player)
        end
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end
end

return PassService
