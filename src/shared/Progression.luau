--!strict

--[[
    Progression
    Reglages de la retention a long terme : collection, Nuits (renaissance), Pleine lune, bonus amis et groupe,
    classement. Partage serveur (services) et client (menus). Tuning garde l'equilibrage de la partie.
]]

local Progression = {
    -- Ordre d'affichage et de progression des raretes.
    RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary" },
    -- Mutations collectionnables (ids de Shared/Toys).
    MUTATION_IDS = { "Gold", "Rainbow", "Cosmic" },

    -- Collection : tetines gagnees a la premiere decouverte d'un jouet, selon sa rarete.
    COLLECTION_DISCOVERY_REWARD = {
        Common = 150,
        Uncommon = 500,
        Rare = 1500,
        Epic = 5000,
        Legendary = 20000,
    } :: { [string]: number },
    -- Premiere decouverte d'une mutation.
    COLLECTION_MUTATION_REWARD = 4000,
    -- Bonus de revenu permanent par set de rarete complet, et pour les trois mutations.
    COLLECTION_SET_BONUS = 0.05,
    COLLECTION_MUTATION_SET_BONUS = 0.10,

    -- Nuits (renaissance) : prix de la nuit suivante = NIGHT_BASE_COST x (nuits deja passees + 1).
    NIGHT_BASE_COST = 1000000,
    -- Bonus de revenu permanent par nuit passee.
    NIGHT_INCOME_BONUS = 0.25,
    -- Nuit a partir de laquelle la cuisine sera ouverte (encart « Bientôt » pour l'instant).
    NIGHT_KITCHEN_UNLOCK = 3,

    -- Pleine lune : toutes les MOON_INTERVAL_SECONDS, pendant MOON_DURATION_SECONDS.
    MOON_FIRST_DELAY = 5 * 60,
    MOON_INTERVAL_SECONDS = 20 * 60,
    MOON_DURATION_SECONDS = 3 * 60,
    MOON_INCOME_MULTIPLIER = 2,
    -- > 1 : plus de chances qu'un point d'apparition monte d'une rarete (ToySpawnService:SetRarityBoost).
    MOON_RARITY_BOOST = 2,

    -- Bonus sociaux : +10 % de revenu par ami present sur le serveur (3 au plus), groupe Roblox (0 = desactive).
    FRIEND_BONUS = 0.10,
    FRIEND_MAX = 3,
    GROUP_ID = 0,
    GROUP_BONUS = 0.10,

    -- Classement : OrderedDataStore des plus gros voleurs, rafraichi toutes les LEADERBOARD_REFRESH_SECONDS.
    LEADERBOARD_STORE = "ChutGeant_PlusGrosVoleurs_v1",
    LEADERBOARD_REFRESH_SECONDS = 120,
    LEADERBOARD_TOP = 10,
}

return table.freeze(Progression)
