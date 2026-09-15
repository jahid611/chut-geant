--!strict

--[[
    Remotes
    Point de declaration unique de tous les RemoteEvent et RemoteFunction.

    Le serveur cree les instances, le client les attend.
    Regle absolue : tout ce qui arrive du client est valide cote serveur.
    Aucune donnee client n'est traitee sans verification de type et de bornes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_FOLDER_NAME = "Remotes"

-- Nom -> type d'instance a creer.
local DECLARATIONS: { [string]: string } = {
    -- Serveur -> clients : (noise: number, max: number) niveau de bruit de la chambre.
    NoiseState = "RemoteEvent",
    -- Serveur -> clients : (state: string, endsAt: number) "Sleeping" | "Waking" | "Hunting",
    -- endsAt en temps serveur (workspace:GetServerTimeNow()).
    GiantState = "RemoteEvent",
    -- Serveur -> client : (reason: string, launch: Vector3) le joueur vient d'etre attrape ; le client le propulse
    -- avec cette vitesse (son personnage est simule chez lui). reason : "moved" | "seen" | "mom".
    Caught = "RemoteEvent",
    -- Serveur -> clients : (kind: string, phase: string, endsAt: number) mini-jeu en cours.
    -- kind : "SurpriseWake" | "ShadowRun" | "MomComing" ; phase : "warn" | "open" | "end".
    RoomEvent = "RemoteEvent",
    -- Serveur -> client : (seconds: number) le jouet que le joueur vient de ramasser est piege.
    TrapArmed = "RemoteEvent",
    -- Client -> serveur : (action: string, direction: Vector3) "drop" pose le jouet porte sans bruit devant soi,
    -- "throw" le lance dans la direction (camera), avec du bruit ; le serveur verifie tout.
    ToyAction = "RemoteEvent",
    -- Serveur -> clients : (position: Vector3) un jouet piege vient d'exploser.
    TrapExploded = "RemoteEvent",
    -- Serveur -> client : (chests: number, capacity: number, price: number, canBuy: boolean) tous les coffres du joueur
    -- sont pleins, le jouet porte ne peut pas etre depose.
    ChestFull = "RemoteEvent",
    -- Client -> serveur (RemoteFunction) : (itemId: string) -> (ok: boolean, message: string). itemId = "Chest",
    -- "QuietSlippers" ou "StrongArms". Le serveur verifie le prix, le solde et les limites.
    BuyItem = "RemoteFunction",
    -- Serveur -> client : (seconds: number) le joueur passe une porte de base ; fondu au noir puis retour de l'image.
    BaseTransition = "RemoteEvent",
    -- Client -> serveur : (abilityId: string) utiliser un pouvoir actif ("Fury"). Le serveur verifie la recharge ;
    -- l'etat est publie en attributs du joueur (FuryUntil, FuryReadyAt, en temps serveur).
    UseAbility = "RemoteEvent",
    -- Serveur -> clients : (abilityId: string, userId: number, position: Vector3) effet visible d'un pouvoir.
    AbilityCast = "RemoteEvent",
    -- Client -> serveur (RemoteFunction) : (itemId: string) -> (ok: boolean, message: string) equiper un cosmetique
    -- possede (trainee, contour, skin) ; possession et equipement publies en attributs Owned_<id>, Equipped_<slot>.
    EquipCosmetic = "RemoteFunction",
    -- Client -> serveur : (danceId: string) lancer une danse possedee ; le serveur pose l'attribut Dancing du joueur.
    Dance = "RemoteEvent",
    -- Serveur -> client : (state: table) quetes du jour et de la semaine ; client -> serveur (RemoteFunction)
    -- ClaimQuest (questId) -> (ok, message).
    QuestState = "RemoteEvent",
    ClaimQuest = "RemoteFunction",
    -- Client -> serveur (RemoteFunction) : (kind: "login" | "wheel") -> (ok, message, reward: table?).
    DailyReward = "RemoteFunction",
    -- Serveur -> client : (state: table) pass de saison ; ClaimPass (tier: number, premium: boolean) -> (ok, message).
    PassState = "RemoteEvent",
    ClaimPass = "RemoteFunction",
    -- Serveur -> client : (state: table) collection des jouets deja voles et bonus de sets.
    CollectionState = "RemoteEvent",
    -- Client -> serveur (RemoteFunction) : () -> (ok, message) Nuits : renaissance contre un multiplicateur.
    Rebirth = "RemoteFunction",
    -- Serveur -> clients : (phase: "start" | "end", endsAt: number) evenement Pleine lune.
    MoonEvent = "RemoteEvent",
    -- Serveur -> clients : (rows: table) classements du serveur (plus gros voleur, tetines).
    LeaderboardState = "RemoteEvent",
    -- Serveur -> client : (velocity: Vector3) rebond de trampoline a appliquer au personnage (TrampolineService).
    Bounce = "RemoteEvent",
    -- Client -> serveur : (direction: Vector3) coup de l'arme equipee (WeaponService verifie cadence, portee, cone).
    WeaponSwing = "RemoteEvent",
    -- Serveur -> clients : (weaponId: string, attackerUserId: number, targetUserId: number, position: Vector3) coup
    -- qui a touche (son et etincelle cote client).
    WeaponHit = "RemoteEvent",
    -- Client -> serveur : (action: "next" | "skip" | "close" | "restart") tutoriel des nouveaux joueurs (TutorialService,
    -- « restart » : rejouer depuis le menu Parametres) ; l'etape en
    -- cours est publiee en attributs du joueur (TutorialStep, TutorialDone, TutorialTarget).
    TutorialAction = "RemoteEvent",
    -- Serveur -> client : (kind: string, a: any?, b: any?) vol entre joueurs et verrou de base (StealService,
    -- BaseLockService). kind : "robbed" (voleurNom, positionCoffre) | "stealing" (victimeNom) | "success" (xp)
    -- | "dropped" | "returned" | "lost" (voleurNom) | "refused" (texte) | "notice" (texte).
    StealNotice = "RemoteEvent",
    -- Client -> serveur : () verrouiller sa base 60 s (bouton du HUD ; le pupitre de la base fait pareil).
    LockBase = "RemoteEvent",
    -- Client -> serveur : (emoteId: string) emote rapide de la roue (EmoteService, anti-spam 2 s) ;
    -- serveur -> clients : (userId: number, emoteId: string) bulle au-dessus de la tete et petit geste.
    Emote = "RemoteEvent",
    -- Serveur -> clients : (message: table) fil d'actualite du serveur (FeedService) :
    -- { icon, fallback, before, accent, after, color: Color3? }.
    Feed = "RemoteEvent",
    -- Client -> serveur : (key: string, value: number | boolean) reglage du menu Parametres (SettingsService) ;
    -- publie en attributs du joueur ReglageMusique, ReglageEffets, ReglageNoms, EffetsReduits.
    Settings = "RemoteEvent",
    -- Client -> serveur (RemoteFunction) : (code: string) -> (ok: boolean, message: string, icon: string) code cadeau
    -- (CodeService, une fois par joueur, 5 essais par minute).
    RedeemCode = "RemoteFunction",
    -- Client -> serveur (RemoteFunction) : ("claim") -> (ok: boolean, recompense { cash, xp, cosmetic? } | message)
    -- coffre de retour apres 24 h d'absence (WelcomeBackService ; attributs WelcomeBackTier, WelcomeBackHours).
    WelcomeBack = "RemoteFunction",
    -- Serveur -> client : ("win", { title, cash, xp, badge, wins }) | ("fail", raison) | ("info", message) defi
    -- chronometre de la plaque DÉFI (ChallengeService ; attributs Challenge*).
    ChallengeResult = "RemoteEvent",
    -- Serveur -> clients : (noise: number, max: number, state: "Sleeping" | "Growling" | "Hunting", endsAt: number)
    -- jauge et etat du chien de la cuisine (DogService).
    DogState = "RemoteEvent",
    -- Serveur -> client : (kind: "locked" | "caught", text: string) messages de la cuisine (KitchenService,
    -- DogService) : cuisine pas encore debloquee, ou « OUAF ! » quand le chien attrape le joueur.
    KitchenNotice = "RemoteEvent",
    -- Serveur -> client(s) : mission du jour de la tetine (PacifierMissionService) : au joueur ("refused", texte) ou
    -- ("win", { cash, xp, cosmetic? }) ; a tous ("stolen", nom, userId).
    PacifierMission = "RemoteEvent",
    -- Serveur -> joueurs de la cuisine : (kind: "FridgeLight" | "BowlCrash" | "DogDream", phase: "warn" | "start" |
    -- "lit" | "end", endsAt: number) evenements propres a la cuisine (KitchenEventService, KitchenEventController).
    KitchenEvent = "RemoteEvent",
    -- Client -> serveur (RemoteFunction) : (toyId: string) -> (ok: boolean) prepare l'apercu 3D d'un jouet sans image
    -- dans ReplicatedStorage.ApercusJouets.<toyId> (ToyPreviewService), pour la collection.
    ToyPreview = "RemoteFunction",
    -- Serveur -> client : ("survived", cash: number, xp: number) le joueur a echappe a la main geante (HandChaseService).
    ChaseNotice = "RemoteEvent",
}

local Remotes = {}

local function getFolder(): Folder
    if RunService:IsServer() then
        local existing = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
        if existing and existing:IsA("Folder") then
            return existing
        end
        local folder = Instance.new("Folder")
        folder.Name = REMOTE_FOLDER_NAME
        folder.Parent = ReplicatedStorage
        return folder
    end
    return ReplicatedStorage:WaitForChild(REMOTE_FOLDER_NAME) :: Folder
end

--[[
    A appeler une seule fois, depuis Main.server.luau, avant le demarrage des services.
]]
function Remotes.Init(): ()
    assert(RunService:IsServer(), "Remotes.Init can only be called on the server")
    local folder = getFolder()
    for name, className in DECLARATIONS do
        if not folder:FindFirstChild(name) then
            local instance = Instance.new(className)
            instance.Name = name
            instance.Parent = folder
        end
    end
end

--[[
    Recupere un remote par son nom. Le client attend qu'il soit replique.
]]
function Remotes.Get(name: string): Instance
    local folder = getFolder()
    if RunService:IsServer() then
        local remote = folder:FindFirstChild(name)
        assert(remote ~= nil, string.format("Remote inconnu : %s", name))
        return remote
    end
    return folder:WaitForChild(name)
end

return Remotes
