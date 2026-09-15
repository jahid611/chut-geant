--!strict

--[[
    Levels
    Niveau du joueur (LevelService / LevelController) : toute l'XP passe par PassService:AddXp, qui nourrit a la fois
    le pass de saison et le niveau (evenement PassService.XpGained).

    Sources d'XP en plus de celles du pass (quetes, roue, connexion, 15 XP par jouet vole, 6 XP par minute) :
    - jouet depose : selon sa rarete, multiplie par sa mutation, + un bonus par porteur en plus ;
    - survivre a « Maman arrive ! » ou « Vite, dans l'ombre ! » en etant dans la chambre ;
    - premiere decouverte d'un jouet ou d'une mutation (collection).
]]

local Levels = {}

Levels.MAX_LEVEL = 100

-- XP necessaire pour passer du niveau `level` au suivant.
function Levels.XpNeeded(level: number): number
    return math.floor(100 * math.pow(math.max(level, 1), 1.35) + 0.5)
end

Levels.XP_BY_RARITY = table.freeze({
    Common = 10,
    Uncommon = 20,
    Rare = 40,
    Epic = 80,
    Legendary = 200,
})
Levels.XP_MUTATION_MULTIPLIER = table.freeze({
    Gold = 1.5,
    Rainbow = 2,
    Cosmic = 3,
})
-- Par porteur requis au-dela du premier (jouets lourds).
Levels.XP_HEAVY_BONUS = 25
Levels.XP_SURVIVE = table.freeze({
    MomComing = 60,
    ShadowRun = 40,
})
Levels.XP_DISCOVERY = 50
Levels.XP_MUTATION_DISCOVERY = 100

-- Recompenses : tetines a chaque niveau, gros bonus tous les MILESTONE_EVERY niveaux, cosmetiques a certains paliers.
Levels.MILESTONE_EVERY = 5
function Levels.CashReward(level: number): number
    return 250 * level
end
function Levels.MilestoneCash(level: number): number
    return 2000 * level
end
Levels.COSMETICS = table.freeze({
    [10] = "TrailRainbow",
    [20] = "DanceJoy",
    [30] = "TrailHearts",
    [50] = "OutlineRainbow",
} :: { [number]: string })
-- Cosmetique deja possede : tetines a la place.
function Levels.CosmeticRefund(level: number): number
    return 5000 * level
end

-- Titres affiches sous le niveau (a partir du niveau indique).
Levels.TITLES = table.freeze({
    { level = 1, title = "Apprenti voleur" },
    { level = 5, title = "Voleur discret" },
    { level = 10, title = "Pas de velours" },
    { level = 15, title = "Ombre de la nuit" },
    { level = 25, title = "Chapardeur agile" },
    { level = 35, title = "Maître chapardeur" },
    { level = 50, title = "Roi des doudous" },
    { level = 70, title = "Fantôme du couloir" },
    { level = 85, title = "Terreur des coffres" },
    { level = 100, title = "Légende du berceau" },
})

function Levels.TitleFor(level: number): string
    local current = Levels.TITLES[1].title
    for _, entry in Levels.TITLES do
        if level >= entry.level then
            current = entry.title
        end
    end
    return current
end

-- Prochain niveau qui donne une grosse recompense (palier ou cosmetique), ou nil au niveau max.
function Levels.NextMilestone(level: number): number?
    if level >= Levels.MAX_LEVEL then
        return nil
    end
    local nextLevel = (math.floor(level / Levels.MILESTONE_EVERY) + 1) * Levels.MILESTONE_EVERY
    return math.min(nextLevel, Levels.MAX_LEVEL)
end

return table.freeze(Levels)
