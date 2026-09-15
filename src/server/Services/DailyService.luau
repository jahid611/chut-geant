--!strict

--[[
    DailyService
    Cadeaux du jour (Shared/Retention) :
    - connexion : recompense qui grandit chaque jour d'affilee (7 jours, le 7e = gros cadeau), serie remise a 1 si
      un jour est manque ; au-dela du 7e jour, la serie recommence au jour 1 ;
    - roue quotidienne gratuite : un tour par jour, 8 cases (tetines, XP de pass, recharge des pouvoirs).
    Jours en UTC ; un joueur connecte a minuit passe au jour suivant (verifie toutes les 30 s).

    Profil : daily = { lastLoginDay, streak, claimedDay, wheelDay }.
    Client : attributs Daily_Streak, Daily_LoginClaimable, Daily_WheelReady, Daily_ResetAt ; pastille
    Notif_Cadeaux. DailyReward ("login" | "wheel") -> (ok, message, { index = case de la roue }?).
    Recharge : efface les attributs du joueur qui finissent par « ReadyAt » (FuryReadyAt... d'AbilityService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Retention = require(Shared:WaitForChild("Retention"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local PassService = require(script.Parent:WaitForChild("PassService"))

type DailyData = { lastLoginDay: number, streak: number, claimedDay: number, wheelDay: number }

local DailyService = {}

local random = Random.new()

local function formatNumber(value: number): string
    local digits = tostring(math.floor(math.abs(value)))
    local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1 ")))
    return (string.gsub(grouped, "^ ", ""))
end

local function dataOf(profile: DataService.Profile): DailyData
    local raw = profile.daily :: any
    for _, field in { "lastLoginDay", "streak", "claimedDay", "wheelDay" } do
        if typeof(raw[field]) ~= "number" then
            raw[field] = if field == "streak" then 0 else -1
        end
    end
    return raw :: DailyData
end

local function today(): number
    return Retention.DayNumber(os.time())
end

-- Nouveau jour de connexion : la serie continue si le joueur etait la hier, sinon elle repart a 1.
local function registerLogin(data: DailyData): boolean
    local day = today()
    if data.lastLoginDay == day then
        return false
    end
    if data.lastLoginDay == day - 1 then
        data.streak = data.streak % #Retention.LOGIN_CASH + 1
    else
        data.streak = 1
    end
    data.lastLoginDay = day
    return true
end

local function publish(player: Player, data: DailyData): ()
    local day = today()
    local now = os.time()
    local loginClaimable = data.claimedDay ~= day
    local wheelReady = data.wheelDay ~= day
    player:SetAttribute("Daily_Streak", data.streak)
    player:SetAttribute("Daily_LoginClaimable", loginClaimable)
    player:SetAttribute("Daily_WheelReady", wheelReady)
    player:SetAttribute("Daily_ResetAt", now + Retention.SecondsToNextDay(now))
    player:SetAttribute("Notif_Cadeaux", loginClaimable or wheelReady)
end

function DailyService:ClaimLogin(player: Player): (boolean, string)
    local profile = DataService:Get(player)
    if profile == nil then
        return false, "Ton profil charge encore, réessaie."
    end
    local data = dataOf(profile)
    registerLogin(data)
    if data.claimedDay == today() then
        return false, "Déjà récupéré aujourd'hui, reviens demain !"
    end
    local streak = math.clamp(data.streak, 1, #Retention.LOGIN_CASH)
    local cash = Retention.LOGIN_CASH[streak]
    data.claimedDay = today()
    BaseService:AddCash(player, cash)
    local message = string.format("Jour %d : +%s tétines !", streak, formatNumber(cash))
    if streak == #Retention.LOGIN_CASH then
        PassService:AddXp(player, Retention.LOGIN_DAY7_XP)
        message =
            string.format("Jour %d : +%s tétines et +%d XP !", streak, formatNumber(cash), Retention.LOGIN_DAY7_XP)
    end
    publish(player, data)
    return true, message
end

function DailyService:SpinWheel(player: Player): (boolean, string, { index: number }?)
    local profile = DataService:Get(player)
    if profile == nil then
        return false, "Ton profil charge encore, réessaie.", nil
    end
    local data = dataOf(profile)
    if data.wheelDay == today() then
        return false, "Reviens demain pour un nouveau tour !", nil
    end
    local totalWeight = 0
    for _, slot in Retention.WHEEL do
        totalWeight += slot.weight
    end
    local roll = random:NextNumber(0, totalWeight)
    local index = #Retention.WHEEL
    for i, slot in Retention.WHEEL do
        roll -= slot.weight
        if roll <= 0 then
            index = i
            break
        end
    end
    local slot = Retention.WHEEL[index]
    data.wheelDay = today()

    local message: string
    if slot.kind == "cash" then
        BaseService:AddCash(player, slot.amount)
        message = string.format("Roue : +%s tétines !", formatNumber(slot.amount))
    elseif slot.kind == "xp" then
        PassService:AddXp(player, slot.amount)
        message = string.format("Roue : +%d XP de pass !", slot.amount)
    else
        for name in player:GetAttributes() do
            if string.sub(name, -7) == "ReadyAt" then
                player:SetAttribute(name, nil)
            end
        end
        message = "Roue : tous tes pouvoirs sont rechargés !"
    end
    publish(player, data)
    return true, message, { index = index }
end

function DailyService:Init(): () end

function DailyService:Start(): ()
    local remote = Remotes.Get("DailyReward") :: RemoteFunction
    remote.OnServerInvoke = function(player: Player, kind: any)
        if kind == "login" then
            local ok, message = DailyService:ClaimLogin(player)
            return ok, message, nil
        elseif kind == "wheel" then
            return DailyService:SpinWheel(player)
        end
        return false, "Requête invalide.", nil
    end

    local function onPlayer(player: Player): ()
        local profile = DataService:WaitForProfile(player)
        if profile == nil then
            return
        end
        local data = dataOf(profile)
        registerLogin(data)
        publish(player, data)
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end

    task.spawn(function()
        while true do
            task.wait(30)
            for _, player in Players:GetPlayers() do
                local profile = DataService:Get(player)
                if profile then
                    local data = dataOf(profile)
                    registerLogin(data)
                    publish(player, data)
                end
            end
        end
    end)
end

return DailyService
