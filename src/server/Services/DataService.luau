--!strict

--[[
    DataService
    Sauvegarde des joueurs (DataStore « ChutGeant_Joueurs_v1 ») : avant ce service, tout etait perdu en quittant.

    Chargement a l'arrivee (3 essais), sauvegarde toutes les AUTOSAVE_SECONDS, au depart et a la fermeture du
    serveur. Si le DataStore est indisponible (Studio sans acces aux API), le joueur joue avec un profil neuf non
    sauvegarde (avertissement dans la sortie).

    Les autres services lisent et modifient directement le profil (DataService:WaitForProfile) ; les compteurs
    passent par AddStat, qui emet StatChanged (quetes, pass de saison, collection s'y abonnent).

    Champs par domaine (chaque service ne touche qu'aux siens) :
    - BaseService / ShopService : cash, chests, goldChests, toys, owned, equipped ;
    - quetes, recompenses du jour, pass : quests, daily, pass ;
    - collection et Nuits (renaissance) : collection, nights ;
    - stats : compteurs libres (stolen, caught, thrown, events, playSeconds...).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local STORE_NAME = "ChutGeant_Joueurs_v1"
local AUTOSAVE_SECONDS = 60
local LOAD_TIMEOUT = 20

export type OwnedToy = { id: string, mutation: string? }

export type Profile = {
    version: number,
    cash: number,
    chests: number,
    goldChests: number,
    toys: { OwnedToy },
    -- jouets ranges dans le tipi (TentService, 3 au plus)
    tentToys: { OwnedToy },
    owned: { [string]: number },
    equipped: { [string]: string },
    stats: { [string]: number },
    quests: { [string]: any },
    daily: { [string]: any },
    pass: { [string]: any },
    collection: { [string]: boolean },
    nights: number,
    firstJoin: number,
    -- niveau du joueur (LevelService) : xp = XP accumulee dans le niveau en cours
    level: number,
    xp: number,
    -- tutoriel des nouveaux joueurs (TutorialService) : etape en cours, fini ou passe
    tutorial: { step: number, done: boolean, bonusGiven: boolean?, purchased: boolean? },
    -- reglages du joueur (menu Parametres, SettingsService) et codes cadeaux deja utilises (CodeService)
    settings: { [string]: any },
    codes: { [string]: boolean },
}

local DataService = {}

local statChanged = Instance.new("BindableEvent")
-- (player: Player, key: string, total: number, added: number)
DataService.StatChanged = statChanged.Event

local profiles: { [Player]: Profile } = {}
local loaded: { [Player]: BindableEvent } = {}
local saveable: { [Player]: boolean } = {}
local store: DataStore? = nil

local function defaultProfile(): Profile
    return {
        version = 1,
        cash = 0,
        chests = 1,
        goldChests = 0,
        toys = {},
        tentToys = {},
        owned = {},
        equipped = {},
        stats = {},
        quests = {},
        daily = {},
        pass = {},
        collection = {},
        nights = 0,
        firstJoin = os.time(),
        level = 1,
        xp = 0,
        tutorial = { step = 1, done = false },
        settings = {},
        codes = {},
    }
end

-- Complete un profil sauvegarde avec les champs ajoutes depuis.
local function reconcile(data: any): Profile
    local profile = defaultProfile()
    if typeof(data) ~= "table" then
        return profile
    end
    for key, value in data do
        if (profile :: any)[key] ~= nil and typeof(value) == typeof((profile :: any)[key]) then
            (profile :: any)[key] = value
        end
    end
    return profile
end

local function keyOf(player: Player): string
    return "joueur_" .. player.UserId
end

local function load(player: Player): ()
    local profile = defaultProfile()
    local ok = false
    local currentStore = store
    if currentStore then
        for attempt = 1, 3 do
            local success, result = pcall(function()
                return currentStore:GetAsync(keyOf(player))
            end)
            if success then
                profile = reconcile(result)
                ok = true
                break
            end
            warn(string.format("[DataService] chargement de %s, essai %d : %s", player.Name, attempt, tostring(result)))
            task.wait(attempt)
        end
    end
    if not ok then
        warn(
            string.format(
                "[DataService] profil de %s non sauvegarde cette session (DataStore indisponible)",
                player.Name
            )
        )
    end
    saveable[player] = ok
    profiles[player] = profile
    local signal = loaded[player]
    if signal then
        signal:Fire()
    end
end

function DataService:Save(player: Player): boolean
    local profile: Profile? = profiles[player]
    local currentStore = store
    if profile == nil or currentStore == nil or not saveable[player] then
        return false
    end
    local success, err = pcall(function()
        currentStore:UpdateAsync(keyOf(player), function()
            return profile
        end)
    end)
    if not success then
        warn(string.format("[DataService] sauvegarde de %s : %s", player.Name, tostring(err)))
    end
    return success
end

-- Profil du joueur s'il est charge.
function DataService:Get(player: Player): Profile?
    return profiles[player]
end

-- Attend le chargement du profil (nil si le joueur part avant ou apres LOAD_TIMEOUT secondes).
function DataService:WaitForProfile(player: Player): Profile?
    local existing: Profile? = profiles[player]
    if existing then
        return existing
    end
    if (loaded[player] :: BindableEvent?) == nil then
        loaded[player] = Instance.new("BindableEvent")
    end
    local started = os.clock()
    while profiles[player] == nil and player.Parent and os.clock() - started < LOAD_TIMEOUT do
        task.wait(0.1)
    end
    return profiles[player]
end

-- Ajoute a un compteur du profil et previent les abonnes (quetes, pass...).
function DataService:AddStat(player: Player, key: string, amount: number): ()
    local profile: Profile? = profiles[player]
    if profile == nil or amount == 0 then
        return
    end
    local total = (profile.stats[key] or 0) + amount
    profile.stats[key] = total
    statChanged:Fire(player, key, total, amount)
end

function DataService:Init(): ()
    local ok, result = pcall(function()
        return DataStoreService:GetDataStore(STORE_NAME)
    end)
    if ok then
        store = result
    else
        warn("[DataService] DataStore inaccessible : " .. tostring(result))
    end
end

function DataService:Start(): ()
    local function onPlayer(player: Player): ()
        if (loaded[player] :: BindableEvent?) == nil then
            loaded[player] = Instance.new("BindableEvent")
        end
        task.spawn(load, player)
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        onPlayer(player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        DataService:Save(player)
        profiles[player] = nil
        saveable[player] = nil
        local signal = loaded[player]
        if signal then
            signal:Destroy()
        end
        loaded[player] = nil
    end)
    game:BindToClose(function()
        for _, player in Players:GetPlayers() do
            DataService:Save(player)
        end
    end)
    task.spawn(function()
        while true do
            task.wait(AUTOSAVE_SECONDS)
            for player in profiles do
                DataService:AddStat(player, "playSeconds", AUTOSAVE_SECONDS)
                task.spawn(function()
                    DataService:Save(player)
                end)
            end
        end
    end)
end

return DataService
