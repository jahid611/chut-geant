--!strict

--[[
    GiantService
    Le geant endormi : dort, se reveille quand la jauge de bruit est pleine, chasse.

    Sleeping -> Waking (Tuning.GIANT_WAKE_SECONDS, le temps de s'immobiliser)
    -> Hunting (Tuning.GIANT_HUNT_SECONDS) -> Sleeping, jauge remise a zero.
    Pendant la chasse, tout joueur de la chambre qui bouge est attrape : il lache
    son jouet (retour a son point) et est propulse loin du berceau (le client applique
    la vitesse, remote Caught), au lieu d'etre teleporte a sa base.

    Glance : un regard bref du bebe pour les mini-jeux (« Vite, dans l'ombre ! ») ; ceux
    que le filtre ne protege pas sont attrapes, puis le bebe se rendort.

    Pouvoirs (Shared/Abilities) : Cape d'ombre = jamais attrape ; Doudou bouclier = la prochaine propulsion est
    annulee ; Hochet leurre = personne n'est attrape tant que le bebe regarde le hochet ; Berceuse = Soothe.

    L'etat est pousse aux clients (remote GiantState) et pose en attribut State
    sur workspace.Geant s'il existe, pour les animations et les effets.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Tuning"))

local CarryService = require(script.Parent:WaitForChild("CarryService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))

export type GiantState = "Sleeping" | "Waking" | "Hunting"

local GiantService = {}

-- (player: Player, reason: string) un joueur vient d'etre attrape et propulse (ComboService : le combo retombe).
local caughtEvent = Instance.new("BindableEvent")
GiantService.Caught = caughtEvent.Event
-- (state: GiantState, endsAt: number, glance: boolean, cause: string?) nouvel etat ; glance vrai pour un regard bref ;
-- cause "huntEnded" seulement quand une chasse de reveil arrive a son terme normal (pas Berceuse ni regard bref).
-- Utilise par HandChaseService.
local stateEvent = Instance.new("BindableEvent")
GiantService.StateChanged = stateEvent.Event

local state: GiantState = "Sleeping"
local endsAt = 0
local caughtAt: { [Player]: number } = {}
local glancing = false
local glanceToken = 0
-- Invalide les delais d'un reveil en cours (Berceuse).
local wakeToken = 0

local function setState(newState: GiantState, duration: number, cause: string?): ()
    state = newState
    endsAt = workspace:GetServerTimeNow() + duration
    local giant = workspace:FindFirstChild("Geant")
    if giant then
        giant:SetAttribute("State", newState)
    end
    local remote = Remotes.Get("GiantState") :: RemoteEvent
    remote:FireAllClients(state, endsAt)
    stateEvent:Fire(state, endsAt, glancing, cause)
end

local function cribPosition(): Vector3
    local chambre = workspace:FindFirstChild("Chambre")
    local decor = if chambre then chambre:FindFirstChild("Decor") else nil
    local crib = if decor then decor:FindFirstChild("Crib") else nil
    if crib and crib:IsA("Model") then
        return crib:GetPivot().Position
    end
    return Vector3.new(0, 0, -150)
end

-- Attrape un joueur : il lache son jouet et le client le propulse loin du berceau.
function GiantService:Catch(player: Player, reason: string): ()
    -- Cape d'ombre : invisible pour le bebe et pour maman.
    if Abilities.IsActive(player, "ShadowCape") then
        return
    end
    local now = os.clock()
    local last: number? = caughtAt[player]
    if last and now - last < Tuning.CATCH_STUN_SECONDS + 0.5 then
        return
    end
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    if root == nil or not root:IsA("BasePart") then
        return
    end
    caughtAt[player] = now
    -- Doudou bouclier : cette propulsion est annulee (le delai de recuperation compte quand meme).
    if Abilities.ConsumeShield(player) then
        return
    end
    CarryService:Drop(player, true)
    local away = root.Position - cribPosition()
    local flat = Vector3.new(away.X, 0, away.Z)
    local direction = if flat.Magnitude > 1 then flat.Unit else Vector3.new(0, 0, 1)
    local launch = direction * Tuning.CATCH_LAUNCH_SPEED + Vector3.new(0, Tuning.CATCH_LAUNCH_UP, 0)
    local remote = Remotes.Get("Caught") :: RemoteEvent
    remote:FireClient(player, reason, launch)
    caughtEvent:Fire(player, reason)
end

--[[
    Pendant la chasse, chaque joueur de la chambre qui bouge OU saute est propulse, autant de fois qu'il recommence
    (retour utilisateur : apres une propulsion on pouvait rebouger librement, et sauter ne comptait pas). Seuls ceux
    qui bougent : on mesure le deplacement entre deux controles plutot que la vitesse instantanee, qui tremble a
    l'arret. Un joueur propulse est ignore tant qu'il vole, puis le temps de se relever.
]]
local HUNT_CHECK_SECONDS = 0.2
local lastPositions: { [Player]: Vector3 } = {}
local lastCheck = 0

local function huntTick(): ()
    local now = os.clock()
    local elapsed = now - lastCheck
    if elapsed < HUNT_CHECK_SECONDS then
        return
    end
    lastCheck = now
    -- Hochet leurre : le bebe le regarde, les positions sont suivies mais personne n'est attrape.
    local distracted = Abilities.IsDecoyActive()
    for _, player in Players:GetPlayers() do
        local character = player.Character
        local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
        local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        if root == nil or not root:IsA("BasePart") or humanoid == nil or not NoiseService:IsInRoom(root.Position) then
            lastPositions[player] = nil
            continue
        end
        local previous: Vector3? = lastPositions[player]
        lastPositions[player] = root.Position
        if distracted then
            continue
        end
        local last: number? = caughtAt[player]
        if last then
            local since = now - last
            local airborne = humanoid.FloorMaterial == Enum.Material.Air
            if since < Tuning.CATCH_STUN_SECONDS + Tuning.CATCH_RECOVER_SECONDS or (airborne and since < 6) then
                continue
            end
        end
        -- premier controle (ou retour dans la chambre) : pas encore de mesure
        if previous == nil or elapsed > 1 then
            continue
        end
        local delta = root.Position - previous
        -- Il faut une vraie intention du joueur (MoveDirection, repliquee depuis ses commandes, ou un saut) : apres une
        -- propulsion, la glissade et la remise debout deplacaient le corps et relancaient la capture en boucle alors
        -- que le joueur ne touchait plus a rien (retour utilisateur « le boing se fait plein de fois »).
        local wantsToMove = humanoid.MoveDirection.Magnitude > 0.1
        local moved = wantsToMove and Vector3.new(delta.X, 0, delta.Z).Magnitude > Tuning.GIANT_FREEZE_SPEED * elapsed
        local humanoidState = humanoid:GetState()
        local jumped = humanoidState == Enum.HumanoidStateType.Jumping
            or (delta.Y > Tuning.GIANT_JUMP_RISE and humanoid.Jump)
        if
            humanoidState == Enum.HumanoidStateType.GettingUp
            or humanoidState == Enum.HumanoidStateType.PlatformStanding
            or humanoidState == Enum.HumanoidStateType.Ragdoll
            or humanoidState == Enum.HumanoidStateType.FallingDown
        then
            continue
        end
        if moved or jumped then
            GiantService:Catch(player, if jumped then "jumped" else "moved")
        end
    end
end

function GiantService:GetState(): (GiantState, number)
    return state, endsAt
end

function GiantService:GetCribPosition(): Vector3
    return cribPosition()
end

-- Reveille le bebe. instant : presque sans preavis (jouet piege qui explose).
function GiantService:Wake(instant: boolean?): ()
    if state ~= "Sleeping" or glancing then
        return
    end
    wakeToken += 1
    local token = wakeToken
    local warn = if instant then 0.4 else Tuning.GIANT_WAKE_SECONDS
    setState("Waking", warn)
    task.delay(warn, function()
        if token ~= wakeToken then
            return
        end
        table.clear(lastPositions)
        setState("Hunting", Tuning.GIANT_HUNT_SECONDS)
        task.delay(Tuning.GIANT_HUNT_SECONDS, function()
            if token ~= wakeToken then
                return
            end
            setState("Sleeping", 0, "huntEnded")
            NoiseService:Reset()
        end)
    end)
end

-- Berceuse : le bebe se rendort tout de suite (reveil, chasse ou regard annules) et la jauge revient a zero.
function GiantService:Soothe(): ()
    if state ~= "Sleeping" then
        wakeToken += 1
        glanceToken += 1
        glancing = false
        setState("Sleeping", 0)
    end
    NoiseService:Reset()
end

--[[
    Regard bref du bebe (mini-jeux) : pendant `seconds`, il est eveille ; tout joueur de la chambre pour qui
    isSafe renvoie faux est attrape au debut du regard. Sans effet si le bebe est deja reveille.
]]
function GiantService:Glance(seconds: number, isSafe: (Player, Vector3) -> boolean): ()
    if state ~= "Sleeping" or glancing then
        return
    end
    glancing = true
    glanceToken += 1
    local token = glanceToken
    setState("Hunting", seconds)
    if not Abilities.IsDecoyActive() then
        for _, player in Players:GetPlayers() do
            local character = player.Character
            local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
            if root and root:IsA("BasePart") and NoiseService:IsInRoom(root.Position) then
                if not isSafe(player, root.Position) then
                    GiantService:Catch(player, "seen")
                end
            end
        end
    end
    task.delay(seconds, function()
        if token ~= glanceToken then
            return
        end
        glancing = false
        setState("Sleeping", 0)
        NoiseService:Reset()
    end)
end

function GiantService:Init(): () end

function GiantService:Start(): ()
    NoiseService.Maxed:Connect(function()
        self:Wake()
    end)

    Players.PlayerAdded:Connect(function(player: Player)
        (Remotes.Get("GiantState") :: RemoteEvent):FireClient(player, state, endsAt)
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        lastPositions[player] = nil
        caughtAt[player] = nil
    end)

    RunService.Heartbeat:Connect(function()
        -- Avec la main geante (HandChaseService), la regle « bouger = attrape » ne sert plus pendant la chasse.
        if state == "Hunting" and not glancing and not Tuning.HAND_CHASE_ENABLED then
            huntTick()
        end
    end)
end

return GiantService
