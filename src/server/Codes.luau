--!strict

--[[
    Codes
    Codes cadeaux saisis dans le menu Parametres (CodeService). Garde cote serveur, hors de Shared : les clients ne
    doivent pas pouvoir lire la liste des codes. Chaque code n'est utilisable qu'une fois par joueur.

    cash : tetines ; xp : XP (pass de saison et niveau) ; item : article du catalogue donne (Shared/Catalog), ou
    fallbackCash tetines a la place si le joueur le possede deja.
]]

export type Reward = { cash: number?, xp: number?, item: string?, fallbackCash: number? }

local CODES: { [string]: Reward } = {
    CHUT = { cash = 2000 },
    BEBEDORT = { cash = 5000 },
    NUITBLANCHE = { item = "TrailStars", fallbackCash = 8000 },
    LANCEMENT = { cash = 10000, xp = 200 },
}

return CODES
