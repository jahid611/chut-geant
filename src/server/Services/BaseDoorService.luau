--!strict

--[[
    BaseDoorService
    Portes des bases : entrer dans une base (la pantoufle...) mene a son interieur, un autre
    monde construit sous la chambre, et une porte interieure ramene dans la chambre.

    Une porte est une BasePart taguee "BaseDoor" portant l'attribut Destination (CFrame).
    Toutes les CHECK_SECONDS, le serveur regarde si le HumanoidRootPart d'un joueur est dans le
    volume d'une porte ; si oui (et hors delai), fondu au noir cote client puis deplacement a la
    destination, avec le jouet porte (soude au HumanoidRootPart).

    Pourquoi pas l'evenement Touched : teste en jeu, un joueur qui arrivait dans la pantoufle et
    marchait aussitot vers la sortie (a 8 studs) la touchait pendant le delai anti-rebond ; le contact
    etait ignore et Touched ne se redeclenchait plus tant qu'il restait dessus : joueur bloque.
    La verification par position n'a pas ce defaut.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Zone = require(Shared:WaitForChild("Zone"))

local BaseLockService = require(script.Parent:WaitForChild("BaseLockService"))

-- Arrivee sous ce niveau = interieur d'une base (construits a y = -900) : portes d'entree, refusees pendant un verrou.
local INTERIOR_Y = -400

local DOOR_TAG = "BaseDoor"
local CHECK_SECONDS = 0.2
-- Delai apres un passage : laisse le temps d'arriver et evite de repasser la porte d'arrivee.
local COOLDOWN_SECONDS = 1.2
local FADE_SECONDS = 0.35

local BaseDoorService = {}

local lastUse: { [Player]: number } = {}

local function doors(): { BasePart }
    local list: { BasePart } = {}
    for _, instance in CollectionService:GetTagged(DOOR_TAG) do
        -- Les tags suivent les instances rangees dans ServerStorage : seules les portes du workspace comptent.
        if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
            table.insert(list, instance)
        end
    end
    return list
end

local function pass(player: Player, character: Model, destination: CFrame): ()
    lastUse[player] = os.clock()
    -- Fondu au noir cote client, puis deplacement une fois l'ecran noir (le saut ne se voit pas).
    local remote = Remotes.Get("BaseTransition") :: RemoteEvent
    remote:FireClient(player, FADE_SECONDS)
    task.delay(FADE_SECONDS, function()
        if character.Parent then
            character:PivotTo(destination)
        end
    end)
end

local function check(): ()
    local now = os.clock()
    local list = doors()
    for _, player in Players:GetPlayers() do
        local last: number? = lastUse[player]
        if last and now - last < COOLDOWN_SECONDS + FADE_SECONDS then
            continue
        end
        local character = player.Character
        local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
        if character == nil or humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
            continue
        end
        for _, door in list do
            local destination = door:GetAttribute("Destination")
            if typeof(destination) == "CFrame" and Zone.Contains(door, root.Position) then
                -- Base verrouillee (BaseLockService) : seul son proprietaire entre dans l'interieur ; les autres sont
                -- repousses hors de la porte.
                local owner = if destination.Position.Y < INTERIOR_Y
                    then BaseLockService:LockedOwnerNear(destination.Position)
                    else nil
                if owner and owner ~= player then
                    lastUse[player] = now
                    local away = Vector3.new(root.Position.X - door.Position.X, 0, root.Position.Z - door.Position.Z)
                    local direction = if away.Magnitude > 0.1 then away.Unit else door.CFrame.LookVector
                    character:PivotTo(CFrame.new(root.Position + direction * 10) * root.CFrame.Rotation)
                    local remote = Remotes.Get("StealNotice") :: RemoteEvent
                    remote:FireClient(player, "refused", "Base verrouillée par " .. owner.DisplayName .. " !")
                    break
                end
                pass(player, character, destination)
                break
            end
        end
    end
end

function BaseDoorService:Init(): () end

function BaseDoorService:Start(): ()
    Players.PlayerRemoving:Connect(function(player: Player)
        lastUse[player] = nil
    end)
    task.spawn(function()
        while true do
            task.wait(CHECK_SECONDS)
            check()
        end
    end)
end

return BaseDoorService
