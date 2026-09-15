--!strict

--[[
    KitchenService
    Acces a la cuisine (recette tools/scene/build-cuisine.luau) par des trous de souris : parties taguees
    « KitchenDoor » avec les attributs Destination (CFrame d'arrivee) et Direction ("in" | "out").

    Comme BaseDoorService, le serveur regarde toutes les CHECK_SECONDS si le bassin d'un joueur est dans le volume
    d'une porte : fondu au noir (remote BaseTransition) puis deplacement, avec le jouet porte (soude au bassin).
    Entrer demande la Nuit Progression.NIGHT_KITCHEN_UNLOCK (attribut joueur Nights, pose par NightsService) : sinon
    le joueur est repousse et recoit « La cuisine s'ouvre à la Nuit 3 » (remote KitchenNotice, avec un cadenas).

    Attribut joueur « Piece » : "Cuisine" quand son bassin est dans une zone taguee KitchenZone, sinon "Chambre".
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kitchen = require(Shared:WaitForChild("Kitchen"))
local Progression = require(Shared:WaitForChild("Progression"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Zone = require(Shared:WaitForChild("Zone"))

local CHECK_SECONDS = 0.2

local KitchenService = {}

local lastUse: { [Player]: number } = {}
local lastNotice: { [Player]: number } = {}

local function tagged(tag: string): { BasePart }
    local list: { BasePart } = {}
    for _, instance in CollectionService:GetTagged(tag) do
        -- Les tags suivent les instances archivees dans ServerStorage : seules celles du workspace comptent.
        if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
            table.insert(list, instance)
        end
    end
    return list
end

function KitchenService:IsInKitchen(position: Vector3): boolean
    for _, zone in tagged(Kitchen.ZONE_TAG) do
        if Zone.Contains(zone, position) then
            return true
        end
    end
    return false
end

function KitchenService:IsUnlocked(player: Player): boolean
    local nights = player:GetAttribute("Nights")
    return typeof(nights) == "number" and nights >= Progression.NIGHT_KITCHEN_UNLOCK
end

local function pass(player: Player, character: Model, destination: CFrame): ()
    lastUse[player] = os.clock()
    local remote = Remotes.Get("BaseTransition") :: RemoteEvent
    remote:FireClient(player, Kitchen.FADE_SECONDS)
    task.delay(Kitchen.FADE_SECONDS, function()
        if character.Parent then
            character:PivotTo(destination)
        end
    end)
end

-- Cuisine pas encore debloquee : le joueur est repousse hors du trou de souris, message au plus toutes les 3 s.
local function refuse(player: Player, character: Model, root: BasePart, door: BasePart): ()
    local now = os.clock()
    lastUse[player] = now
    local away = Vector3.new(root.Position.X - door.Position.X, 0, root.Position.Z - door.Position.Z)
    local direction = if away.Magnitude > 0.1 then away.Unit else door.CFrame.LookVector
    character:PivotTo(CFrame.new(root.Position + direction * Kitchen.LOCKED_PUSH) * root.CFrame.Rotation)
    local last: number? = lastNotice[player]
    if last == nil or now - last >= Kitchen.LOCKED_NOTICE_SECONDS then
        lastNotice[player] = now
        local remote = Remotes.Get("KitchenNotice") :: RemoteEvent
        remote:FireClient(
            player,
            "locked",
            string.format("La cuisine s'ouvre à la Nuit %d", Progression.NIGHT_KITCHEN_UNLOCK)
        )
    end
end

local function check(): ()
    local now = os.clock()
    local doors = tagged(Kitchen.DOOR_TAG)
    for _, player in Players:GetPlayers() do
        local character = player.Character
        if character == nil then
            continue
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local root = character:FindFirstChild("HumanoidRootPart")
        if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
            continue
        end
        local piece = if KitchenService:IsInKitchen(root.Position) then "Cuisine" else "Chambre"
        if player:GetAttribute("Piece") ~= piece then
            player:SetAttribute("Piece", piece)
        end
        local last: number? = lastUse[player]
        if last and now - last < Kitchen.DOOR_COOLDOWN + Kitchen.FADE_SECONDS then
            continue
        end
        for _, door in doors do
            local destination = door:GetAttribute("Destination")
            if typeof(destination) == "CFrame" and Zone.Contains(door, root.Position) then
                if door:GetAttribute("Direction") == "in" and not KitchenService:IsUnlocked(player) then
                    refuse(player, character, root, door)
                else
                    pass(player, character, destination)
                end
                break
            end
        end
    end
end

function KitchenService:Init(): () end

function KitchenService:Start(): ()
    Players.PlayerRemoving:Connect(function(player: Player)
        lastUse[player] = nil
        lastNotice[player] = nil
    end)
    task.spawn(function()
        while true do
            task.wait(CHECK_SECONDS)
            check()
        end
    end)
end

return KitchenService
