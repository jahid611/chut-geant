--!strict

--[[
    HandChaseService
    Course-poursuite pendant la chasse du bebe (retour utilisateur « le jeu est ennuyant » : se figer pendant la chasse
    etait toujours la bonne reponse). Pendant une chasse de reveil (GiantService, pas un regard bref), une main geante,
    rendue au sol comme une grande ombre par HandChaseController, part du pied du berceau et poursuit un joueur :
    - cible : joueur vivant de la chambre, hors refuge (EventService:IsHidden : ShadowZone et HideZone), sans Cape
      d'ombre, pas en train de se relever d'une capture ; les porteurs de jouet d'abord, puis le plus proche ; la cible
      courante est gardee si elle reste dans la meilleure categorie ; sans cible, la main revient vers le berceau ;
    - vitesse de Tuning.HAND_SPEED_START a HAND_SPEED_END sur la duree de la chasse ;
    - contact (HAND_CATCH_RADIUS, HAND_REACH_HEIGHT) : GiantService:Catch(joueur, "hand") ;
    - Hochet leurre : la main s'arrete et n'attrape personne ; Berceuse : la chasse s'arrete, pas de prime ;
    - a la fin normale de la chasse, un joueur poursuivi au moins une fois et jamais disqualifie depuis (sortie de la
      chambre, mort ou capture, meme en revenant avant la fin) recoit HAND_SURVIVE_CASH et HAND_SURVIVE_XP (remote
      ChaseNotice). Se cacher tout le temps ne rapporte rien ; un refuge de la chambre ne disqualifie pas.
    Etat publie en attributs de workspace.Geant : MainActive, MainPosition (sol), MainCibleUserId.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Tuning"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CarryService = require(script.Parent:WaitForChild("CarryService"))
local EventService = require(script.Parent:WaitForChild("EventService"))
local GiantService = require(script.Parent:WaitForChild("GiantService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local PassService = require(script.Parent:WaitForChild("PassService"))

local PUBLISH_SECONDS = 0.1
local GROUND_SECONDS = 0.25
-- Depart : au pied du berceau, cote chambre (le berceau est au fond, z negatif).
local HOME_OFFSET = Vector3.new(0, 0, 70)
local HOME_SPEED_FACTOR = 0.5
-- Apres une capture, le joueur vole puis se releve : il n'est ni cible ni attrape pendant ce temps.
local IGNORE_AFTER_CATCH = Tuning.CATCH_STUN_SECONDS + Tuning.CATCH_RECOVER_SECONDS + 0.5

local HandChaseService = {}

local active = false
local position = Vector3.zero
local home = Vector3.zero
local groundY = 0
local target: Player? = nil
local startedAt = 0
local endsAt = 0
local sinceRetarget = math.huge
local sincePublish = math.huge
local sinceGround = 0
-- Eligibles a la prime : poursuivis au moins une fois pendant cette chasse et jamais disqualifies depuis.
local chased: { [Player]: boolean } = {}
-- Disqualifies pour toute la chasse : sortis de la chambre (cuisine, base), morts ou attrapes.
local disqualified: { [Player]: boolean } = {}
local caughtAt: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
    local character = player.Character
    local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
        return nil
    end
    return root
end

-- Hauteur du parquet de la chambre (haut de Chambre.Structure.Sol), ou nil.
local function floorTop(): number?
    local chambre = workspace:FindFirstChild("Chambre")
    local structure = if chambre then chambre:FindFirstChild("Structure") else nil
    local floor = if structure then structure:FindFirstChild("Sol") else nil
    if floor and floor:IsA("BasePart") then
        return floor.Position.Y + floor.Size.Y / 2
    end
    return nil
end

-- Sol sous la main : rayon court qui part toujours de FLOOR_CLEARANCE au-dessus du parquet (pas du sol courant) :
-- la main glisse sous les meubles et ne reste jamais perchee sur le berceau (bug du 15/09 : premier rayon sur le
-- berceau, main a y = 104, contact vertical impossible).
local FLOOR_CLEARANCE = 12
local function groundAt(point: Vector3, fallbackY: number): number
    local floorY = floorTop()
    local fromY = if floorY then floorY + FLOOR_CLEARANCE - 8 else fallbackY
    local ignore: { Instance } = {}
    for _, player in Players:GetPlayers() do
        if player.Character then
            table.insert(ignore, player.Character)
        end
    end
    local live = workspace:FindFirstChild("ToysLive")
    if live then
        table.insert(ignore, live)
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    params.RespectCanCollide = true
    local hit = workspace:Raycast(Vector3.new(point.X, fromY + 8, point.Z), Vector3.new(0, -60, 0), params)
    return if hit then hit.Position.Y else (floorY or fallbackY)
end

-- Joueur poursuivable a cet instant (et sa racine), sinon nil.
local function chaseable(player: Player, now: number): BasePart?
    local root = rootOf(player)
    if root == nil or not NoiseService:IsInRoom(root.Position) then
        return nil
    end
    local last = caughtAt[player]
    if last and now - last < IGNORE_AFTER_CATCH then
        return nil
    end
    if Abilities.IsActive(player, "ShadowCape") or EventService:IsHidden(root.Position, true) then
        return nil
    end
    return root
end

-- Les porteurs de jouet passent toujours en premier, puis le plus proche. La cible courante est gardee si elle est
-- encore dans la meilleure categorie, pour que la main ne saute pas d'un joueur a l'autre.
local function pickTarget(now: number): Player?
    local best: Player? = nil
    local bestDistance = math.huge
    local bestCarrier = false
    for _, player in Players:GetPlayers() do
        local root = chaseable(player, now)
        if root then
            local offset = root.Position - position
            local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
            local carrier = CarryService:GetCarried(player) ~= nil
            if (carrier and not bestCarrier) or (carrier == bestCarrier and distance < bestDistance) then
                best, bestDistance, bestCarrier = player, distance, carrier
            end
        end
    end
    local current = target
    if current and current.Parent and chaseable(current, now) then
        local currentCarrier = CarryService:GetCarried(current) ~= nil
        if currentCarrier == bestCarrier then
            return current
        end
    end
    return best
end

local function publish(): ()
    local giant = workspace:FindFirstChild("Geant")
    if giant == nil then
        return
    end
    local current = target
    giant:SetAttribute("MainActive", active)
    giant:SetAttribute("MainPosition", if active then position else nil)
    giant:SetAttribute("MainCibleUserId", if active and current then current.UserId else nil)
end

local function start(untilTime: number): ()
    local crib = GiantService:GetCribPosition()
    home = crib + HOME_OFFSET
    groundY = groundAt(home, crib.Y + 2)
    position = Vector3.new(home.X, groundY, home.Z)
    target = nil
    startedAt = workspace:GetServerTimeNow()
    endsAt = untilTime
    sinceRetarget, sincePublish, sinceGround = math.huge, math.huge, 0
    table.clear(chased)
    table.clear(disqualified)
    active = true
    publish()
end

local function disqualify(player: Player): ()
    chased[player] = nil
    disqualified[player] = true
end

local function stop(natural: boolean): ()
    if not active then
        return
    end
    active = false
    target = nil
    publish()
    if natural then
        local notice = Remotes.Get("ChaseNotice") :: RemoteEvent
        for player in chased do
            local root = rootOf(player)
            if player.Parent and not disqualified[player] and root and NoiseService:IsInRoom(root.Position) then
                BaseService:AddCash(player, Tuning.HAND_SURVIVE_CASH)
                PassService:AddXp(player, Tuning.HAND_SURVIVE_XP, "chase")
                notice:FireClient(player, "survived", Tuning.HAND_SURVIVE_CASH, Tuning.HAND_SURVIVE_XP)
            end
        end
    end
    table.clear(chased)
    table.clear(disqualified)
end

local function step(dt: number): ()
    if not active then
        return
    end
    local now = workspace:GetServerTimeNow()
    sinceRetarget += dt
    sincePublish += dt
    sinceGround += dt
    local distracted = Abilities.IsDecoyActive()

    if sinceRetarget >= Tuning.HAND_RETARGET_SECONDS then
        sinceRetarget = 0
        target = if distracted then nil else pickTarget(now)
        local current = target
        if current and not disqualified[current] then
            chased[current] = true
        end
    end
    -- Quitter la chambre (cuisine, sa base), mourir : plus de prime pour cette chasse, meme en revenant avant la fin.
    for player in chased do
        local root = rootOf(player)
        if player.Parent == nil or root == nil or not NoiseService:IsInRoom(root.Position) then
            disqualify(player)
        end
    end

    local span = math.max(endsAt - startedAt, 1)
    local progress = math.clamp((now - startedAt) / span, 0, 1)
    local speed = Tuning.HAND_SPEED_START + (Tuning.HAND_SPEED_END - Tuning.HAND_SPEED_START) * progress
    local goal: Vector3? = nil
    local current = target
    if distracted then
        goal = nil
    elseif current then
        local root = chaseable(current, now)
        if root then
            goal = root.Position
        else
            target = nil
            sinceRetarget = math.huge
        end
    else
        goal = home
        speed *= HOME_SPEED_FACTOR
    end
    if goal then
        local flat = Vector3.new(goal.X - position.X, 0, goal.Z - position.Z)
        local distance = flat.Magnitude
        if distance > 0.05 then
            position += flat.Unit * math.min(speed * dt, distance)
        end
    end
    if sinceGround >= GROUND_SECONDS then
        sinceGround = 0
        groundY = groundAt(position, groundY)
    end
    position = Vector3.new(position.X, groundY, position.Z)

    if not distracted then
        for _, player in Players:GetPlayers() do
            local root = chaseable(player, now)
            if root then
                local offset = root.Position - position
                local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
                if flat <= Tuning.HAND_CATCH_RADIUS and math.abs(offset.Y) <= Tuning.HAND_REACH_HEIGHT then
                    -- Catch peut annuler la propulsion (Doudou bouclier) : le joueur est ignore quand meme un instant,
                    -- et la main change de cible.
                    caughtAt[player] = now
                    GiantService:Catch(player, "hand")
                    if target == player then
                        target = nil
                        sinceRetarget = math.huge
                    end
                end
            end
        end
    end

    if sincePublish >= PUBLISH_SECONDS then
        sincePublish = 0
        publish()
    end
end

function HandChaseService:IsActive(): boolean
    return active
end

function HandChaseService:Init(): () end

function HandChaseService:Start(): ()
    GiantService.StateChanged:Connect(function(state: string, untilTime: number, glance: boolean, cause: string?)
        if state == "Hunting" and not glance and Tuning.HAND_CHASE_ENABLED then
            start(untilTime)
        elseif active then
            -- prime seulement a la fin normale de la chasse (cause donnee par GiantService, jamais deduite du temps)
            stop(cause == "huntEnded")
        end
    end)
    GiantService.Caught:Connect(function(player: Player)
        caughtAt[player] = workspace:GetServerTimeNow()
        if active then
            disqualify(player)
        end
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        chased[player] = nil
        disqualified[player] = nil
        caughtAt[player] = nil
        if target == player then
            target = nil
        end
    end)
    RunService.Heartbeat:Connect(step)
    publish()
end

return HandChaseService
