--!strict

--[[
    Tuning
    Tous les reglages d'equilibrage du jeu, au meme endroit.
]]

local Tuning = {
    -- Manches collectives : seuls les dépôts stockés venant du monde comptent.
    ROUND_PREPARE_SECONDS = 10,
    ROUND_ACTIVE_SECONDS = 300,
    ROUND_RESULT_SECONDS = 6,
    ROUND_PAUSE_SECONDS = 10,
    ROUND_SOLO_GOAL = 6,
    ROUND_EXTRA_PLAYER_GOAL = 4,
    ROUND_REWARD_CAP = 12,
    ROUND_FAILURE_CASH = 100,
    ROUND_FAILURE_XP = 5,
    ROUND_SUCCESS_CASH = 200,
    ROUND_SUCCESS_XP = 10,
    ROUND_SUCCESS_CASH_BONUS = 300,
    ROUND_SUCCESS_XP_BONUS = 20,
    ROUND_PUBLISH_SECONDS = 0.5,
    ROUND_POLL_SECONDS = 0.1,
    ROUND_LEADERBOARD_SIZE = 8,
    ROUND_LAST_MINUTE_SECONDS = 60,
    ROUND_URGENT_SECONDS = 10,

    -- Deplacement
    -- 15/09 : un peu plus rapide (retour utilisateur), 14 -> 17 ; les autres vitesses suivent en proportion (x1,21)
    -- et SNEAK_SPEED aussi, donc le bruit a pleine vitesse ne change pas (NoiseService rapporte la vitesse a ces deux).
    -- 15/09 soir : « augmente pas mal la vitesse de base des joueurs, donc proportionnellement celle des bonus » : x1,3
    -- sur toutes les vitesses de deplacement (marche, portage, se faufiler, Furie, bras costauds).
    WALK_SPEED = 22,
    -- Vitesse en portant, selon le nombre de porteurs requis par le jouet.
    CARRY_SPEED = { 17.5, 12.5, 9.75 },
    -- Vitesse d'un porteur a qui il manque des coequipiers.
    CARRY_SPEED_ALONE = 3.25,
    -- Distance a laquelle un coequipier compte comme aide au portage.
    HELPER_RADIUS = 10,
    PICKUP_DISTANCE = 10,

    -- Bruit
    NOISE_MAX = 100,
    -- Les petites prises de risque se récupèrent au calme ; la course longue reste dangereuse.
    NOISE_DECAY_PER_SECOND = 8,
    -- En dessous de cette vitesse horizontale (studs/s), on se faufile sans bruit.
    SNEAK_SPEED = 12.4,
    -- Bruit par seconde a pleine vitesse, multiplie par le nombre de porteurs du jouet tenu.
    -- 15/09 soir : « diminue pas mal la rapidite de la jauge a se remplir, ca permet de jouer au jeu » : -40 %.
    NOISE_MOVE_PER_SECOND = 8,
    NOISE_MOVE_INITIAL = 5,
    NOISE_RAMP_START_SECONDS = 3,
    NOISE_RAMP_END_SECONDS = 8,
    NOISE_RUN_RECOVERY = 2,
    NOISE_OTHER_PLAYERS_FACTOR = 0.5,
    -- Cuisine : débit historique, indépendant de la rampe de la chambre.
    DOG_NOISE_MOVE_PER_SECOND = 8,
    NOISE_LANDING = 7,
    NOISE_BROADCAST_HZ = 10,

    -- Geant
    GIANT_WAKE_SECONDS = 2,
    -- 10 -> 14 : la chasse est devenue une course-poursuite (HandChaseService), il faut le temps de fuir.
    -- 14 -> 7 (15/09) : « 15 secondes c'est beaucoup trop long » (utilisateur), reveil + chasse = 9 s.
    GIANT_HUNT_SECONDS = 7,
    -- Main geante (HandChaseService) : pendant une chasse de reveil, une ombre de main poursuit un joueur de la
    -- chambre au lieu de la regle « bouger = attrape » (false = ancienne regle).
    HAND_CHASE_ENABLED = true,
    -- Vitesse de la main (studs/s), lineaire du debut a la fin de la chasse : on la distance a vide (marche 17), pas
    -- en portant un jouet (13,5 / 9,5 / 7,5) sans Furie.
    -- 15/09 soir : « elle est super lente » ; avec la marche a 22, elle part a 20 et finit a 30 (rattrape a vide).
    HAND_SPEED_START = 20,
    HAND_SPEED_END = 30,
    -- Contact : distance horizontale au centre de l'ombre, et ecart vertical maximal (sauter ne suffit pas a passer).
    HAND_CATCH_RADIUS = 7,
    HAND_REACH_HEIGHT = 12,
    HAND_RETARGET_SECONDS = 0.3,
    -- Prime a la fin de la chasse pour un joueur poursuivi par la main et jamais attrape.
    HAND_SURVIVE_XP = 40,
    HAND_SURVIVE_CASH = 150,
    -- Pendant la chasse, se deplacer plus vite que ceci (studs/s, mesure sur 0,2 s) = propulse, a chaque fois.
    GIANT_FREEZE_SPEED = 2.5,
    -- Monter de plus que ceci (studs) entre deux controles = saut = propulse aussi.
    GIANT_JUMP_RISE = 0.6,

    -- Jouets
    RESPAWN_SECONDS = 8,
    KITCHEN_RESPAWN_SECONDS = 20,
    -- Les points d'accueil servent au premier vol et au dépannage, sans boucle de combo trop rentable.
    WELCOME_RESPAWN_SECONDS = 25,
    WELCOME_POINTS_PER_BASE = 2,
    WELCOME_MIN_DISTANCE = 35,
    WELCOME_MAX_DISTANCE = 55,
    WELCOME_POINT_SPACING = 20,
    RARITY_WEIGHTS = {
        Common = 60,
        Uncommon = 25,
        Rare = 10,
        Epic = 4,
        Legendary = 1,
    },
    -- Chance de mutation a l'apparition, testees de la plus rare a la plus commune.
    MUTATION_CHANCES = {
        { id = "Cosmic", chance = 0.002 },
        { id = "Rainbow", chance = 0.01 },
        { id = "Gold", chance = 0.05 },
    },

    -- Economie
    INCOME_TICK_SECONDS = 1,

    -- Coffres a jouets (maquettes validees : 12 jouets par coffre, 2e coffre a 5 000 tetines)
    CHEST_CAPACITY = 12,
    CHEST_PRICE = 5000,
    MAX_CHESTS = 4,
    -- Taille (studs) d'un coffre dans l'interieur d'une base ; les jouets deposes sont mis a l'echelle de leur coffre.
    CHEST_SIZE = 70,
    -- Temps de chute libre d'un jouet jete dans le coffre avant d'etre fige.
    CHEST_SETTLE_SECONDS = 3,

    -- Boutique : ameliorations (prix valides sur la maquette)
    SHOP_ITEMS = {
        QuietSlippers = { price = 2500, displayName = "Chaussons silencieux" },
        StrongArms = { price = 8000, displayName = "Bras costauds" },
    },
    -- Chaussons silencieux : bruit de deplacement multiplie par ce facteur (mesure en jeu : 26,5 -> 15,9 a 0,6).
    QUIET_SLIPPERS_NOISE = 0.5,
    -- Bras costauds : vitesse en plus en portant, et vitesse seul sur un objet lourd. A +2 (11 -> 13) on ne sentait
    -- rien, on marche a 14 a vide (retour utilisateur « les bonus ne marchent pas »).
    STRONG_ARMS_BONUS = 5,
    STRONG_ARMS_ALONE_SPEED = 10.4,

    -- Furie (idee de l'utilisateur, AbilityService) : sprint tres rapide avec une trainee, mais tres bruyant,
    -- disponible toutes les FURY_COOLDOWN secondes.
    FURY_SECONDS = 3,
    FURY_COOLDOWN = 20,
    FURY_PRICE = 750,
    FURY_SPEED_BONUS = 35,
    -- En plus de la vitesse (déjà comptée jusqu'à x1,5) : environ 43 points sur une Furie depuis le repos.
    FURY_NOISE_MULTIPLIER = 1.2,

    -- Pieges et mini-jeux (EventService)
    -- Chance qu'un jouet qui apparait soit piege (invisible jusqu'a ce qu'on le ramasse).
    TRAP_CHANCE = 0.12,
    -- Temps entre la prise d'un jouet piege et l'explosion.
    TRAP_FUSE_SECONDS = 2.5,
    -- Premier evenement apres le lancement du serveur, puis intervalle aleatoire entre deux evenements.
    EVENT_FIRST_DELAY = 45,
    EVENT_MIN_GAP = 40,
    EVENT_MAX_GAP = 75,
    -- Reveil surprise : le bebe gigote pendant ce temps avant de se reveiller.
    SURPRISE_WARN_SECONDS = 1.5,
    -- « Vite, dans l'ombre ! » : compte a rebours puis regard du bebe.
    SHADOW_COUNTDOWN = 5,
    SHADOW_GLANCE_SECONDS = 2.5,
    -- « Maman arrive ! » : pas dans l'escalier, puis la porte s'ouvre et elle regarde.
    MOM_WARN_SECONDS = 7,
    MOM_LOOK_SECONDS = 5,
    -- Porte ouverte : temps pour sortir de la lumiere avant d'etre vu (la lumiere entre par la porte a l'ouverture).
    -- Couvre aussi la mini-cinematique camera vers la porte (~2,3 s en tout avec l'arrivee de la maman).
    MOM_CATCH_GRACE = 1.6,
    -- Vraies ombres (retour utilisateur « pas des ronds moches ») : pendant qu'elle regarde, la lune passe en lumiere
    -- chaude rasante qui entre par la porte (+X, 22 degres de haut). Heure et latitude trouvees par recherche dans
    -- Studio (Lighting:GetMoonDirection) ; MOM_LIGHT_DIRECTION est la direction obtenue, vers la source.
    MOM_LIGHT_CLOCK = 19.5,
    MOM_LIGHT_LATITUDE = 23,
    MOM_LIGHT_DIRECTION = Vector3.new(0.924, 0.383, -0.009),
    MOM_LIGHT_BRIGHTNESS = 5,
    MOM_LIGHT_COLOR = Color3.fromRGB(255, 196, 130),
    -- Attrape : le joueur est propulse en arriere, loin du berceau, puis se releve.
    -- (a 115 / 70 on volait ~100 studs : « ça ne propulse pas beaucoup », retour utilisateur)
    CATCH_LAUNCH_SPEED = 200,
    CATCH_LAUNCH_UP = 110,
    -- Jouet lâché par bébé, maman, chien ou coup : seule la direction du joueur est reprise.
    TOY_DROP_LAUNCH_SPEED = 32,
    TOY_DROP_LAUNCH_UP = 18,
    TOY_PHYSICS_MAX_DISTANCE = 80,
    CATCH_STUN_SECONDS = 1.4,
    -- apres s'etre releve, court delai avant de pouvoir etre repropulse par la chasse
    CATCH_RECOVER_SECONDS = 0.6,
    -- Au-dela de cette part de la jauge, le bebe « va presque pleurer » (son « Chuuut »).
    NEAR_WAKE_FRACTION = 0.75,

    -- Portage bras leves : le jouet se pose au-dessus de la tete, a la hauteur des doigts.
    CARRY_ABOVE_HEAD = 1.7,
    -- Taille maximale d'un jouet porte (plus grande dimension, studs) : le chateau (20) cachait tout l'ecran.
    -- Le jouet reprend sa taille quand il est pose.
    -- (a 5 / 8, la fusee portee cachait encore une grande partie de l'ecran, teste en jeu)
    CARRY_MAX_SIZE = 4,
    CARRY_MAX_SIZE_HEAVY = 6,
    -- Lancer un jouet (touche F) : vitesse, bruit au lancer et a l'atterrissage, propulsion du joueur touche.
    -- Valeurs pour un jouet de poids 1. Poids = porteurs requis + (plus grande taille au sol - THROW_LIGHT_SIZE) /
    -- THROW_SIZE_PER_WEIGHT, au moins 1 : vitesse divisee par le poids, bruits multiplies par le poids.
    THROW_LIGHT_SIZE = 8,
    THROW_SIZE_PER_WEIGHT = 25,
    THROW_SPEED = 75,
    THROW_UP = 38,
    THROW_NOISE = 18,
    THROW_LAND_NOISE = 10,
    THROW_FLIGHT_SECONDS = 2,
    HIT_LAUNCH_SPEED = 90,
    HIT_LAUNCH_UP = 55,
}

return table.freeze(Tuning)
