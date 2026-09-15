--!strict

--[[
    DogService
    Le chien de la famille garde la cuisine. Il a SA jauge de bruit, independante de NoiseService (qui reste celle de
    la chambre et du bebe). Elle monte avec :
    - les deplacements dans la cuisine (meme formule que la chambre, x Kitchen.TILE_NOISE_FACTOR : le carrelage
      resonne), chaussons silencieux et poids du jouet porte compris ;
    - les atterrissages apres un saut ;
    - les jouets lances qui volent dans la cuisine.
    Elle redescend doucement quand tout le monde se tait.

    Pleine : le chien grogne (Kitchen.GROWL_SECONDS, le temps de s'immobiliser), puis chasse (Kitchen.HUNT_SECONDS) :
    tout joueur de la cuisine qui bouge ou saute est attrape (il lache son jouet et part vers le trou de souris de
    sortie), puis le chien se rendort et la jauge revient a zero. Cape d'ombre et doudou bouclier protegent comme
    contre le bebe.

    Etat publie : attributs State / EndsAt sur le modele workspace.Cuisine.Chien, et remote DogState
    (noise, max, state, endsAt) pour les joueurs. Un attrape envoie Caught avec la raison "dog" (EventController :
    « OUAF ! » au-dessus du joueur, sans l'onde du cri du bebe) et KitchenNotice « caught » (« OUAF ! » a l'ecran).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local Kitchen = require(Shared:WaitForChild("Kitchen"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))
local Tuning = require(Shared:WaitForChild("Tuning"))
local Zone = require(Shared:WaitForChild("Zone"))

local CarryService = require(script.Parent:WaitForChild("CarryService"))
local KitchenService = require(script.Parent:WaitForChild("KitchenService"))

export type DogState = "Sleeping" | "Growling" | "Hunting"

local TICK_SECONDS = 0.2
local ANIM_SECONDS = 1 / 15
-- Vitesse maximale a laquelle le chien tourne la tete vers un joueur pendant la chasse (radians par seconde).
local TURN_SPEED = 3

local DogService = {}

local noise = 0
local state: DogState = "Sleeping"
local endsAt = 0
local wakeToken = 0
local caughtAt: { [Player]: number } = {}
local lastPositions: { [Player]: Vector3 } = {}
local landingConnections: { [Player]: RBXScriptConnection } = {}

local function dogModel(): Model?
    local kitchen = workspace:FindFirstChild("Cuisine")
    local dog = if kitchen then kitchen:FindFirstChild(Kitchen.DOG_NAME) else nil
    return if dog and dog:IsA("Model") then dog else nil
end

-- Changement d'etat : tout le monde ; rafraichissement periodique de la jauge : seulement les joueurs dans la cuisine
-- (evite de remplir la file des clients qui n'ont pas encore branche leur ecouteur).
local function broadcast(toAll: boolean?): ()
    local remote = Remotes.Get("DogState") :: RemoteEvent
    if toAll then
        remote:FireAllClients(noise, Kitchen.NOISE_MAX, state, endsAt)
        return
    end
    for _, player in Players:GetPlayers() do
        if player:GetAttribute("Piece") == "Cuisine" then
            remote:FireClient(player, noise, Kitchen.NOISE_MAX, state, endsAt)
        end
    end
end

local function setState(newState: DogState, duration: number): ()
    state = newState
    endsAt = if duration > 0 then workspace:GetServerTimeNow() + duration else 0
    local dog = dogModel()
    if dog then
        dog:SetAttribute("State", newState)
        dog:SetAttribute("EndsAt", endsAt)
    end
    broadcast(true)
end

local function rootOf(player: Player): (BasePart?, Humanoid?)
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
    if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
        return root, humanoid
    end
    return nil, nil
end

-- Centre du trou de souris de sortie (vers lequel le chien envoie les joueurs attrapes).
local function exitPosition(): Vector3?
    for _, door in CollectionService:GetTagged(Kitchen.DOOR_TAG) do
        if door:IsA("BasePart") and door:IsDescendantOf(workspace) and door:GetAttribute("Direction") == "out" then
            return door.Position
        end
    end
    return nil
end

local function wake(): ()
    if state ~= "Sleeping" then
        return
    end
    wakeToken += 1
    local token = wakeToken
    noise = Kitchen.NOISE_MAX
    setState("Growling", Kitchen.GROWL_SECONDS)
    task.delay(Kitchen.GROWL_SECONDS, function()
        if token ~= wakeToken then
            return
        end
        table.clear(lastPositions)
        setState("Hunting", Kitchen.HUNT_SECONDS)
        task.delay(Kitchen.HUNT_SECONDS, function()
            if token ~= wakeToken then
                return
            end
            noise = 0
            setState("Sleeping", 0)
        end)
    end)
end

-- Ajoute du bruit a la jauge du chien (sans effet s'il ne dort pas).
function DogService:Add(amount: number): ()
    if state ~= "Sleeping" or amount <= 0 then
        return
    end
    noise = math.min(noise + amount, Kitchen.NOISE_MAX)
    if noise >= Kitchen.NOISE_MAX then
        wake()
    end
end

-- Etat, jauge et fin de l'etat en cours (temps serveur, 0 s'il dort).
function DogService:GetState(): (DogState, number, number)
    return state, noise, endsAt
end

-- Reveil immediat (tests en jeu).
function DogService:Wake(): ()
    noise = Kitchen.NOISE_MAX
    wake()
end

local function catch(player: Player, root: BasePart): ()
    if Abilities.IsActive(player, "ShadowCape") then
        return
    end
    local now = os.clock()
    local last: number? = caughtAt[player]
    if last and now - last < Tuning.CATCH_STUN_SECONDS + 0.5 then
        return
    end
    caughtAt[player] = now
    if Abilities.ConsumeShield(player) then
        return
    end
    CarryService:Drop(player, true)
    local exit = exitPosition()
    local toward = if exit then exit - root.Position else -root.CFrame.LookVector
    local flat = Vector3.new(toward.X, 0, toward.Z)
    local direction = if flat.Magnitude > 1 then flat.Unit else Vector3.new(0, 0, 1)
    local launch = direction * Tuning.CATCH_LAUNCH_SPEED * Kitchen.LAUNCH_FACTOR
        + Vector3.new(0, Tuning.CATCH_LAUNCH_UP * Kitchen.LAUNCH_FACTOR, 0)
    local caught = Remotes.Get("Caught") :: RemoteEvent
    caught:FireClient(player, "dog", launch)
    local notice = Remotes.Get("KitchenNotice") :: RemoteEvent
    notice:FireClient(player, "caught", "OUAF !")
end

-- Attrape un joueur de la cuisine (comme GiantService:Catch) : sert aussi aux tests en jeu, le banc de test ne sachant
-- pas simuler les commandes (MoveDirection) d'un vrai joueur.
function DogService:Catch(player: Player): ()
    local root = rootOf(player)
    if root then
        catch(player, root)
    end
end

local function movementNoise(dt: number): number
    local gain = 0
    for _, player in Players:GetPlayers() do
        local root = rootOf(player)
        if root == nil or not KitchenService:IsInKitchen(root.Position) then
            continue
        end
        local velocity = root.AssemblyLinearVelocity
        local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
        if speed <= Tuning.SNEAK_SPEED then
            continue
        end
        local fraction =
            math.clamp((speed - Tuning.SNEAK_SPEED) / math.max(Tuning.WALK_SPEED - Tuning.SNEAK_SPEED, 1), 0, 1.5)
        local toy = CarryService:GetCarried(player)
        local toyId = if toy then toy:GetAttribute("ToyId") else nil
        local def = if typeof(toyId) == "string" then Toys.Get(toyId) else nil
        local quiet = math.max(1 - 0.1 * Abilities.Level(player, "QuietSlippers"), 0.4)
        gain += fraction * Tuning.DOG_NOISE_MOVE_PER_SECOND * (if def then def.carriers else 1) * quiet * Kitchen.TILE_NOISE_FACTOR * dt
    end
    return gain
end

-- Jouets lances qui volent dans la cuisine (les jouets portes, soudes au joueur, sont exclus).
local function thrownToysNoise(dt: number): number
    local live = workspace:FindFirstChild("ToysLive")
    if live == nil then
        return 0
    end
    local gain = 0
    for _, toy in live:GetChildren() do
        if toy:GetAttribute("CarrierUserId") ~= nil then
            continue
        end
        local primary = Zone.PrimaryPart(toy)
        if
            primary
            and not primary.Anchored
            and primary.AssemblyLinearVelocity.Magnitude > Kitchen.THROWN_TOY_SPEED
            and KitchenService:IsInKitchen(primary.Position)
        then
            gain += Kitchen.THROWN_TOY_NOISE_PER_SECOND * dt
        end
    end
    return gain
end

-- Pendant la chasse : attrape ceux qui bougent vraiment ou sautent (meme regle que le bebe, GiantService).
local function huntTick(elapsed: number): ()
    local now = os.clock()
    for _, player in Players:GetPlayers() do
        local root, humanoid = rootOf(player)
        if root == nil or humanoid == nil or not KitchenService:IsInKitchen(root.Position) then
            lastPositions[player] = nil
            continue
        end
        local previous: Vector3? = lastPositions[player]
        lastPositions[player] = root.Position
        local last: number? = caughtAt[player]
        if last then
            local since = now - last
            local airborne = humanoid.FloorMaterial == Enum.Material.Air
            if since < Tuning.CATCH_STUN_SECONDS + Tuning.CATCH_RECOVER_SECONDS or (airborne and since < 6) then
                continue
            end
        end
        if previous == nil then
            continue
        end
        local humanoidState = humanoid:GetState()
        if
            humanoidState == Enum.HumanoidStateType.GettingUp
            or humanoidState == Enum.HumanoidStateType.PlatformStanding
            or humanoidState == Enum.HumanoidStateType.Ragdoll
            or humanoidState == Enum.HumanoidStateType.FallingDown
        then
            continue
        end
        local delta = root.Position - previous
        local moved = humanoid.MoveDirection.Magnitude > 0.1
            and Vector3.new(delta.X, 0, delta.Z).Magnitude > Kitchen.FREEZE_SPEED * elapsed
        local jumped = humanoidState == Enum.HumanoidStateType.Jumping
            or (delta.Y > Kitchen.JUMP_RISE and humanoid.Jump)
        if moved or jumped then
            catch(player, root)
        end
    end
end

--[[
    Animation procedurale du chien (modele d'une piece) autour de son pivot de repos, pose par la recette au pied du
    modele, regard (LookVector) vers la tete :
    - il dort : respiration (le corps monte et descend doucement) ;
    - il grogne : il se redresse, tete levee, et tremble ;
    - il chasse : redresse, tete levee, il se tourne vers le joueur de la cuisine le plus proche.
]]
local animDog: Model? = nil
local restPivot = CFrame.identity
local restHeight = 1
local lookYaw = 0

local function nearestTarget(from: Vector3): Vector3?
    local best: Vector3? = nil
    local bestDistance = math.huge
    for _, player in Players:GetPlayers() do
        local root = rootOf(player)
        if root and KitchenService:IsInKitchen(root.Position) then
            local distance = (root.Position - from).Magnitude
            if distance < bestDistance then
                best, bestDistance = root.Position, distance
            end
        end
    end
    return best
end

local function animate(step: number): ()
    local dog = dogModel()
    if dog == nil then
        animDog = nil
        return
    end
    if dog ~= animDog then
        animDog = dog
        restPivot = dog:GetPivot()
        local _, size = dog:GetBoundingBox()
        restHeight = size.Y
        lookYaw = 0
    end
    local now = os.clock()
    local desiredYaw = 0
    if state == "Hunting" then
        local target = nearestTarget(restPivot.Position)
        if target then
            local offset = restPivot:PointToObjectSpace(target)
            desiredYaw = math.atan2(-offset.X, -offset.Z)
        else
            desiredYaw = lookYaw
        end
    end
    local delta = (desiredYaw - lookYaw + math.pi) % (2 * math.pi) - math.pi
    lookYaw += math.clamp(delta, -TURN_SPEED * step, TURN_SPEED * step)

    local pose: CFrame
    if state == "Sleeping" then
        local breath = 0.5 + 0.5 * math.sin(now * 1.7)
        pose = restPivot
            * CFrame.Angles(0, lookYaw, 0)
            * CFrame.new(0, restHeight * 0.04 * breath, 0)
            * CFrame.Angles(math.rad(1.2 * breath), 0, 0)
    elseif state == "Growling" then
        pose = restPivot
            * CFrame.Angles(0, lookYaw, 0)
            * CFrame.new(0, restHeight * 0.22, 0)
            * CFrame.Angles(math.rad(10 + 2 * math.sin(now * 38)), 0, math.rad(1.5 * math.sin(now * 31)))
    else
        pose = restPivot
            * CFrame.Angles(0, lookYaw, 0)
            * CFrame.new(0, restHeight * 0.3, 0)
            * CFrame.Angles(math.rad(14 + 3 * math.sin(now * 9)), 0, 0)
    end
    dog:PivotTo(pose)
end

local function watchCharacter(player: Player, character: Model): ()
    local humanoid = character:WaitForChild("Humanoid", 5)
    if humanoid == nil or not humanoid:IsA("Humanoid") then
        return
    end
    local old = landingConnections[player]
    if old then
        old:Disconnect()
    end
    landingConnections[player] = humanoid.StateChanged:Connect(
        function(_: Enum.HumanoidStateType, newState: Enum.HumanoidStateType)
            if newState ~= Enum.HumanoidStateType.Landed then
                return
            end
            local root = character:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") and KitchenService:IsInKitchen(root.Position) then
                DogService:Add(Tuning.NOISE_LANDING * Kitchen.TILE_NOISE_FACTOR)
            end
        end
    )
end

function DogService:Init(): () end

function DogService:Start(): ()
    local function onPlayer(player: Player): ()
        player.CharacterAdded:Connect(function(character: Model)
            watchCharacter(player, character)
        end)
        if player.Character then
            task.spawn(watchCharacter, player, player.Character)
        end
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        onPlayer(player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        caughtAt[player] = nil
        lastPositions[player] = nil
        local connection = landingConnections[player]
        if connection then
            connection:Disconnect()
        end
        landingConnections[player] = nil
    end)

    setState("Sleeping", 0)
    local elapsed, sinceBroadcast, sinceAnim = 0, 0, 0
    RunService.Heartbeat:Connect(function(dt: number)
        elapsed += dt
        sinceBroadcast += dt
        sinceAnim += dt
        if sinceAnim >= ANIM_SECONDS then
            animate(sinceAnim)
            sinceAnim = 0
        end
        if elapsed < TICK_SECONDS then
            return
        end
        local step = elapsed
        elapsed = 0
        if state == "Sleeping" then
            local gain = movementNoise(step) + thrownToysNoise(step)
            if gain > 0 then
                DogService:Add(gain)
            end
            if state == "Sleeping" then
                noise = math.max(noise - Kitchen.NOISE_DECAY_PER_SECOND * step, 0)
            end
        elseif state == "Hunting" then
            huntTick(step)
        end
        if sinceBroadcast >= 1 / Kitchen.BROADCAST_HZ then
            sinceBroadcast = 0
            broadcast()
        end
    end)
end

return DogService
