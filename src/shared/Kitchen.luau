--!strict

--[[
    Kitchen
    Reglages de la cuisine, 2e piece debloquee a la Nuit Progression.NIGHT_KITCHEN_UNLOCK, et du chien de la famille
    qui la garde (KitchenService, DogService, DogController, recette tools/scene/build-cuisine.luau).
]]

local Kitchen = {
    -- Volume de la cuisine (partie invisible taguee) et portes (trous de souris) : attributs Destination (CFrame)
    -- et Direction ("in" = de la chambre vers la cuisine, "out" = retour).
    ZONE_TAG = "KitchenZone",
    DOOR_TAG = "KitchenDoor",
    -- Modele du chien, enfant direct de workspace.Cuisine.
    DOG_NAME = "Chien",

    -- Jauge du chien, independante de celle du bebe (NoiseService).
    NOISE_MAX = 100,
    NOISE_DECAY_PER_SECOND = 5,
    -- Carrelage qui resonne : deplacements et atterrissages x1,3 par rapport au parquet de la chambre.
    TILE_NOISE_FACTOR = 1.3,
    -- Un jouet lance (non porte) plus rapide que ceci dans la cuisine fait du bruit tant qu'il vole.
    THROWN_TOY_SPEED = 30,
    THROWN_TOY_NOISE_PER_SECOND = 20,
    BROADCAST_HZ = 5,

    -- Reveil : il grogne (le temps de s'immobiliser), puis chasse ; tout joueur de la cuisine qui bouge est attrape.
    GROWL_SECONDS = 2,
    HUNT_SECONDS = 8,
    FREEZE_SPEED = 2.5,
    JUMP_RISE = 0.6,
    -- Le chien envoie moins loin que le bebe (la cuisine est plus petite que la chambre).
    LAUNCH_FACTOR = 0.75,

    -- Portes
    DOOR_COOLDOWN = 1.2,
    FADE_SECONDS = 0.35,
    LOCKED_NOTICE_SECONDS = 3,
    LOCKED_PUSH = 10,
}

return table.freeze(Kitchen)
