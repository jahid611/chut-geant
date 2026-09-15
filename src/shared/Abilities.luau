--!strict

--[[
    Abilities
    Reglages et etat des pouvoirs actifs et des ameliorations a niveaux (catalogue : Shared/Catalog).
    Partage serveur (AbilityService, GiantService, EventService, CarryService, NoiseService) et client
    (AbilityController : barre de pouvoirs, touches).

    Etat publie en attributs du joueur, en temps serveur (workspace:GetServerTimeNow()) :
    - <Id>Until   : fin de l'effet en cours (pouvoirs a duree) ;
    - <Id>ReadyAt : prochaine utilisation possible ;
    - Owned_<Id>  : niveau possede (ShopService).
    Hochet leurre : attribut DecoyUntil du workspace (le bebe regarde le hochet, personne n'est attrape).
]]

export type Ability = {
    id: string,
    short: string, -- nom court affiche sous la case de la barre
    key: Enum.KeyCode,
    gamepad: Enum.KeyCode?,
    color: Color3,
    cooldown: number,
    duration: number, -- 0 = effet instantane
}

local Tuning = require(script.Parent:WaitForChild("Tuning"))

local Abilities = {}

-- Tetine magique : part de la jauge retiree.
Abilities.PACIFIER_FRACTION = 0.3
-- Hochet leurre : duree pendant laquelle le bebe regarde ailleurs, et vitesse du lancer du hochet.
Abilities.DECOY_SECONDS = 4
Abilities.DECOY_THROW_SPEED = 45
-- Ventouse = tir vise (retour utilisateur du 15/09) : portee par niveau, jouets lourds a partir du niveau 2.
-- Tir rate (rien touche, jouet trop lourd) : recharge courte au lieu de la recharge complete.
Abilities.SUCTION_RANGES = { 90, 160 }
Abilities.SUCTION_RANGE = 90
Abilities.SUCTION_HEAVY_LEVEL = 2
Abilities.SUCTION_MISS_COOLDOWN = 3
-- Tolerance du tir : un jouet dont le centre passe a moins de ceci (+ un tiers de sa taille) du trait est touche.
Abilities.SUCTION_AIM_TOLERANCE = 1.2
-- Cone de l'ancienne visee automatique (CarryService:FindAimed, gardee pour compatibilite).
Abilities.SUCTION_MIN_DOT = 0.9
-- Cape d'ombre : transparence du personnage pendant l'effet.
Abilities.CAPE_TRANSPARENCY = 0.7

-- Ameliorations a niveaux
Abilities.QUIET_PER_LEVEL = 0.1 -- Chaussons silencieux : -10 % de bruit de deplacement par niveau
-- (x1,21 le 15/09, comme toutes les vitesses de base)
Abilities.STRONG_BONUS_PER_LEVEL = 2.4 -- Bras costauds : vitesse en portant (aide suffisante)
Abilities.STRONG_ALONE_PER_LEVEL = 1.8 -- Bras costauds : vitesse seul sur un jouet lourd
Abilities.MAGNET_PER_LEVEL = 0.1 -- Aimant a tetines : +10 % de revenu par niveau
Abilities.KEEN_EAR_LEAD = { 3, 6 } -- Oreille fine : secondes d'avance de l'indice, par niveau

local LIST: { Ability } = {
    {
        id = "Fury",
        short = "Furie",
        key = Enum.KeyCode.R,
        gamepad = Enum.KeyCode.ButtonY,
        color = Color3.fromRGB(255, 132, 188),
        cooldown = Tuning.FURY_COOLDOWN,
        duration = Tuning.FURY_SECONDS,
    },
    {
        id = "MagicPacifier",
        short = "Tétine",
        key = Enum.KeyCode.T,
        gamepad = Enum.KeyCode.DPadUp,
        color = Color3.fromRGB(88, 222, 168),
        cooldown = 90,
        duration = 0,
    },
    {
        id = "DecoyRattle",
        short = "Hochet",
        key = Enum.KeyCode.Y,
        gamepad = Enum.KeyCode.DPadLeft,
        color = Color3.fromRGB(255, 212, 96),
        cooldown = 120,
        duration = 4,
    },
    {
        id = "ShieldPlush",
        short = "Doudou",
        key = Enum.KeyCode.H,
        gamepad = Enum.KeyCode.DPadRight,
        color = Color3.fromRGB(96, 170, 255),
        cooldown = 90,
        duration = 60,
    },
    {
        id = "SuctionGun",
        short = "Ventouse",
        key = Enum.KeyCode.V,
        gamepad = Enum.KeyCode.DPadDown,
        color = Color3.fromRGB(245, 88, 96),
        cooldown = 45,
        duration = 0,
    },
    {
        id = "ShadowCape",
        short = "Cape",
        key = Enum.KeyCode.C,
        gamepad = Enum.KeyCode.ButtonL1,
        color = Color3.fromRGB(128, 96, 200),
        cooldown = 120,
        duration = 5,
    },
    {
        id = "Lullaby",
        short = "Berceuse",
        key = Enum.KeyCode.X,
        gamepad = Enum.KeyCode.ButtonL2,
        color = Color3.fromRGB(176, 190, 245),
        cooldown = 300,
        duration = 0,
    },
}

local byId: { [string]: Ability } = {}
for _, ability in LIST do
    byId[ability.id] = table.freeze(ability)
end

Abilities.LIST = LIST

function Abilities.Get(id: string): Ability?
    return byId[id]
end

-- Niveau possede d'un article du catalogue (0 = pas achete).
function Abilities.Level(player: Player, itemId: string): number
    local level = player:GetAttribute("Owned_" .. itemId)
    return if typeof(level) == "number" then level else 0
end

-- Effet a duree en cours ?
function Abilities.IsActive(player: Player, id: string): boolean
    local untilTime = player:GetAttribute(id .. "Until")
    return typeof(untilTime) == "number" and untilTime > workspace:GetServerTimeNow()
end

-- Le bebe regarde-t-il un hochet leurre ?
function Abilities.IsDecoyActive(): boolean
    local untilTime = workspace:GetAttribute("DecoyUntil")
    return typeof(untilTime) == "number" and untilTime > workspace:GetServerTimeNow()
end

-- Doudou bouclier (serveur) : consomme le bouclier s'il est actif. Vrai si la propulsion est annulee.
function Abilities.ConsumeShield(player: Player): boolean
    if Abilities.IsActive(player, "ShieldPlush") then
        player:SetAttribute("ShieldPlushUntil", nil)
        return true
    end
    return false
end

return Abilities
