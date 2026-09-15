--!strict

--[[
    WeaponController
    Armes rigolotes cote joueur (WeaponService donne l'outil de l'arme equipee) :
    - clic / tap avec l'arme en main (Tool.Activated) = coup : intention envoyee au serveur (remote WeaponSwing,
      direction de la camera), son de whoosh, geste de frappe procedural ;
    - coup qui touche (remote WeaponHit) : son de l'arme pour l'attaquant et la victime, petite eclaboussure de
      lumiere a l'endroit du coup pour tout le monde.

    Geste de frappe (retour utilisateur du 15/09 : « le bon mouvement de frappe comme dans la vraie vie ») : images
    cles par style d'arme (Shared/Weapons.style) sur l'epaule droite, le coude droit et la taille, ecrites dans
    Transform a chaque PreSimulation apres les animations (les articulations de ce place sont des AnimationConstraint,
    comme la pose bras leves de CarryController). Chaque segment a sa courbe : preparation qui ralentit, frappe qui
    accelere, suivi, retour en douceur.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local Sfx = require(script.Parent.Parent.Ui.Sfx)

-- Rotations en radians (x, y, z) de chaque articulation. Epaule R15 autour de X : pi/2 = bras devant (pose de tenue
-- d'outil), pi = bras en l'air ; coude autour de X = plier ; taille autour de Y = tourner le buste.
type Key = { t: number, shoulder: Vector3, elbow: Vector3, waist: Vector3, ease: string }
type Style = { seconds: number, keys: { Key } }

local REST_SHOULDER = Vector3.new(1.57, 0, 0)
local REST_ELBOW = Vector3.new(0.2, 0, 0)

local function key(t: number, shoulder: Vector3, elbow: Vector3, waist: Vector3, ease: string): Key
    return { t = t, shoulder = shoulder, elbow = elbow, waist = waist, ease = ease }
end

local STYLES: { [string]: Style } = {
    -- Coup en arc (batte, epee, marteau, tapette) : armer au-dessus de l'epaule en tournant le buste, abattre vite
    -- devant soi en depliant le coude, suivi vers le bas, retour.
    arc = {
        seconds = 0.46,
        keys = {
            key(0, REST_SHOULDER, REST_ELBOW, Vector3.zero, "linear"),
            key(0.32, Vector3.new(2.95, 0, -0.25), Vector3.new(1.3, 0, 0), Vector3.new(0, 0.38, 0), "out"),
            key(0.55, Vector3.new(0.55, 0, 0.1), Vector3.new(0.05, 0, 0), Vector3.new(0, -0.4, 0), "in"),
            key(0.72, Vector3.new(0.3, 0, 0.12), Vector3.new(0.15, 0, 0), Vector3.new(0, -0.48, 0), "out"),
            key(1, REST_SHOULDER, REST_ELBOW, Vector3.zero, "inout"),
        },
    },
    -- Chausson : grand coup de haut en bas, le buste bascule vers l'avant.
    overhead = {
        seconds = 0.46,
        keys = {
            key(0, REST_SHOULDER, REST_ELBOW, Vector3.zero, "linear"),
            key(0.34, Vector3.new(3.05, 0, -0.1), Vector3.new(1.45, 0, 0), Vector3.new(-0.18, 0.1, 0), "out"),
            key(0.56, Vector3.new(0.35, 0, 0.05), Vector3.new(0.05, 0, 0), Vector3.new(0.32, -0.1, 0), "in"),
            key(0.74, Vector3.new(0.2, 0, 0.05), Vector3.new(0.2, 0, 0), Vector3.new(0.38, -0.12, 0), "out"),
            key(1, REST_SHOULDER, REST_ELBOW, Vector3.zero, "inout"),
        },
    },
    -- Oreiller : grand balayage horizontal, le buste pivote d'un cote a l'autre.
    sweep = {
        seconds = 0.52,
        keys = {
            key(0, REST_SHOULDER, REST_ELBOW, Vector3.zero, "linear"),
            key(0.33, Vector3.new(1.45, 0, -0.55), Vector3.new(0.5, 0, 0), Vector3.new(0, 0.85, 0), "out"),
            key(0.6, Vector3.new(1.55, 0, 0.35), Vector3.new(0.1, 0, 0), Vector3.new(0, -0.8, 0), "in"),
            key(0.78, Vector3.new(1.5, 0, 0.45), Vector3.new(0.2, 0, 0), Vector3.new(0, -0.9, 0), "out"),
            key(1, REST_SHOULDER, REST_ELBOW, Vector3.zero, "inout"),
        },
    },
    -- Pistolet a eau : bras tendu vise devant, tir, recul vers le haut, retour.
    shoot = {
        seconds = 0.38,
        keys = {
            key(0, REST_SHOULDER, REST_ELBOW, Vector3.zero, "linear"),
            key(0.25, Vector3.new(1.62, 0, 0), Vector3.new(0, 0, 0), Vector3.zero, "out"),
            key(0.38, Vector3.new(2.0, 0, 0), Vector3.new(0.35, 0, 0), Vector3.new(-0.12, 0, 0), "out"),
            key(1, REST_SHOULDER, REST_ELBOW, Vector3.zero, "inout"),
        },
    },
    -- Baguette : petit coup de poignet et d'avant-bras vers l'avant.
    flick = {
        seconds = 0.36,
        keys = {
            key(0, REST_SHOULDER, REST_ELBOW, Vector3.zero, "linear"),
            key(0.35, Vector3.new(1.85, 0, 0), Vector3.new(1.1, 0, 0), Vector3.new(0, 0.08, 0), "out"),
            key(0.55, Vector3.new(1.35, 0, 0), Vector3.new(-0.05, 0, 0), Vector3.new(0, -0.08, 0), "in"),
            key(1, REST_SHOULDER, REST_ELBOW, Vector3.zero, "inout"),
        },
    },
}

-- Couleur de l'eclaboussure par arme (blanc par defaut).
local HIT_COLORS: { [string]: Color3 } = {
    WeaponWaterGun = Color3.fromRGB(120, 200, 255),
    WeaponMagicWand = Color3.fromRGB(255, 225, 110),
    WeaponPinkBat = Color3.fromRGB(255, 150, 200),
    WeaponPillow = Color3.fromRGB(240, 240, 255),
}

local WeaponController = {}

local player = Players.LocalPlayer
local swingStartedAt: number? = nil
local swingStyle: Style = STYLES.arc
local swingSeconds = STYLES.arc.seconds
local lastLocalSwing = 0

local function ease(kind: string, t: number): number
    if kind == "out" then
        return 1 - (1 - t) * (1 - t)
    elseif kind == "in" then
        return t * t * t
    elseif kind == "inout" then
        return t * t * (3 - 2 * t)
    end
    return t
end

local function joint(character: Model, limb: string, name: string): any?
    local part = character:FindFirstChild(limb)
    local found = if part then part:FindFirstChild(name) else nil
    if found and (found:IsA("AnimationConstraint") or found:IsA("Motor6D")) then
        return found
    end
    return nil
end

local function angles(v: Vector3): CFrame
    return CFrame.Angles(v.X, v.Y, v.Z)
end

local function poseSwing(): ()
    local started = swingStartedAt
    local character = player.Character
    if started == nil or character == nil then
        return
    end
    local style = swingStyle
    local t = (os.clock() - started) / swingSeconds
    if t >= 1 then
        swingStartedAt = nil
        return
    end
    local keys = style.keys
    local a, b = keys[1], keys[#keys]
    for i = 1, #keys - 1 do
        if t >= keys[i].t and t <= keys[i + 1].t then
            a, b = keys[i], keys[i + 1]
            break
        end
    end
    local span = math.max(b.t - a.t, 1e-3)
    local alpha = ease(b.ease, math.clamp((t - a.t) / span, 0, 1))
    local shoulder = joint(character, "RightUpperArm", "RightShoulder") or joint(character, "Torso", "Right Shoulder")
    local elbow = joint(character, "RightLowerArm", "RightElbow")
    local waist = joint(character, "UpperTorso", "Waist")
    if shoulder then
        shoulder.Transform = angles(a.shoulder:Lerp(b.shoulder, alpha))
    end
    if elbow then
        elbow.Transform = angles(a.elbow:Lerp(b.elbow, alpha))
    end
    if waist then
        waist.Transform = angles(a.waist:Lerp(b.waist, alpha))
    end
end

-- Lance le geste de frappe de l'arme. slowdown (tests en jeu) : ralentit le geste pour le capturer image par image.
function WeaponController:PlaySwing(weaponId: string, slowdown: number?): ()
    local weapon = Weapons.Get(weaponId)
    swingStyle = STYLES[if weapon and weapon.style then weapon.style else "arc"] or STYLES.arc
    swingSeconds = swingStyle.seconds * math.max(slowdown or 1, 1)
    swingStartedAt = os.clock()
end

local function onActivated(tool: Tool): ()
    local id = tool:GetAttribute(Weapons.TOOL_ATTRIBUTE)
    local weapon = if typeof(id) == "string" then Weapons.Get(id) else nil
    if weapon == nil or player:GetAttribute("CarriedToyId") ~= nil then
        return
    end
    local now = os.clock()
    if now - lastLocalSwing < weapon.cooldown then
        return
    end
    lastLocalSwing = now
    -- Attribut de test « RalentiCoup » (nombre) : ralentit le geste pour le verifier par captures ; absent en jeu.
    local slowdown = player:GetAttribute("RalentiCoup")
    WeaponController:PlaySwing(weapon.id, if typeof(slowdown) == "number" then slowdown else nil)
    Sfx.play("weaponSwing")
    local remote = Remotes.Get("WeaponSwing") :: RemoteEvent
    remote:FireServer(Workspace.CurrentCamera.CFrame.LookVector)
end

local function watchTool(tool: Instance): ()
    if not tool:IsA("Tool") or tool:GetAttribute(Weapons.TOOL_ATTRIBUTE) == nil then
        return
    end
    if tool:GetAttribute("CoupBranche") then
        return
    end
    tool:SetAttribute("CoupBranche", true)
    tool.Activated:Connect(function()
        onActivated(tool)
    end)
end

-- Eclaboussure de lumiere locale a l'endroit du coup.
local function burst(position: Vector3, color: Color3): ()
    local ball = Instance.new("Part")
    ball.Name = "CoupArme"
    ball.Shape = Enum.PartType.Ball
    ball.Material = Enum.Material.Neon
    ball.Color = color
    ball.Size = Vector3.new(1, 1, 1)
    ball.Position = position + Vector3.new(0, 1.5, 0)
    ball.Anchored = true
    ball.CanCollide = false
    ball.CanQuery = false
    ball.CanTouch = false
    ball.CastShadow = false
    ball.Transparency = 0.2
    ball.Parent = Workspace
    local tween = TweenService:Create(
        ball,
        TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = Vector3.new(6, 6, 6), Transparency = 1 }
    )
    tween.Completed:Connect(function()
        ball:Destroy()
    end)
    tween:Play()
end

function WeaponController:Init(): () end

function WeaponController:Start(): ()
    local function onCharacter(character: Model): ()
        for _, child in character:GetChildren() do
            watchTool(child)
        end
        character.ChildAdded:Connect(watchTool)
    end
    player.CharacterAdded:Connect(onCharacter)
    if player.Character then
        onCharacter(player.Character)
    end

    RunService.PreSimulation:Connect(poseSwing)

    local hitRemote = Remotes.Get("WeaponHit") :: RemoteEvent
    hitRemote.OnClientEvent:Connect(function(weaponId: any, attackerId: any, targetId: any, position: any)
        if typeof(weaponId) ~= "string" or typeof(position) ~= "Vector3" then
            return
        end
        local weapon = Weapons.Get(weaponId)
        if weapon == nil then
            return
        end
        if attackerId == player.UserId or targetId == player.UserId then
            Sfx.play(weapon.hitSound)
        end
        burst(position, HIT_COLORS[weaponId] or Color3.new(1, 1, 1))
    end)
end

return WeaponController
