--!strict

--[[
    QuestService
    Quetes du jour (3) et de la semaine (3), tirees au hasard dans Retention.QUESTS parmi les modeles disponibles.

    Progression = stat du profil (DataService) moins sa valeur au moment du tirage : aucune quete ne se souvient
    d'autre chose que son point de depart. Stats emises ici, a partir d'evenements existants :
    - stolenRare  : jouet rare, epique ou legendaire depose (BaseService.ToyDeposited) ;
    - stolenHeavy : jouet a 2 porteurs ou plus depose ;
    - cashEarned  : hausse de l'attribut Cash du joueur (revenu, recompenses).
    Stats attendues d'autres services (modeles marques available = false dans Retention) : thrown, momSurvived.

    Nouveau tirage a minuit UTC (jour) et le lundi a minuit UTC (semaine), verifie toutes les 30 s.
    Recompense : tetines + XP de pass (Retention.QUEST_REWARD). Client : attribut Quests_State (JSON) et remote
    QuestState, pastille Notif_Quetes ; ClaimQuest ("daily:2" | "weekly:1") -> (ok, message).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Retention = require(Shared:WaitForChild("Retention"))
local Toys = require(Shared:WaitForChild("Toys"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local PassService = require(script.Parent:WaitForChild("PassService"))

type QuestEntry = { id: string, target: number, base: number, claimed: boolean }
type QuestData = { day: number, week: number, daily: { QuestEntry }, weekly: { QuestEntry } }

local RARE_OR_BETTER: { [string]: boolean } = { Rare = true, Epic = true, Legendary = true }

local QuestService = {}

local random = Random.new()
local dirty: { [Player]: boolean } = {}
local lastCash: { [Player]: number } = {}

local function formatNumber(value: number): string
    local digits = tostring(math.floor(math.abs(value)))
    local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1 ")))
    return (string.gsub(grouped, "^ ", ""))
end

local function pick(period: "daily" | "weekly", stats: { [string]: number }): { QuestEntry }
    local pool = {}
    for _, template in Retention.QUESTS do
        if template.available then
            table.insert(pool, template)
        end
    end
    for i = #pool, 2, -1 do
        local j = random:NextInteger(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local entries: { QuestEntry } = {}
    for i = 1, math.min(Retention.QUESTS_PER_PERIOD, #pool) do
        local template = pool[i]
        table.insert(entries, {
            id = template.id,
            target = if period == "daily" then template.daily else template.weekly,
            base = stats[template.stat] or 0,
            claimed = false,
        })
    end
    return entries
end

-- Quetes du joueur, retirees si la journee ou la semaine a change. Rend (donnees, changees ?).
local function ensure(profile: DataService.Profile): (QuestData, boolean)
    local now = os.time()
    local day, week = Retention.DayNumber(now), Retention.WeekNumber(now)
    local data = profile.quests :: any
    local changed = false
    if data.day ~= day or typeof(data.daily) ~= "table" then
        data.day = day
        data.daily = pick("daily", profile.stats)
        changed = true
    end
    if data.week ~= week or typeof(data.weekly) ~= "table" then
        data.week = week
        data.weekly = pick("weekly", profile.stats)
        changed = true
    end
    return data :: QuestData, changed
end

local function progressOf(profile: DataService.Profile, entry: QuestEntry): number
    local template = Retention.GetQuest(entry.id)
    if template == nil then
        return 0
    end
    return math.clamp((profile.stats[template.stat] or 0) - entry.base, 0, entry.target)
end

local function view(profile: DataService.Profile, period: string, list: { QuestEntry }): ({ any }, boolean)
    local rows = {}
    local pending = false
    for i, entry in list do
        local template = Retention.GetQuest(entry.id)
        if template == nil then
            continue
        end
        local progress = progressOf(profile, entry)
        local done = progress >= entry.target
        -- temps de jeu affiche en minutes
        local minutes = template.stat == "playSeconds"
        local shownTarget = if minutes then math.floor(entry.target / 60) else entry.target
        local shownProgress = if minutes then math.floor(progress / 60) else progress
        if done and not entry.claimed then
            pending = true
        end
        table.insert(rows, {
            key = period .. ":" .. i,
            label = string.format(template.label, shownTarget),
            progress = shownProgress,
            target = shownTarget,
            done = done,
            claimed = entry.claimed,
        })
    end
    return rows, pending
end

local function push(player: Player): ()
    local profile = DataService:Get(player)
    if profile == nil then
        return
    end
    local data = ensure(profile)
    local daily, dailyPending = view(profile, "daily", data.daily)
    local weekly, weeklyPending = view(profile, "weekly", data.weekly)
    local now = os.time()
    local state = {
        daily = daily,
        weekly = weekly,
        dailyResetAt = now + Retention.SecondsToNextDay(now),
        weeklyResetAt = now + Retention.SecondsToNextWeek(now),
    }
    player:SetAttribute("Quests_State", HttpService:JSONEncode(state))
    player:SetAttribute("Notif_Quetes", dailyPending or weeklyPending)
    local remote = Remotes.Get("QuestState") :: RemoteEvent
    remote:FireClient(player, state)
end

function QuestService:Claim(player: Player, key: string): (boolean, string)
    local profile = DataService:Get(player)
    if profile == nil then
        return false, "Ton profil charge encore, réessaie."
    end
    local period, indexText = string.match(key, "^(%a+):(%d+)$")
    local index = if indexText then tonumber(indexText) else nil
    if (period ~= "daily" and period ~= "weekly") or index == nil then
        return false, "Quête inconnue."
    end
    local data = ensure(profile)
    local list = if period == "daily" then data.daily else data.weekly
    local entry = list[index :: number]
    if entry == nil then
        return false, "Quête inconnue."
    end
    if entry.claimed then
        return false, "Déjà récupérée."
    end
    if progressOf(profile, entry) < entry.target then
        return false, "Quête pas encore terminée."
    end
    entry.claimed = true
    local reward = if period == "daily" then Retention.QUEST_REWARD.daily else Retention.QUEST_REWARD.weekly
    BaseService:AddCash(player, reward.cash)
    PassService:AddXp(player, reward.xp)
    push(player)
    return true, string.format("Quête réussie : +%s tétines, +%d XP !", formatNumber(reward.cash), reward.xp)
end

function QuestService:Init(): () end

function QuestService:Start(): ()
    local claim = Remotes.Get("ClaimQuest") :: RemoteFunction
    claim.OnServerInvoke = function(player: Player, key: any)
        if typeof(key) ~= "string" then
            return false, "Requête invalide."
        end
        return QuestService:Claim(player, key)
    end

    BaseService.ToyDeposited:Connect(function(player: Player, toyId: string)
        local def = Toys.Get(toyId)
        if def == nil then
            return
        end
        if RARE_OR_BETTER[def.rarity] then
            DataService:AddStat(player, "stolenRare", 1)
        end
        if def.carriers >= 2 then
            DataService:AddStat(player, "stolenHeavy", 1)
        end
    end)

    DataService.StatChanged:Connect(function(player: Player)
        dirty[player] = true
    end)

    local function onPlayer(player: Player): ()
        local profile = DataService:WaitForProfile(player)
        if profile == nil then
            return
        end
        ensure(profile)
        push(player)
        -- tetines gagnees : hausses de l'attribut Cash (la premiere valeur posee au chargement ne compte pas)
        player:GetAttributeChangedSignal("Cash"):Connect(function()
            local cash = player:GetAttribute("Cash")
            if typeof(cash) ~= "number" then
                return
            end
            local previous: number? = lastCash[player]
            lastCash[player] = cash
            if previous and cash > previous then
                DataService:AddStat(player, "cashEarned", cash - previous)
            end
        end)
        local cash = player:GetAttribute("Cash")
        if typeof(cash) == "number" then
            lastCash[player] = cash
        end
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        dirty[player] = nil
        lastCash[player] = nil
    end)

    -- Envoi groupe (le revenu change la stat cashEarned chaque seconde) et changement de jour.
    task.spawn(function()
        local sinceRollover = 0
        while true do
            task.wait(1)
            sinceRollover += 1
            local checkRollover = sinceRollover >= 30
            if checkRollover then
                sinceRollover = 0
            end
            for _, player in Players:GetPlayers() do
                local profile = DataService:Get(player)
                if profile == nil then
                    continue
                end
                local changed = false
                if checkRollover then
                    _, changed = ensure(profile)
                end
                if changed or dirty[player] then
                    dirty[player] = nil
                    push(player)
                end
            end
        end
    end)
end

return QuestService
