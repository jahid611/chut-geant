--!strict

--[[
    TrampolineService
    Trampoline pres du berceau (demande utilisateur du 15/09) : sauter dessus propulse le joueur en cloche jusque
    dans le berceau, pour aller chercher le jouet legendaire pose sur le matelas. C'est tres bruyant.

    Pieces taguees « Trampoline » (surface de rebond, posee par la recette build-chambre avec le modele 3D), attribut
    Target (Vector3 : point d'arrivee sur le matelas). Le serveur verifie la position du joueur (sur la toile, en
    train de retomber), calcule la vitesse d'un tir parabolique qui arrive sur Target en FLIGHT_SECONDS et l'envoie
    au client (remote Bounce : le personnage est simule chez lui), ajoute le bruit et joue le son du ressort.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local NoiseService = require(script.Parent:WaitForChild("NoiseService"))

local TAG = "Trampoline"
-- Sommet du vol au-dessus de la cible si la toile n'a pas d'attribut Apex (hauteur du rebord du berceau + marge).
local APEX_MARGIN = 60
local NOISE = 22
local COOLDOWN = 1.2
-- « Boing » de ressort (son « Spring » de la bibliotheque Roblox).
local BOING_SOUND = "rbxassetid://142245269"

local TrampolineService = {}

-- (player: Player) un joueur vient de rebondir vers le berceau (fil d'actualite du serveur).
local bounced = Instance.new("BindableEvent")
TrampolineService.Bounced = bounced.Event

local lastBounce: { [Player]: number } = {}

local function playBoing(pad: BasePart): ()
    if BOING_SOUND == "rbxassetid://0" then
        return
    end
    local sound = Instance.new("Sound")
    sound.SoundId = BOING_SOUND
    sound.Volume = 0.8
    sound.PlaybackSpeed = 0.9 + math.random() * 0.2
    sound.RollOffMaxDistance = 500
    sound.Parent = pad
    sound:Play()
    task.delay(3, function()
        sound:Destroy()
    end)
end

-- Vitesse initiale d'un tir en cloche de from a to qui passe par un sommet a la hauteur apex (au-dessus du rebord
-- du berceau : avec un temps de vol fixe la trajectoire plafonnait a 127 et le joueur butait contre le lit, teste
-- en jeu le 16/09).
local function launchVelocity(from: Vector3, to: Vector3, apex: number): Vector3
    local g = workspace.Gravity
    local rise = math.max(apex - from.Y, 1)
    local vy = math.sqrt(2 * g * rise)
    local fall = math.max(apex - to.Y, 0)
    local seconds = vy / g + math.sqrt(2 * fall / g)
    local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
    return flat / seconds + Vector3.new(0, vy, 0)
end

local function check(): ()
    local now = os.clock()
    local pads = CollectionService:GetTagged(TAG)
    for _, player in Players:GetPlayers() do
        local last: number? = lastBounce[player]
        if last and now - last < COOLDOWN then
            continue
        end
        local character = player.Character
        local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
        if root == nil or not root:IsA("BasePart") or root.AssemblyLinearVelocity.Y > 2 then
            continue
        end
        for _, pad in pads do
            if not pad:IsA("BasePart") or not pad:IsDescendantOf(workspace) then
                continue
            end
            -- volume de detection : la toile et 6 studs au-dessus
            local local_ = pad.CFrame:PointToObjectSpace(root.Position)
            local half = pad.Size / 2
            local onPad = math.abs(local_.X) <= half.X
                and math.abs(local_.Z) <= half.Z
                and local_.Y >= -half.Y
                and local_.Y <= half.Y + 6
            local target = pad:GetAttribute("Target")
            if onPad and typeof(target) == "Vector3" then
                lastBounce[player] = now
                local apexAttribute = pad:GetAttribute("Apex")
                local apex = if typeof(apexAttribute) == "number" then apexAttribute else target.Y + APEX_MARGIN
                -- Le client fait suivre au personnage la cloche calculee (depart, arrivee, sommet) : une simple vitesse
                -- etait freinee en l'air par le Humanoid (18 studs parcourus au lieu de 126, teste en jeu le 16/09).
                local _ = launchVelocity(root.Position, target, apex)
                local remote = Remotes.Get("Bounce") :: RemoteEvent
                remote:FireClient(player, root.Position, target, apex)
                NoiseService:Add(NOISE)
                playBoing(pad)
                bounced:Fire(player)
                break
            end
        end
    end
end

function TrampolineService:Init(): () end

function TrampolineService:Start(): ()
    local elapsed = 0
    RunService.Heartbeat:Connect(function(dt: number)
        elapsed += dt
        if elapsed >= 0.1 then
            elapsed = 0
            check()
        end
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        lastBounce[player] = nil
    end)
end

return TrampolineService
