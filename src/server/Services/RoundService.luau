--!strict

-- Cycle collectif en mémoire. Aucun remote entrant ; les possessions et records ne sont jamais réinitialisés.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local EventService = require(script.Parent:WaitForChild("EventService"))
local GiantService = require(script.Parent:WaitForChild("GiantService"))
local PassService = require(script.Parent:WaitForChild("PassService"))
local Rules = require(Shared:WaitForChild("RoundRules"))
local Tuning = require(Shared:WaitForChild("Tuning"))

local RoundService = {}
local phase = "Attente"
local roundId = 0
local revision = 0
local phaseStart = 0
local phaseEnd = 0
local state: Rules.State? = nil
local finale = false
local resultReady = false
local nextPublish = 0

local function ready(player: Player): boolean
    -- Chests est posé après l'initialisation de la monnaie ; Cash seul peut être posé par un autre service.
    return player.Parent == Players and DataService:Get(player) ~= nil and player:GetAttribute("Chests") ~= nil
end

local function readyCount(): number
    local count = 0
    for _, player in Players:GetPlayers() do
        if ready(player) then
            count += 1
        end
    end
    return count
end

local function publish(): ()
    revision += 1
    local current = state
    local rows: { Rules.Entry } = if current then Rules.Rank(current) else {}
    local top = {}
    local ranks: { [number]: number } = {}
    for rank, entry in rows do
        ranks[entry.userId] = rank
        if rank <= Tuning.ROUND_LEADERBOARD_SIZE then
            table.insert(top, { userId = entry.userId, name = entry.name, count = entry.count, rank = rank })
        end
    end
    local goal = if current then current.goal else Rules.Goal(readyCount(), Tuning)
    local total = if current then current.total else 0
    local won = if current then (if current.closed then current.won else total >= goal) else false
    workspace:SetAttribute("MancheId", roundId)
    workspace:SetAttribute("ManchePhase", phase)
    workspace:SetAttribute("MancheDebut", phaseStart)
    workspace:SetAttribute("MancheFin", phaseEnd)
    workspace:SetAttribute("MancheObjectif", goal)
    workspace:SetAttribute("MancheProgression", total)
    workspace:SetAttribute("MancheReussie", won)
    workspace:SetAttribute("MancheBilanPret", resultReady)
    -- Instantané cohérent : le contrôleur ne mélange pas les attributs de deux publications.
    workspace:SetAttribute(
        "MancheClassement",
        HttpService:JSONEncode({
            id = roundId,
            revision = revision,
            phase = phase,
            startsAt = phaseStart,
            endsAt = phaseEnd,
            goal = goal,
            total = total,
            won = won,
            resultReady = resultReady,
            finale = finale,
            rows = top,
        })
    )
    for _, player in Players:GetPlayers() do
        local entry = if current then current.entries[player.UserId] else nil
        player:SetAttribute("MancheId", roundId)
        player:SetAttribute("MancheContribution", if entry then entry.count else 0)
        player:SetAttribute("MancheRang", ranks[player.UserId] or 0)
        player:SetAttribute(
            "ManchePersonnel",
            HttpService:JSONEncode({
                id = roundId,
                revision = revision,
                count = if entry then entry.count else 0,
                rank = ranks[player.UserId] or 0,
                cash = if entry then entry.cash else 0,
                xp = if entry then entry.xp else 0,
            })
        )
    end
    workspace:SetAttribute("MancheRevision", revision)
    nextPublish = workspace:GetServerTimeNow() + Tuning.ROUND_PUBLISH_SECONDS
end

local function setPhase(value: string, now: number, seconds: number): ()
    phase = value
    phaseStart = now
    phaseEnd = now + seconds
end

local function abandon(): ()
    state = nil
    finale = false
    resultReady = false
    setPhase("Attente", workspace:GetServerTimeNow(), 0)
    EventService:SetPaused(false)
    publish()
end

local function beginActive(now: number, seconds: number): ()
    roundId += 1
    state = Rules.New(roundId, now, seconds, readyCount(), Tuning)
    finale = false
    resultReady = false
    setPhase("Active", now, seconds)
    EventService:SetPaused(false)
    publish()
end

local function momAvailable(): boolean
    for _, hinge in CollectionService:GetTagged("MomDoor") do
        local door = hinge.Parent
        local mom = if door then door:FindFirstChild("Maman") else nil
        if hinge:IsA("BasePart") and hinge:IsDescendantOf(workspace) and mom and mom:IsA("Model") then
            return true
        end
    end
    return false
end

local function finish(now: number): ()
    local current = state
    if phase ~= "Active" or current == nil or not Rules.Close(current, roundId, now) then
        return
    end
    -- Figer avant les appels externes : cette manche ne peut plus compter ni se fermer une seconde fois.
    setPhase("Résultat", now, Tuning.ROUND_RESULT_SECONDS)
    EventService:SetPaused(true)
    for _, player in Players:GetPlayers() do
        local entry = current.entries[player.UserId]
        if entry and not entry.paid and ready(player) then
            entry.paid = true
            local cash, xp = Rules.Reward(entry.count, current.won, Tuning)
            BaseService:AddCash(player, cash)
            entry.cash = cash
            PassService:AddXp(player, xp, "manche")
            entry.xp = xp
            DataService:AddStat(player, "roundsPlayed", 1)
            if current.won then
                DataService:AddStat(player, "roundsWon", 1)
            end
            player:SetAttribute(
                "MancheDernierResultat",
                HttpService:JSONEncode({
                    id = roundId,
                    won = current.won,
                    count = entry.count,
                    cash = entry.cash,
                    xp = entry.xp,
                })
            )
        end
    end
    if not current.won and not EventService:IsRunning() and GiantService:GetState() == "Sleeping" then
        if momAvailable() then
            finale = EventService:Trigger("MomComing")
        else
            print("[RoundService] Finale maman indisponible : modèle ou porte absent ; bilan d'échec seul.")
        end
    end
    resultReady = not finale
    -- Avec maman, l'échéance du bilan sera posée après la fin réelle (préavis d'oreille fine compris).
    if finale then
        phaseEnd = 0
    end
    publish()
end

local function step(): ()
    local now = workspace:GetServerTimeNow()
    if #Players:GetPlayers() == 0 then
        if phase ~= "Attente" then
            abandon()
        end
        return
    end
    if phase == "Attente" then
        if readyCount() > 0 then
            setPhase("Préparation", now, Tuning.ROUND_PREPARE_SECONDS)
            publish()
        end
    elseif (phase == "Préparation" or phase == "Pause") and now >= phaseEnd then
        if readyCount() > 0 then
            beginActive(now, Tuning.ROUND_ACTIVE_SECONDS)
        else
            abandon()
        end
    elseif phase == "Active" and now >= phaseEnd then
        finish(now)
    elseif phase == "Résultat" then
        if finale and not EventService:IsRunning() then
            finale = false
            resultReady = true
            phaseEnd = now + Tuning.ROUND_RESULT_SECONDS
            publish()
        elseif resultReady and now >= phaseEnd then
            setPhase("Pause", now, Tuning.ROUND_PAUSE_SECONDS)
            publish()
        end
    end
    if now >= nextPublish then
        publish()
    end
end

-- Banc Studio exclusivement ; abandonne la manche courante sans prime. Jamais exposé par un remote.
function RoundService:DebugStart(seconds: number): boolean
    if
        not RunService:IsStudio()
        or seconds ~= seconds
        or seconds < 1
        or seconds > Tuning.ROUND_ACTIVE_SECONDS
        or readyCount() == 0
        or finale
    then
        return false
    end
    beginActive(workspace:GetServerTimeNow(), seconds)
    return true
end

function RoundService:Init(): ()
    publish()
end

function RoundService:Start(): ()
    BaseService.ToyDeposited:Connect(function(player: Player, _toyId: string, _mutation: string?, source: string?)
        local current = state
        local now = workspace:GetServerTimeNow()
        if phase ~= "Active" or current == nil or not ready(player) then
            return
        end
        if now >= current.endsAt then
            finish(now)
            return
        end
        Rules.Deposit(current, roundId, now, player.UserId, player.DisplayName, source)
    end)
    Players.PlayerRemoving:Connect(function(leaving: Player)
        -- Aucune référence Player conservée ; les contributions restent indexées par UserId.
        for _, player in Players:GetPlayers() do
            if player ~= leaving then
                return
            end
        end
        abandon()
    end)
    task.spawn(function()
        while true do
            step()
            task.wait(Tuning.ROUND_POLL_SECONDS)
        end
    end)
end

return RoundService
