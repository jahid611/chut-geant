--!strict

--[[
    CatalogDecor
    Decors de base supplementaires (modeles gratuits de la boite a outils Roblox, dans le theme chambre de bebe),
    fusionnes dans Catalog. Meme forme qu'un article de Catalog : kind = "cosmetic", slot = "decor", tab = "Cosmétiques",
    needs3D = true (modele dans ServerStorage.CosmeticModels.<id>). Provenance : docs/decors-boite-a-outils.md.
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

local function decor(id: string, name: string, description: string, icon: string, price: number): Item
    return {
        id = id,
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "decor",
        name = name,
        description = description,
        icon = icon,
        prices = { price },
        needs3D = true,
    }
end

local ITEMS: { Item } = {
    decor("DecorRubberDuck", "Canard géant", "Un gros canard de bain.", "iconeDecorCanard", 5000),
    decor("DecorHeartPillow", "Coussin cœur", "Tout doux pour ta base.", "iconeDecorCoussinCoeur", 6000),
    decor("DecorStrawberryPillow", "Coussin fraise", "Un coussin kawaii.", "iconeDecorCoussinFraise", 7000),
    decor("DecorBuildingBlocks", "Cubes de construction", "Une pile de cubes colorés.", "iconeDecorCubes", 8000),
    decor("DecorBunnyPlush", "Lapin en peluche", "Un lapin tout mignon.", "iconeDecorLapin", 10000),
    decor("DecorAlpacaPlush", "Alpaga en peluche", "Un alpaga moelleux.", "iconeDecorAlpaga", 12000),
    decor("DecorMusicBox", "Boîte à musique", "Une petite mélodie pour dormir.", "iconeDecorBoiteMusique", 14000),
    decor("DecorBeanbagBlue", "Pouf bleu", "Pour se reposer entre deux vols.", "iconeDecorPoufBleu", 15000),
    decor("DecorBeanbagRed", "Pouf rouge", "Pour se reposer entre deux vols.", "iconeDecorPoufRouge", 15000),
    decor("DecorBalloons", "Ballons", "Une grappe de ballons.", "iconeDecorBallons", 18000),
    decor("DecorNurseryRug", "Tapis de chambre", "Un grand tapis pour ta base.", "iconeDecorTapis", 20000),
    decor("DecorStarString", "Guirlande d'étoiles", "Des étoiles qui brillent.", "iconeDecorEtoiles", 22000),
    decor("DecorWoodenTrain", "Petit train en bois", "Tchou tchou !", "iconeDecorTrain", 25000),
    decor("DecorStarMobile", "Mobile étoilé", "Un mobile qui fait rêver.", "iconeDecorMobileEtoile", 28000),
    decor("DecorSpaceMobile", "Mobile de l'espace", "Planètes et fusées.", "iconeDecorMobileEspace", 32000),
    decor("DecorToyShelf", "Étagère à jouets", "Pour exposer tes trésors.", "iconeDecorEtagere", 40000),
    decor("DecorPlayTent", "Tente de jeu", "Une cachette douillette.", "iconeDecorTente", 45000),
    decor("DecorCartoonRocket", "Fusée cartoon", "Prête pour le décollage.", "iconeDecorFusee", 60000),
    decor("DecorBouncyCastle", "Château gonflable", "Le rêve de tous les bébés.", "iconeDecorChateau", 80000),
}

return ITEMS
