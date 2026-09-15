--!strict

--[[
    BaseLockService
    Verrou de base : le proprietaire verrouille sa base pendant LOCK_SECONDS (recharge COOLDOWN_SECONDS depuis
    l'activation). Pendant le verrou, personne ne peut voler dans ses coffres (StealService) ni entrer dans son
    interieur (BaseDoorService).

    - Pupitre invisible « PupitreVerrou » au centre du sol de chaque base, avec un ProximityPrompt « Verrouiller »
      (attribut OwnerUserId recopie de la base : le client ne l'affiche qu'au proprietaire) ; bouton du HUD
      (StealController) par le remote LockBase.
    - Champ de force rose translucide sur la zone de la base, avec le compte a rebours au-dessus.
    Attributs du joueur (temps serveur) : BaseLockUntil (fin du verrou), BaseLockReadyAt (prochaine utilisation) ;
    attribut LockUntil sur la base.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))

local LOCK_SECONDS = 60
local COOLDOWN_SECONDS = 180
local BASE_TAG = "Base"
local FIELD_NAME = "ChampVerrou"
local DESK_NAME = "PupitreVerrou"
local PROMPT_NAME = "PromptVerrou"
-- Porte d'interieur verrouillee : la base la plus proche de l'arrivee, dans ce rayon.
local INTERIOR_RADIUS = 700

local BaseLockService = {}

local lockedUntil: { [Player]: number } = {}
local fields: { [Player]: BasePart } = {}

local function serverNow(): number
    return workspace:GetServerTimeNow()
end

local function notify(player: Player, message: string): ()
    local remote = Remotes.Get("StealNotice") :: RemoteEvent
    remote:FireClient(player, "notice", message)
end

function BaseLockService:IsLocked(player: Player): boolean
    local untilTime: number? = lockedUntil[player]
    return untilTime ~= nil and untilTime > serverNow()
end

-- Proprietaire d'une base verrouillee proche de cette position (arrivee d'une porte d'interieur), ou nil.
function BaseLockService:LockedOwnerNear(position: Vector3): Player?
    local best: Player? = nil
    local bestDistance = INTERIOR_RADIUS
    for base, owner in BaseService:GetOwnedBases() do
        local distance = (base.Position - position).Magnitude
        if distance < bestDistance then
            bestDistance = distance
            best = if BaseLockService:IsLocked(owner) then owner else nil
        end
    end
    return best
end

local function removeField(player: Player): ()
    local field: BasePart? = fields[player]
    if field then
        field:Destroy()
    end
    fields[player] = nil
end

local function buildField(player: Player, base: BasePart): ()
    removeField(player)
    local field = Instance.new("Part")
    field.Name = FIELD_NAME
    field.Anchored = true
    field.CanCollide = false
    field.CanQuery = false
    field.CanTouch = false
    field.CastShadow = false
    field.Material = Enum.Material.ForceField
    field.Color = Color3.fromRGB(255, 120, 190)
    field.Transparency = 0.15
    field.Size = base.Size + Vector3.new(4, 4, 4)
    field.CFrame = base.CFrame
    field.Parent = workspace

    local board = Instance.new("BillboardGui")
    board.Name = "CompteVerrou"
    board.Adornee = field
    board.Size = UDim2.fromOffset(260, 70)
    board.StudsOffsetWorldSpace = Vector3.new(0, base.Size.Y / 2 + 6, 0)
    board.AlwaysOnTop = true
    board.MaxDistance = 350
    board.LightInfluence = 0
    board.Parent = field
    local label = Instance.new("TextLabel")
    label.Name = "Texte"
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.FredokaOne
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeColor3 = Color3.fromRGB(120, 30, 80)
    label.TextStrokeTransparency = 0
    label.Text = string.format("Verrouillée %d s", LOCK_SECONDS)
    label.Parent = board
    fields[player] = field
end

local function unlock(player: Player): ()
    lockedUntil[player] = nil
    removeField(player)
    if player.Parent then
        player:SetAttribute("BaseLockUntil", nil)
    end
    local base = BaseService:GetBase(player)
    if base then
        base:SetAttribute("LockUntil", nil)
    end
end

function BaseLockService:Lock(player: Player): (boolean, string)
    local base = BaseService:GetBase(player)
    if base == nil then
        return false, "Tu n'as pas encore de base."
    end
    local now = serverNow()
    if BaseLockService:IsLocked(player) then
        return false, "Ta base est déjà verrouillée."
    end
    local readyAt = player:GetAttribute("BaseLockReadyAt")
    if typeof(readyAt) == "number" and readyAt > now then
        return false, string.format("Verrou disponible dans %d s", math.ceil(readyAt - now))
    end
    lockedUntil[player] = now + LOCK_SECONDS
    player:SetAttribute("BaseLockUntil", now + LOCK_SECONDS)
    player:SetAttribute("BaseLockReadyAt", now + COOLDOWN_SECONDS)
    base:SetAttribute("LockUntil", now + LOCK_SECONDS)
    buildField(player, base)
    return true, string.format("Base verrouillée %d s !", LOCK_SECONDS)
end

-- Pupitre et bouton « Verrouiller » d'une base (une seule fois par base).
local function setupDesk(base: Instance): ()
    if not base:IsA("BasePart") or not base:IsDescendantOf(workspace) or base:FindFirstChild(DESK_NAME) then
        return
    end
    local desk = Instance.new("Part")
    desk.Name = DESK_NAME
    desk.Size = Vector3.new(2, 2, 2)
    desk.Transparency = 1
    desk.Anchored = true
    desk.CanCollide = false
    desk.CanQuery = false
    desk.CanTouch = false
    desk.CFrame = base.CFrame * CFrame.new(0, -base.Size.Y / 2 + 3, 0)
    desk.Parent = base
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = PROMPT_NAME
    prompt.ActionText = "Verrouiller"
    prompt.ObjectText = "Ta base"
    prompt.HoldDuration = 0.4
    prompt.MaxActivationDistance = 14
    prompt.RequiresLineOfSight = false
    prompt.KeyboardKeyCode = Enum.KeyCode.L
    prompt.Parent = desk
    local function syncOwner(): ()
        desk:SetAttribute("OwnerUserId", base:GetAttribute("OwnerUserId"))
    end
    base:GetAttributeChangedSignal("OwnerUserId"):Connect(syncOwner)
    syncOwner()
    prompt.Triggered:Connect(function(player: Player)
        if BaseService:GetOwnerOfBase(base) ~= player then
            return
        end
        local _, message = BaseLockService:Lock(player)
        notify(player, message)
    end)
end

function BaseLockService:Init(): () end

function BaseLockService:Start(): ()
    local remote = Remotes.Get("LockBase") :: RemoteEvent
    remote.OnServerEvent:Connect(function(player: Player)
        local _, message = BaseLockService:Lock(player)
        notify(player, message)
    end)

    for _, base in CollectionService:GetTagged(BASE_TAG) do
        setupDesk(base)
    end
    CollectionService:GetInstanceAddedSignal(BASE_TAG):Connect(setupDesk)

    Players.PlayerRemoving:Connect(function(player: Player)
        unlock(player)
    end)

    task.spawn(function()
        while true do
            task.wait(0.5)
            local now = serverNow()
            for player, untilTime in table.clone(lockedUntil) do
                if untilTime <= now or player.Parent == nil then
                    unlock(player)
                    continue
                end
                local field: BasePart? = fields[player]
                local board = if field then field:FindFirstChild("CompteVerrou") else nil
                local label = if board then board:FindFirstChild("Texte") else nil
                if label and label:IsA("TextLabel") then
                    label.Text = string.format("Verrouillée %d s", math.ceil(untilTime - now))
                end
            end
        end
    end)
end

return BaseLockService
