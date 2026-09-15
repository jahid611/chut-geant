--!strict

--[[
    BaseAlertService
    Alerte d'intrusion (idee 24 du carnet docs/IDEES.md) : quand un autre joueur entre dans la base d'un joueur qui
    n'y est pas, le proprietaire est prevenu ou qu'il soit, et peut revenir defendre ses coffres.

    Controle toutes les CHECK_SECONDS : pour chaque joueur, BaseService:GetBaseAt(position) donne la base ou il se
    trouve et son proprietaire. Un meme intrus ne declenche l'alerte chez un meme proprietaire qu'une fois toutes les
    ALERT_COOLDOWN secondes. Le client est prevenu par les attributs du proprietaire AlerteIntrus (nom de l'intrus) et
    AlerteIntrusN (compteur, pour que deux alertes du meme intrus declenchent quand meme le message).
]]

local Players = game:GetService("Players")

local BaseService = require(script.Parent:WaitForChild("BaseService"))

local CHECK_SECONDS = 0.5
local ALERT_COOLDOWN = 30

local BaseAlertService = {}

-- lastAlert[owner][intruder] = os.clock() de la derniere alerte
local lastAlert: { [Player]: { [Player]: number } } = {}

local function rootOf(player: Player): BasePart?
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    return if root and root:IsA("BasePart") then root else nil
end

-- Previent `owner` qu'un intrus nomme `intruderName` est dans sa base (aussi utilise pour tester en solo :
-- BaseAlertService:Alert(game.Players:GetPlayers()[1], "Test")).
function BaseAlertService:Alert(owner: Player, intruderName: string): ()
    local count = owner:GetAttribute("AlerteIntrusN")
    owner:SetAttribute("AlerteIntrus", intruderName)
    owner:SetAttribute("AlerteIntrusN", (if typeof(count) == "number" then count else 0) + 1)
end

local function check(): ()
    local now = os.clock()
    for _, intruder in Players:GetPlayers() do
        local root = rootOf(intruder)
        if root == nil then
            continue
        end
        local base, owner = BaseService:GetBaseAt(root.Position)
        if base == nil or owner == nil or owner == intruder or owner.Parent == nil then
            continue
        end
        -- le proprietaire deja dans sa base voit l'intrus lui-meme : pas d'alerte
        local ownerRoot = rootOf(owner)
        if ownerRoot then
            local ownerBase = BaseService:GetBaseAt(ownerRoot.Position)
            if ownerBase == base then
                continue
            end
        end
        local byIntruder = lastAlert[owner]
        if byIntruder == nil then
            byIntruder = {}
            lastAlert[owner] = byIntruder
        end
        local last = byIntruder[intruder]
        if last and now - last < ALERT_COOLDOWN then
            continue
        end
        byIntruder[intruder] = now
        BaseAlertService:Alert(owner, intruder.DisplayName)
    end
end

function BaseAlertService:Init(): () end

function BaseAlertService:Start(): ()
    Players.PlayerRemoving:Connect(function(player: Player)
        lastAlert[player] = nil
        for _, byIntruder in lastAlert do
            byIntruder[player] = nil
        end
    end)
    task.spawn(function()
        while true do
            task.wait(CHECK_SECONDS)
            check()
        end
    end)
end

return BaseAlertService
