--!strict

--[[
    CatalogWeapons
    Armes rigolotes (batte rose, tapette a mouche...), fusionnees dans Catalog : kind = "weapon", tab = "Armes",
    slot = "weapon" (une seule arme equipee a la fois, attribut Equipped_weapon), modele d'outil dans
    ServerStorage.WeaponModels.<id> (WeaponService). Stats : Shared/Weapons.
]]

type Item = {
    id: string,
    tab: string,
    kind: string,
    name: string,
    description: string,
    icon: string,
    prices: { number },
    slot: string?,
    needs3D: boolean?,
}

local function weapon(id: string, name: string, description: string, icon: string, price: number): Item
    return {
        id = id,
        tab = "Armes",
        kind = "weapon",
        slot = "weapon",
        name = name,
        description = description,
        icon = icon,
        prices = { price },
        needs3D = true,
    }
end

local ITEMS: { Item } = {
    weapon("WeaponFlySwatter", "Tapette à mouche", "Rapide et précise.", "iconeArmeTapette", 6000),
    weapon("WeaponPillow", "Oreiller", "Touche tout le monde devant toi.", "iconeArmeOreiller", 9000),
    weapon("WeaponPinkBat", "Batte rose", "Fait lâcher les jouets. Bonk !", "iconeArmeBatte", 15000),
    weapon("WeaponFoamSword", "Épée en mousse", "Frappe de plus loin.", "iconeArmeEpee", 20000),
    weapon("WeaponSlipper", "Chausson géant", "Comme maman : ça part loin !", "iconeArmeChausson", 25000),
    weapon("WeaponWaterGun", "Pistolet à eau", "Arrose de très loin.", "iconeArmePistolet", 30000),
    weapon("WeaponSqueakyHammer", "Marteau qui couine", "Très fort, mais très bruyant.", "iconeArmeMarteau", 45000),
    weapon("WeaponMagicWand", "Baguette magique", "Une étincelle qui envoie en l'air.", "iconeArmeBaguette", 60000),
}

return ITEMS
