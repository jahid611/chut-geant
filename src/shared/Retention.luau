--!strict

--[[
    Retention
    Reglages partages des systemes qui font revenir les joueurs : quetes du jour et de la semaine, pass de saison,
    recompense de connexion et roue quotidienne. Serveur (QuestService, PassService, DailyService) et menus client
    (Ui/Menus/Quests, Pass, Gifts) lisent les memes tables.

    Temps : jours et semaines en UTC. Jour n = secondes epoch // 86400 ; semaine = qui commence le lundi.
]]

local DAY = 86400

export type QuestTemplate = {
    id: string,
    -- %d = objectif (en minutes pour playSeconds)
    label: string,
    stat: string,
    daily: number,
    weekly: number,
    -- faux tant qu'aucun service n'emet encore la stat (le modele n'est pas tire au sort)
    available: boolean,
}

export type WheelSlot = {
    kind: "cash" | "xp" | "recharge",
    amount: number,
    label: string,
    weight: number,
    color: Color3,
}

local Retention = {}

Retention.DAY = DAY

--[[
    Quetes. Stats emises aujourd'hui :
    - stolen (BaseService), playSeconds (DataService, par tranche de 60 s) ;
    - stolenRare, stolenHeavy, cashEarned (QuestService, a partir de BaseService.ToyDeposited et de l'attribut Cash).
    En attente d'un service qui les emette (DataService:AddStat) : thrown (jouet lance), momSurvived (« Maman
    arrive ! » sans etre attrape), caught. Passer available = true quand la stat existe.
]]
Retention.QUESTS = table.freeze({
    { id = "Steal", label = "Vole %d jouets", stat = "stolen", daily = 6, weekly = 45, available = true },
    {
        id = "StealRare",
        label = "Vole %d jouets rares ou mieux",
        stat = "stolenRare",
        daily = 1,
        weekly = 8,
        available = true,
    },
    {
        id = "StealHeavy",
        label = "Dépose %d jouets lourds",
        stat = "stolenHeavy",
        daily = 2,
        weekly = 15,
        available = true,
    },
    { id = "Play", label = "Joue %d minutes", stat = "playSeconds", daily = 900, weekly = 7200, available = true },
    { id = "Earn", label = "Gagne %d tétines", stat = "cashEarned", daily = 3000, weekly = 40000, available = true },
    -- mission de la tetine du bebe (PacifierMissionService) : une fois par jour au plus
    {
        id = "Pacifier",
        label = "Vole %d fois la tétine du bébé",
        stat = "pacifierStolen",
        daily = 1,
        weekly = 3,
        available = true,
    },
    { id = "Throw", label = "Lance %d jouets", stat = "thrown", daily = 5, weekly = 30, available = false },
    {
        id = "SurviveMom",
        label = "Échappe %d fois à maman",
        stat = "momSurvived",
        daily = 2,
        weekly = 12,
        available = false,
    },
} :: { QuestTemplate })

Retention.QUESTS_PER_PERIOD = 3
Retention.QUEST_REWARD = table.freeze({
    daily = table.freeze({ cash = 1500, xp = 80 }),
    weekly = table.freeze({ cash = 12000, xp = 400 }),
})

-- Pass de saison : 30 paliers, XP constante par palier.
Retention.PASS_SEASON = 1
Retention.PASS_TIERS = 30
Retention.PASS_XP_PER_TIER = 250
Retention.PASS_XP_PER_TOY = 15
Retention.PASS_XP_PER_MINUTE = 6
-- Cosmetiques gratuits de la piste gratuite (sinon tetines : palier x PASS_CASH_PER_TIER).
Retention.PASS_COSMETICS = table.freeze({ [10] = "TrailStars", [20] = "DanceRobot", [30] = "OutlineGold" })
Retention.PASS_CASH_PER_TIER = 400
-- Si le cosmetique est deja possede, il est rembourse en tetines.
Retention.PASS_COSMETIC_REFUND = 10000

function Retention.PassFreeCash(tier: number): number
    return tier * Retention.PASS_CASH_PER_TIER
end

-- Connexion : 7 jours d'affilee, jour 7 = gros cadeau ; un jour manque remet la serie a 1.
Retention.LOGIN_CASH = table.freeze({ 500, 1000, 1500, 2500, 3500, 5000, 20000 })
Retention.LOGIN_DAY7_XP = 400

-- Roue quotidienne gratuite : 8 cases.
Retention.WHEEL = table.freeze({
    { kind = "cash", amount = 300, label = "300", weight = 22, color = Color3.fromRGB(96, 170, 255) },
    { kind = "xp", amount = 100, label = "100 XP", weight = 18, color = Color3.fromRGB(88, 222, 168) },
    { kind = "cash", amount = 800, label = "800", weight = 18, color = Color3.fromRGB(255, 132, 188) },
    { kind = "recharge", amount = 0, label = "Recharge", weight = 10, color = Color3.fromRGB(168, 104, 255) },
    { kind = "cash", amount = 1500, label = "1 500", weight = 14, color = Color3.fromRGB(255, 212, 96) },
    { kind = "xp", amount = 250, label = "250 XP", weight = 10, color = Color3.fromRGB(64, 196, 140) },
    { kind = "cash", amount = 4000, label = "4 000", weight = 6, color = Color3.fromRGB(245, 88, 96) },
    { kind = "cash", amount = 10000, label = "10 000", weight = 2, color = Color3.fromRGB(245, 180, 40) },
} :: { WheelSlot })

function Retention.DayNumber(t: number): number
    return math.floor(t / DAY)
end

-- Semaines commencant le lundi (le 1er janvier 1970 etait un jeudi).
function Retention.WeekNumber(t: number): number
    return math.floor((math.floor(t / DAY) + 3) / 7)
end

function Retention.SecondsToNextDay(t: number): number
    return DAY - (t % DAY)
end

function Retention.SecondsToNextWeek(t: number): number
    local weekday = (math.floor(t / DAY) + 3) % 7
    return (7 - weekday) * DAY - (t % DAY)
end

-- « 5 h 12 min », « 3 j 4 h »
function Retention.FormatDuration(seconds: number): string
    local s = math.max(math.floor(seconds), 0)
    local days = math.floor(s / DAY)
    local hours = math.floor((s % DAY) / 3600)
    local minutes = math.floor((s % 3600) / 60)
    if days > 0 then
        return string.format("%d j %d h", days, hours)
    elseif hours > 0 then
        return string.format("%d h %d min", hours, minutes)
    end
    return string.format("%d min", math.max(minutes, 1))
end

function Retention.GetQuest(id: string): QuestTemplate?
    for _, quest in Retention.QUESTS do
        if quest.id == id then
            return quest
        end
    end
    return nil
end

return table.freeze(Retention)
