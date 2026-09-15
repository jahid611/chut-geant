--!strict

--[[
    Tutorial
    Etapes du tutoriel des nouveaux joueurs (TutorialService / TutorialController), textes tres courts.

    target :
    - "toy"  : fleche vers un jouet proche de la base (attribut joueur TutorialTarget) ;
    - "base" : fleche vers la base du joueur ;
    - "ui"   : surbrillance d'un element du HUD (chemin dans PlayerGui, voir `ui`) ;
    - "none" : bulle seule.
    manual : l'etape avance avec le bouton de la bulle (etapes d'information).
]]

export type Step = {
    title: string,
    text: string,
    icon: string,
    target: "toy" | "base" | "ui" | "none",
    ui: { string }?,
    manual: boolean,
    button: string?,
}

local Tutorial = {}

Tutorial.STEPS = table.freeze({
    {
        title = "Chut ! Le bébé dort.",
        text = "Approche-toi doucement du jouet.",
        icon = "bebeDort",
        target = "toy",
        manual = false,
    },
    {
        title = "Vole-le !",
        text = "Maintiens le bouton pour l'attraper.",
        icon = "boutonMesJouets",
        target = "toy",
        manual = false,
    },
    {
        title = "Ramène-le dans ta base",
        text = "Suis la flèche jusqu'à ta base.",
        icon = "articleCoffre",
        target = "base",
        manual = false,
    },
    {
        title = "Des tétines chaque seconde !",
        text = "Chaque jouet de ta base te rapporte.",
        icon = "tetine",
        target = "ui",
        ui = { "HUD", "Tetines" },
        manual = true,
        button = "Suivant",
    },
    {
        title = "Ta première amélioration",
        text = "Ouvre la boutique et achète quelque chose.",
        icon = "boutonBoutique",
        target = "ui",
        ui = { "HUD", "Boutons", "Boutique" },
        manual = false,
    },
    {
        title = "Attention au bruit !",
        text = "Jauge pleine : le bébé se réveille.",
        icon = "bebeDort",
        target = "ui",
        ui = { "HUD", "Bruit" },
        manual = true,
        button = "Compris",
    },
    {
        title = "Bravo, petit voleur !",
        text = "Quêtes et cadeaux t'attendent à gauche.",
        icon = "menuCadeaux",
        target = "ui",
        ui = { "Menus", "Colonne" },
        manual = true,
        button = "C'est parti",
    },
} :: { Step })

-- Etape de fin (recompense).
Tutorial.FINAL_STEP = 7
-- Tetines offertes a l'etape « premiere amelioration », pour pouvoir acheter tout de suite.
Tutorial.SHOP_BONUS = 3000
-- Recompense de fin : tetines + cosmetique (tetines en plus s'il est deja possede).
Tutorial.REWARD_CASH = 5000
Tutorial.REWARD_ITEM = "TrailRainbow"
Tutorial.REWARD_ITEM_FALLBACK_CASH = 3000
-- Distance (studs) a laquelle l'etape « approche » est validee.
Tutorial.NEAR_TOY = 16
-- Etape d'information qui avance seule si le joueur ne clique pas.
Tutorial.AUTO_NEXT_SECONDS = 12

return table.freeze(Tutorial)
