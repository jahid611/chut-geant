--!strict

--[[
    LeaderboardService
    Classements :
    - du serveur : jouets voles cette session et au total, tetines, nuits (rafraichi toutes les 10 s) ;
    - mondial « plus gros voleurs » : OrderedDataStore Progression.LEADERBOARD_STORE (total de jouets voles),
      ecrit et relu toutes les Progression.LEADERBOARD_REFRESH_SECONDS. Sans acces aux DataStores (Studio), il
      reste vide sans erreur.
    Etat publie dans ReplicatedStorage.Classement (StringValue JSON, lu par le menu Classement a l'ouverture) et
    pousse par le remote LeaderboardState. Ajoute aussi « Volés » dans le leaderstats (liste des joueurs).
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local SERVER_REFRESH_SECONDS = 10

type ServerRow = { name: string, userId: number, session: number, total: number, cash: number, nights: number }
type GlobalRow = { name: string, userId: number, total: number }

local LeaderboardService = {}

local sessionStolen: { [Player]: number } = {}
local globalRows: { GlobalRow } = {}
local names: { [number]: string } = {}
local store: OrderedDataStore? = nil
local stateValue: StringValue? = nil

local function serverRows(): { ServerRow }
    local rows: { ServerRow } = {}
    for _, player in Players:GetPlayers() do
        local profile = DataService:Get(player)
        table.insert(rows, {
            name = player.DisplayName,
            userId = player.UserId,
            session = sessionStolen[player] or 0,
            total = if profile then profile.stats.stolen or 0 else 0,
            cash = math.floor(BaseService:GetCash(player)),
            nights = if profile then profile.nights else 0,
        })
    end
    table.sort(rows, function(a, b)
        if a.session ~= b.session then
            return a.session > b.session
        end
        return a.total > b.total
    end)
    return rows
end

local function publish(): ()
    local state = { server = serverRows(), global = globalRows, updatedAt = os.time() }
    local value = stateValue
    if value then
        local ok, encoded = pcall(function()
            return HttpService:JSONEncode(state)
        end)
        if ok then
            value.Value = encoded
        end
    end
    local remote = Remotes.Get("LeaderboardState") :: RemoteEvent
    remote:FireAllClients(state)
    for _, player in Players:GetPlayers() do
        local stats = player:FindFirstChild("leaderstats")
        local stolen = if stats then stats:FindFirstChild("Volés") else nil
        local profile = DataService:Get(player)
        if stolen and stolen:IsA("IntValue") and profile then
            stolen.Value = profile.stats.stolen or 0
        end
    end
end

local function nameOf(userId: number): string
    local cached = names[userId]
    if cached then
        return cached
    end
    local ok, result = pcall(function()
        return Players:GetNameFromUserIdAsync(userId)
    end)
    local name = if ok and typeof(result) == "string" then result else "Joueur " .. userId
    names[userId] = name
    return name
end

local function refreshGlobal(): ()
    local current = store
    if current == nil then
        return
    end
    for _, player in Players:GetPlayers() do
        local profile = DataService:Get(player)
        local total = if profile then profile.stats.stolen or 0 else 0
        if total > 0 then
            pcall(function()
                current:SetAsync("u" .. player.UserId, math.floor(total))
            end)
        end
    end
    local ok, pages = pcall(function()
        return current:GetSortedAsync(false, Progression.LEADERBOARD_TOP)
    end)
    if not ok or typeof(pages) ~= "Instance" then
        return
    end
    local pageOk, entries = pcall(function()
        return (pages :: DataStorePages):GetCurrentPage()
    end)
    if not pageOk or typeof(entries) ~= "table" then
        return
    end
    local rows: { GlobalRow } = {}
    for _, entry in entries do
        local key = if typeof(entry.key) == "string" then entry.key else ""
        local userId = tonumber(string.sub(key, 2))
        if userId and typeof(entry.value) == "number" then
            table.insert(rows, { name = nameOf(userId), userId = userId, total = entry.value })
        end
    end
    globalRows = rows
end

function LeaderboardService:Init(): ()
    local ok, result = pcall(function()
        return DataStoreService:GetOrderedDataStore(Progression.LEADERBOARD_STORE)
    end)
    if ok then
        store = result
    end
    local value = Instance.new("StringValue")
    value.Name = "Classement"
    value.Value = "{}"
    value.Parent = ReplicatedStorage
    stateValue = value
end

function LeaderboardService:Start(): ()
    BaseService.ToyDeposited:Connect(function(player: Player)
        sessionStolen[player] = (sessionStolen[player] or 0) + 1
    end)

    local function onPlayer(player: Player): ()
        local stats = player:WaitForChild("leaderstats", 15)
        if stats and stats:FindFirstChild("Volés") == nil then
            local stolen = Instance.new("IntValue")
            stolen.Name = "Volés"
            stolen.Parent = stats
        end
        publish()
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        sessionStolen[player] = nil
        task.defer(publish)
    end)

    task.spawn(function()
        while true do
            task.wait(SERVER_REFRESH_SECONDS)
            publish()
        end
    end)
    task.spawn(function()
        task.wait(15)
        while true do
            refreshGlobal()
            publish()
            task.wait(Progression.LEADERBOARD_REFRESH_SECONDS)
        end
    end)
end

return LeaderboardService
