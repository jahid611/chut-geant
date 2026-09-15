--!strict

--[[
    Weapons
    Stats des armes rigolotes (demande utilisateur du 15/09 : batte rose, tapette a mouche...), partagees serveur
    (WeaponService verifie cadence, portee et cone) et client (WeaponController : cadence affichee, sons).
    Prix, noms et icones : Shared/CatalogWeapons. Modeles : ServerStorage.WeaponModels.<id>.

    range    : distance maximale (studs) entre le bassin de l'attaquant et celui de la cible ;
    cone     : demi-angle (degres) devant l'attaquant dans lequel la cible doit se trouver ;
    cooldown : secondes entre deux coups ;
    launch   : vitesse horizontale de propulsion de la cible ; up : vitesse verticale ;
    noise    : bruit ajoute a la jauge par coup qui touche ;
    dropsToy : la cible lache le jouet qu'elle porte ;
    multi    : touche toutes les cibles du cone (sinon la plus proche) ;
    hitSound : nom de son d'Ui/Sfx joue au contact.
    Prise en main (WeaponService calcule Tool.Grip). Reglage explicite par arme, releve sur un banc de captures
    (repere de la poignee, 15/09 : la tapette etait tenue par la tete) :
    gripAxis : axe de la longueur de l'arme dans le repere de la poignee ("X", "Y" ou "Z") ;
    gripEnd  : bout du manche sur cet axe (-1 = cote min, 1 = cote max) ; l'arme part vers l'autre bout ;
    gripAt   : distance de la main depuis ce bout, en fraction de la longueur (defaut 0,12) ;
    gripOffset : decalage supplementaire dans le repere de la poignee (poignee de pistolet sous le corps) ;
    gripUp   : axe « haut » de l'arme dans le repere de la poignee (defaut Y, ou Z si la longueur est Y) ;
    gripTilt : inclinaison vers le haut en degres (defaut 20) ; gripRoll : rotation autour de la longueur.
    Sans gripAxis : calcul automatique (grand axe, bout le plus fin), gripFlip pour inverser.
    style    : geste de frappe de WeaponController ("arc", "overhead", "sweep", "shoot", "flick").
]]

export type Weapon = {
    id: string,
    range: number,
    cone: number,
    cooldown: number,
    launch: number,
    up: number,
    noise: number,
    dropsToy: boolean,
    multi: boolean,
    hitSound: string,
    gripTilt: number?,
    gripRoll: number?,
    gripFlip: boolean?,
    gripAxis: string?,
    gripEnd: number?,
    gripAt: number?,
    gripOffset: Vector3?,
    gripUp: Vector3?,
    style: string?,
}

local LIST: { Weapon } = {
    -- Batte de baseball rose : l'arme de reference, equilibree.
    {
        id = "WeaponPinkBat",
        range = 9,
        cone = 55,
        cooldown = 1.2,
        launch = 95,
        up = 55,
        noise = 8,
        dropsToy = true,
        multi = false,
        hitSound = "weaponBonk",
        -- manche fin en bas (Y min), gros bout en haut
        gripAxis = "Y",
        gripEnd = -1,
        gripAt = 0.1,
        gripTilt = 25,
        style = "arc",
    },
    -- Tapette a mouche : rapide et precise, pousse peu.
    {
        id = "WeaponFlySwatter",
        range = 10,
        cone = 30,
        cooldown = 0.6,
        launch = 55,
        up = 30,
        noise = 4,
        dropsToy = true,
        multi = false,
        hitSound = "weaponSwat",
        -- une seule piece : manche du cote Z max, tete plate du cote Z min
        gripAxis = "Z",
        gripEnd = 1,
        gripAt = 0.08,
        gripTilt = 25,
        style = "arc",
    },
    -- Oreiller : large (touche tout le monde devant) mais faible, silencieux.
    {
        id = "WeaponPillow",
        range = 8,
        cone = 80,
        cooldown = 1.4,
        launch = 45,
        up = 25,
        noise = 1,
        dropsToy = false,
        multi = true,
        hitSound = "weaponPillow",
        -- tenu par un coin, balaye a l'horizontale
        gripAxis = "X",
        gripEnd = -1,
        gripAt = 0.06,
        gripTilt = 10,
        style = "sweep",
    },
    -- Epee en mousse : bonne allonge.
    {
        id = "WeaponFoamSword",
        range = 12,
        cone = 45,
        cooldown = 1,
        launch = 80,
        up = 45,
        noise = 5,
        dropsToy = true,
        multi = false,
        hitSound = "weaponBonk",
        -- garde et poignee du cote Y max, pointe de la lame en Y min
        gripAxis = "Y",
        gripEnd = 1,
        gripAt = 0.1,
        gripTilt = 25,
        style = "arc",
    },
    -- Marteau qui couine : lent, fort, et il couine (bruyant).
    {
        id = "WeaponSqueakyHammer",
        range = 9,
        cone = 45,
        cooldown = 1.8,
        launch = 120,
        up = 70,
        noise = 14,
        dropsToy = true,
        multi = false,
        hitSound = "weaponSqueak",
        -- manche en Y min, tete en Y max
        gripAxis = "Y",
        gripEnd = -1,
        gripAt = 0.1,
        gripTilt = 25,
        style = "arc",
    },
    -- Pistolet a eau : portee longue, cone etroit, propulsion faible.
    {
        id = "WeaponWaterGun",
        range = 45,
        cone = 12,
        cooldown = 1.1,
        launch = 40,
        up = 20,
        noise = 3,
        dropsToy = false,
        multi = false,
        hitSound = "weaponSplash",
        -- canon en X max ; la main tient la crosse sous le corps, vers l'arriere
        gripAxis = "X",
        gripEnd = -1,
        gripAt = 0.32,
        gripOffset = Vector3.new(0, -0.45, 0),
        gripTilt = 0,
        style = "shoot",
    },
    -- Chausson : comme celui de maman, frappe fort et fait lacher.
    {
        id = "WeaponSlipper",
        range = 10,
        cone = 40,
        cooldown = 1.3,
        launch = 105,
        up = 60,
        noise = 9,
        dropsToy = true,
        multi = false,
        hitSound = "weaponSwat",
        -- tenu par le talon (Z max), la lanière est a l'avant (Z min)
        gripAxis = "Z",
        gripEnd = 1,
        gripAt = 0.12,
        gripTilt = 15,
        style = "overhead",
    },
    -- Baguette magique : petite etincelle, portee moyenne, discrete.
    {
        id = "WeaponMagicWand",
        range = 22,
        cone = 20,
        cooldown = 1.5,
        launch = 70,
        up = 80,
        noise = 2,
        dropsToy = true,
        multi = false,
        hitSound = "weaponSparkle",
        gripAxis = "Y",
        gripEnd = -1,
        gripAt = 0.15,
        gripTilt = 20,
        style = "flick",
    },
}

local Weapons = {}

Weapons.LIST = LIST
-- Nom de l'attribut pose sur l'outil donne au joueur.
Weapons.TOOL_ATTRIBUTE = "WeaponId"

local byId: { [string]: Weapon } = {}
for _, weapon in LIST do
    byId[weapon.id] = table.freeze(weapon)
end

function Weapons.Get(id: string): Weapon?
    return byId[id]
end

return Weapons
