--!strict

--[[
    FeedService
    Fil d'actualite du serveur (idee du carnet docs/IDEES.md, nuit du 15-16/09) : de courts messages envoyes a tous
    pour creer de l'emulation. Le client (FeedController) les empile en haut a droite.

    Messages :
    - jouet Rare ou mieux depose (BaseService.ToyDeposited) : « Léa a volé une Console dorée ! » ;
    - premiere decouverte d'un jouet Epique ou Legendaire (ToyCollectionService.Discovered, qui remplace alors le
      message de depot) : « Sam a découvert la Baguette de fée ! » ;
    - vol reussi dans la base d'un autre (stat stolenFromPlayers) : « Tom a volé un jouet dans la base de Léa ! » ;
      jouet vole rendu (le surlignage du voleur disparait sans vol reussi) : « Léa a récupéré son jouet ! ».
      StealService n'expose pas d'evenement : on suit les stats robbed / stolenFromPlayers (DataService.StatChanged)
      et le surlignage « SurlignageVoleur » pose sur le personnage du voleur ;
    - niveau multiple de 5 (attribut Level) ;
    - debut de pleine lune (attribut MoonUntil du workspace) ;
    - saut de trampoline dans le berceau (TrampolineService.Bounced).
    Anti-spam : un message par joueur toutes les PLAYER_COOLDOWN secondes, et un meme texte pas plus d'une fois dans
    ce delai (le client regroupe aussi les messages identiques).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local ToyCollectionService = require(script.Parent:WaitForChild("ToyCollectionService"))
local TrampolineService = require(script.Parent:WaitForChild("TrampolineService"))

local PLAYER_COOLDOWN = 8
-- Un depot et la decouverte qu'il declenche arrivent ensemble : on attend un instant pour n'en garder qu'un.
local MERGE_SECONDS = 0.3
local THIEF_HIGHLIGHT = "SurlignageVoleur"

local RARITY_COLORS: { [string]: Color3 } = {
    Rare = Color3.fromRGB(90, 165, 255),
    Epic = Color3.fromRGB(168, 104, 255),
    Legendary = Color3.fromRGB(245, 180, 40),
}
local MUTATION_COLORS: { [string]: Color3 } = {
    Gold = Color3.fromRGB(255, 200, 40),
    Rainbow = Color3.fromRGB(255, 120, 220),
    Cosmic = Color3.fromRGB(150, 120, 255),
}
local SHOWN_RARITIES = { Rare = true, Epic = true, Legendary = true }
local DISCOVERY_RARITIES = { Epic = true, Legendary = true }

export type Message = {
    icon: string,
    fallback: string,
    before: string,
    accent: string,
    after: string,
    color: Color3?,
}

type Deposit = { toyId: string, mutation: string?, at: number, discovered: boolean }

local FeedService = {}

local lastByPlayer: { [Player]: number } = {}
local lastByText: { [string]: number } = {}
local lastDeposit: { [Player]: Deposit } = {}
local lastRobbed: { victim: Player, at: number }? = nil
local stealVictim: { [Player]: Player } = {}
local stealStart: { [Player]: number } = {}
local stealSuccess: { [Player]: number } = {}

local function send(player: Player?, message: Message, ignoreCooldown: boolean?): ()
    local now = os.clock()
    local text = message.before .. message.accent .. message.after
    local sameText = lastByText[text]
    if sameText and now - sameText < PLAYER_COOLDOWN then
        return
    end
    if player and not ignoreCooldown then
        local last = lastByPlayer[player]
        if last and now - last < PLAYER_COOLDOWN then
            return
        end
        lastByPlayer[player] = now
    end
    lastByText[text] = now
    local remote = Remotes.Get("Feed") :: RemoteEvent
    remote:FireAllClients(message)
end

local function toyLabel(toyId: string, mutationId: string?): (string, Color3?)
    local def = Toys.Get(toyId)
    local mutation = if mutationId then Toys.GetMutation(mutationId) else nil
    local name = if def then def.displayName else toyId
    if mutation then
        return name .. " " .. string.lower(mutation.displayName), MUTATION_COLORS[mutation.id]
    end
    return name, if def then RARITY_COLORS[def.rarity] else nil
end

local function onDeposited(player: Player, toyId: string, mutationId: string?): ()
    local deposit: Deposit = { toyId = toyId, mutation = mutationId, at = os.clock(), discovered = false }
    lastDeposit[player] = deposit
    task.delay(MERGE_SECONDS, function()
        if deposit.discovered or player.Parent == nil then
            return
        end
        local def = Toys.Get(toyId)
        if def == nil or (not SHOWN_RARITIES[def.rarity] and mutationId == nil) then
            return
        end
        local label, color = toyLabel(toyId, mutationId)
        send(player, {
            icon = "jouet" .. toyId,
            fallback = "boutonMesJouets",
            before = player.DisplayName .. " a volé ",
            accent = label,
            after = " !",
            color = color,
        })
    end)
end

local function onDiscovered(player: Player, rarity: string): ()
    if not DISCOVERY_RARITIES[rarity] then
        return
    end
    -- apres les autres ecouteurs du meme depot (lastDeposit est alors a jour)
    task.defer(function()
        local deposit = lastDeposit[player]
        if deposit == nil or os.clock() - deposit.at > 1 then
            return
        end
        deposit.discovered = true
        local label, color = toyLabel(deposit.toyId, nil)
        send(player, {
            icon = "jouet" .. deposit.toyId,
            fallback = "menuCollection",
            before = player.DisplayName .. " a découvert ",
            accent = label,
            after = " !",
            color = color or RARITY_COLORS[rarity],
        }, true)
    end)
end

local function onStat(player: Player, key: string): ()
    if key == "robbed" then
        lastRobbed = { victim = player, at = os.clock() }
    elseif key == "stolenFromPlayers" then
        stealSuccess[player] = os.clock()
        local victim = stealVictim[player]
        send(player, {
            icon = "pouvoirCape",
            fallback = "lourd",
            before = player.DisplayName .. " a volé un jouet dans la base de ",
            accent = if victim then victim.DisplayName else "quelqu'un",
            after = " !",
            color = Color3.fromRGB(255, 95, 95),
        }, true)
    end
end

local function watchCharacter(player: Player, character: Model): ()
    character.ChildAdded:Connect(function(child: Instance)
        if child.Name ~= THIEF_HIGHLIGHT then
            return
        end
        local robbed = lastRobbed
        if robbed and os.clock() - robbed.at < 3 and robbed.victim ~= player then
            stealVictim[player] = robbed.victim
        end
        stealStart[player] = os.clock()
    end)
    character.ChildRemoved:Connect(function(child: Instance)
        if child.Name ~= THIEF_HIGHLIGHT then
            return
        end
        local started = stealStart[player] or 0
        local victim: Player? = stealVictim[player]
        task.delay(0.6, function()
            local success = stealSuccess[player]
            stealVictim[player] = nil
            if victim == nil or victim.Parent == nil or (success and success >= started) then
                return
            end
            send(victim, {
                icon = "retour",
                fallback = "tetine",
                before = "",
                accent = victim.DisplayName,
                after = " a récupéré son jouet !",
                color = Color3.fromRGB(110, 225, 150),
            }, true)
        end)
    end)
end

local function watchPlayer(player: Player): ()
    local previousLevel = player:GetAttribute("Level")
    player:GetAttributeChangedSignal("Level"):Connect(function()
        local level = player:GetAttribute("Level")
        local old = previousLevel
        previousLevel = level
        -- premiere valeur posee au chargement du profil : pas une montee de niveau
        if typeof(level) ~= "number" or typeof(old) ~= "number" or level <= old then
            return
        end
        local milestone = math.floor(level / 5) * 5
        if milestone > old and milestone >= 5 then
            send(player, {
                icon = "etoile",
                fallback = "tetine",
                before = player.DisplayName .. " est passé au ",
                accent = "niveau " .. level,
                after = " !",
                color = Color3.fromRGB(255, 220, 90),
            }, true)
        end
    end)
    player.CharacterAdded:Connect(function(character: Model)
        watchCharacter(player, character)
    end)
    if player.Character then
        watchCharacter(player, player.Character)
    end
end

function FeedService:Init(): () end

function FeedService:Start(): ()
    BaseService.ToyDeposited:Connect(onDeposited)
    ToyCollectionService.Discovered:Connect(onDiscovered)
    DataService.StatChanged:Connect(function(player: Player, key: string)
        onStat(player, key)
    end)
    TrampolineService.Bounced:Connect(function(player: Player)
        send(player, {
            icon = "bebeDort",
            fallback = "tetine",
            before = player.DisplayName .. " a sauté ",
            accent = "dans le berceau",
            after = " !",
            color = Color3.fromRGB(140, 200, 255),
        })
    end)

    local moonActive = false
    local function onMoon(): ()
        local untilTime = Workspace:GetAttribute("MoonUntil")
        local active = typeof(untilTime) == "number" and untilTime > Workspace:GetServerTimeNow()
        if active and not moonActive then
            send(nil, {
                icon = "menuPleineLune",
                fallback = "lune",
                before = "",
                accent = "Pleine lune !",
                after = " Revenu x2",
                color = Color3.fromRGB(200, 215, 255),
            })
        end
        moonActive = active
    end
    Workspace:GetAttributeChangedSignal("MoonUntil"):Connect(onMoon)

    Players.PlayerAdded:Connect(watchPlayer)
    for _, player in Players:GetPlayers() do
        watchPlayer(player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        lastByPlayer[player] = nil
        lastDeposit[player] = nil
        stealVictim[player] = nil
        stealStart[player] = nil
        stealSuccess[player] = nil
    end)
end

return FeedService
