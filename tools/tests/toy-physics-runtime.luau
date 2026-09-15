--!strict

-- À envoyer à eval_server_runtime pendant un playtest solo, après chargement du profil.
-- Rejouer dans une nouvelle session avec scenario = "capture" (Cactus) puis "lancer" (Top).
-- scenario = "mission" : inspection seule de la tétine sur le matelas et stabilité pendant 7 s.
-- scenario = "mission_retour" : observation seule ; déposer/perdre la tétine dans les 120 s.
-- Les 71 relevés sont écrits dans les journaux serveur, sans bloquer le pont pendant 7 secondes.
local scenario = "lancer"
assert(game:GetService("RunService"):IsStudio(), "Test réservé à Studio")
local Players = game:GetService("Players")
local server = game:GetService("ServerScriptService").Server
local carry = require(server.Services.CarryService)
local giant = require(server.Services.GiantService)
local physics = require(server.ToyPhysics)
local placement = require(server.ToyPlacement)
local spawnService = require(server.Services.ToySpawnService)
local zone = require(game:GetService("ReplicatedStorage").Shared.Zone)
if scenario == "mission_retour" then
    local missionService = require(server.Services.PacifierMissionService)
    local toy = assert(missionService:GetMission(), "Tétine de mission absente")
    local goneAt: number? = nil
    local connection = toy.Destroying:Connect(function()
        goneAt = os.clock()
    end)
    task.spawn(function()
        local deadline = os.clock() + 120
        while goneAt == nil and os.clock() < deadline do
            task.wait(0.1)
        end
        connection:Disconnect()
        local began = assert(goneAt, "Aucune destruction observée en 120 s ; refaire après dépôt réel")
        while os.clock() - began < 23 do
            -- Lire le temps avant l'instance pour ne pas dater une apparition après coup.
            local elapsed = os.clock() - began
            local replacement = missionService:GetMission()
            if replacement then
                assert(replacement ~= toy, "Ancienne mission encore référencée après destruction")
                assert(elapsed >= 19.95, "Retour anticipé avant 20 s (tolérance 0,05 s pour Destroying différé)")
                local count = 0
                for _, candidate in game:GetService("CollectionService"):GetTagged("Toy") do
                    if candidate:IsDescendantOf(workspace) and candidate:GetAttribute("TetineMission") == true then
                        count += 1
                    end
                end
                assert(count == 1, "Retour en double")
                print(
                    string.format(
                        "[TEST-PHYSIQUE] OK retour mission unique après %.3f s ; rejouer mission pour le contact",
                        elapsed
                    )
                )
                return
            end
            task.wait(0.1)
        end
        error("Aucun retour en 23 s après destruction ; vérifier les dépendances et diagnostics de pose")
    end)
    return "Observation du retour armée : déposer la mission, puis lire les journaux et rejouer mission."
end
if scenario == "mission" then
    local missionService = require(server.Services.PacifierMissionService)
    local toy = assert(missionService:GetMission(), "Tétine de mission absente")
    local template = game:GetService("ServerStorage").ToyModels.Pacifier
    local room = workspace.Chambre
    local crib = room.Decor.Crib
    local target = room.Zones.ToileTrampoline:GetAttribute("Target")
    assert(typeof(target) == "Vector3", "Target absent")
    local params = RaycastParams.new()
    params.RespectCanCollide = true
    params.FilterDescendantsInstances = { toy }
    local hit = assert(workspace:Raycast(target + Vector3.new(0, 30, 0), Vector3.new(0, -100, 0), params))
    assert(hit.Instance:IsDescendantOf(crib) and hit.Normal.Y >= 0.98, "Appui hors du matelas")
    local box, size = placement.Bounds(toy)
    local _, originalSize = placement.Bounds(template)
    assert((size - originalSize * 1.7).Magnitude < 0.01, "Échelle finale différente de ×1,7")
    assert(
        math.abs(box.Position.X - target.X) <= 9.01 and math.abs(box.Position.Z - target.Z) <= 9.01,
        "Pose hors recherche locale"
    )
    local bottom = box.Position.Y - size.Y / 2
    local highest = -math.huge
    local valid = true
    for _, x in { -1, 0, 1 } do
        for _, z in { -1, 0, 1 } do
            local point = box:PointToWorldSpace(Vector3.new(x * size.X / 2, 0, z * size.Z / 2))
            local probe =
                workspace:Raycast(Vector3.new(point.X, target.Y + 30, point.Z), Vector3.new(0, -100, 0), params)
            print(
                string.format(
                    "[TEST-PHYSIQUE] sonde(%d,%d) instance=%s normale=%s écartTargetY=%s jeuSousBase=%s",
                    x,
                    z,
                    if probe then probe.Instance:GetFullName() else "aucune",
                    if probe then tostring(probe.Normal) else "absente",
                    if probe then string.format("%.3f", probe.Position.Y - hit.Position.Y) else "absent",
                    if probe then string.format("%.3f", bottom - probe.Position.Y) else "absent"
                )
            )
            if probe then
                highest = math.max(highest, probe.Position.Y)
            end
            valid = valid
                and probe ~= nil
                and probe.Instance:IsDescendantOf(crib)
                and probe.Normal.Y >= 0.98
                and math.abs(probe.Position.Y - hit.Position.Y) <= 0.251
                and bottom - probe.Position.Y >= -0.01
                and bottom - probe.Position.Y <= 0.251
        end
    end
    assert(valid, "Empreinte invalide : lire les neuf sondes ci-dessus")
    assert(math.abs(bottom - highest) < 0.01, "Base sans contact avec l'appui le plus haut")
    assert(placement.Ground(room, target, toy) == nil, "Les règles ordinaires autorisent désormais le berceau")
    local function checkRest(): ()
        assert(missionService:GetMission() == toy and toy:IsDescendantOf(workspace), "Mission disparue")
        assert(
            toy:GetAttribute("CarrierUserId") == nil and toy:GetAttribute("AspireParUserId") == nil,
            "Test interrompu par une prise"
        )
        assert(toy:GetAttribute("PhysiqueActive") == nil, "Simulation inattendue sur le matelas")
        assert((placement.Bounds(toy).Position - box.Position).Magnitude < 0.01, "Tétine déplacée")
        local count = 0
        for _, candidate in game:GetService("CollectionService"):GetTagged("Toy") do
            if candidate:IsDescendantOf(workspace) and candidate:GetAttribute("TetineMission") == true then
                count += 1
            end
        end
        assert(count == 1, "Nombre de tétines de mission différent de un")
        for _, part in physics.Parts(toy) do
            assert(part.Anchored and part.CanCollide and part.CanQuery, "Pose non ancrée ou non interactive")
        end
    end
    checkRest()
    task.delay(7, function()
        checkRest()
        print("[TEST-PHYSIQUE] OK mission : ×1,7, contact matelas, unicité, stabilité 7 s, refus ordinaire")
    end)
    return "Inspection mission démarrée : ne pas prendre la tétine ; lire les journaux après 8 secondes."
end
local player = assert(Players:GetPlayers()[1], "Joueur absent")
local character = assert(player.Character, "Personnage absent")
local root = character:FindFirstChild("HumanoidRootPart")
assert(root and root:IsA("BasePart"), "Racine absente")
assert(
    player:GetAttribute("CarriedToyId") == nil and player:GetAttribute("CarriedToyId2") == nil,
    "Vider les mains et le sac"
)
local position = if scenario == "capture" then Vector3.new(-60, 5, 60) else Vector3.new(60, 7, 120)
character:PivotTo(CFrame.lookAt(position, position - Vector3.zAxis))
root.AssemblyLinearVelocity = Vector3.zero
root.AssemblyAngularVelocity = Vector3.zero

task.spawn(function()
    task.wait(0.3)
    local room = assert(placement.RoomAt(root.Position), "Joueur hors de la pièce")
    local toy = assert(
        spawnService:SpawnTemporary(if scenario == "capture" then "Cactus" else "Top", root.Position, nil, 45),
        "Modèle ou sol de départ indisponible"
    )
    assert(carry:TryPickup(player, toy), "Prise initiale refusée")
    if scenario == "capture" then
        giant:Catch(player, "moved")
    else
        carry:Throw(player, -Vector3.zAxis)
    end
    assert(toy:GetAttribute("PhysiqueActive") == true, "Aucun vol : vérifier bouclier, cape, recharge ou obstacle")
    assert(toy:GetAttribute("CarrierUserId") == nil, "Jouet encore porté")
    local primary = assert(zone.PrimaryPart(toy))
    local parts = physics.Parts(toy)
    for _, part in primary:GetConnectedParts(true) do
        assert(not part:IsDescendantOf(character), "Soudure externe restante")
    end
    assert(primary:GetNetworkOwner() == nil, "Simulation non possédée par le serveur")
    local origin = placement.Bounds(toy).Position
    local previous = origin
    local began = os.clock()
    local previousTime = 0
    local suspended = 0
    local maxSuspended = 0
    local maxDistance = 0
    local belowFloor = false
    for index = 0, 70 do
        if index > 0 then
            task.wait(math.max(0, began + index * 0.1 - os.clock()))
        end
        assert(toy:IsDescendantOf(workspace), "Jouet disparu")
        local now = os.clock() - began
        local box, size = placement.Bounds(toy)
        local vertical = math.abs(box.RightVector.Y) * size.X
            + math.abs(box.UpVector.Y) * size.Y
            + math.abs(box.LookVector.Y) * size.Z
        local bottom = box.Position.Y - vertical / 2
        local floor = placement.FloorAt(room, box.Position)
        local delta = (box.Position - previous).Magnitude
        local distance = (box.Position - origin).Magnitude
        maxDistance = math.max(maxDistance, distance)
        if floor and bottom > floor.Y + 1 and delta < 0.05 then
            suspended += now - previousTime
        else
            suspended = 0
        end
        maxSuspended = math.max(maxSuspended, suspended)
        local anchored = false
        for _, part in parts do
            anchored = anchored or part.Anchored
        end
        belowFloor = belowFloor or (anchored and floor ~= nil and bottom < floor.Y - 0.01)
        print(
            string.format(
                "[TEST-PHYSIQUE] %s t=%.3f position=%s vitesse=%s pas=%.3f distance=%.2f bas=%.3f sol=%s ancre=%s actif=%s",
                scenario,
                now,
                tostring(box.Position),
                tostring(primary.AssemblyLinearVelocity),
                delta,
                distance,
                bottom,
                if floor then string.format("%.3f", floor.Y) else "absent",
                tostring(anchored),
                tostring(toy:GetAttribute("PhysiqueActive"))
            )
        )
        previous, previousTime = box.Position, now
    end
    assert(maxSuspended < 0.5, "Suspension en l'air supérieure à 0,5 seconde")
    assert(not belowFloor, "Ancrage sous le sol")
    assert(maxDistance < 80, "Jouet projeté trop loin dans ce scénario")
    assert(toy:GetAttribute("PhysiqueActive") == nil, "Vol encore actif après 7 secondes")
    local final = placement.Bounds(toy).Position
    assert(placement.RoomAt(final) == room, "Jouet perdu hors de sa pièce")
    for _, descendant in toy:GetDescendants() do
        assert(not descendant:IsA("NoCollisionConstraint"), "Exclusion de collision non nettoyée")
    end
    character:PivotTo(CFrame.new(final + Vector3.new(4, 4, 0)))
    root.AssemblyLinearVelocity = Vector3.zero
    assert(carry:TryPickup(player, toy), "Prise après atterrissage refusée")
    carry:PutDown(player)
    print(
        string.format("[TEST-PHYSIQUE] OK %s distanceMax=%.2f suspensionMax=%.3f", scenario, maxDistance, maxSuspended)
    )
end)

return "Test démarré : lire les journaux [TEST-PHYSIQUE] après 8 secondes, puis arrêter le playtest."
