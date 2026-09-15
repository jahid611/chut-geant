--!strict

--[[
    HandChaseController
    Rendu local de la main geante de HandChaseService (attributs MainActive, MainPosition, MainCibleUserId de
    workspace.Geant) :
    - grande ombre au sol (image d'ombre douce deja televersee, teinte tres sombre) qui suit la position du serveur en
      douceur, respire un peu, grandit et fonce quand elle s'approche du joueur local ; fondu a l'apparition et a la fin ;
    - grondement grave (« Low Rumble 2 », Pro Sound Effects) de plus en plus fort a l'approche, groupe « Effets » ;
    - bord rouge qui pulse sur l'ecran quand ce joueur est la cible ;
    - message « Tu as echappe au bebe ! » a la prime de survie (remote ChaseNotice).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tuning"))

local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Smoke = require(script.Parent.Parent.Ui.Smoke)
local Theme = require(script.Parent.Parent.Ui.Theme)

local SHADOW_TEXTURE = "rbxassetid://123681637407382"
local SHADOW_COLOR = Color3.fromRGB(12, 6, 22)
local RUMBLE_ID = "rbxassetid://9112824733"
-- Diametre de l'ombre loin du joueur et tout pres (studs). A 30 / 44 et 45 % d'opacite minimale, la tache se lisait
-- mal depuis la camera (capture du 15/09) : plus grande et plus sombre.
local SHADOW_SIZE = 42
local SHADOW_NEAR_SIZE = 60
local SHADOW_MIN_OPACITY = 0.75
-- Distances (studs) : l'ombre fonce sous NEAR_DISTANCE ; le grondement s'entend sous FAR_DISTANCE.
local NEAR_DISTANCE = 60
local FAR_DISTANCE = 170
local RUMBLE_MAX_VOLUME = 0.55
local FOLLOW_RATE = 12
local FADE_IN = 0.4
local FADE_OUT = 0.6
local EDGE_THICKNESS = 26

-- Vraie main du bebe au-dessus de l'ombre (« on la voit meme pas, que de l'ombre », utilisateur du 15/09 au soir) :
-- modele 3D ReplicatedStorage.MainGeanteModele (tools/scene/charger-main.luau) qui plane haut loin du joueur local et
-- descend sur lui quand l'ombre le rattrape. Sans le modele, seule l'ombre reste.
local HAND_MODEL_NAME = "MainGeanteModele"
-- 70 studs de haut sortait du champ de la camera du joueur : la main reste visible a 30 et descend a 8 sur lui.
local HAND_HIGH = 30
local HAND_LOW = 8
-- Le modele TRELLIS a les doigts vers le haut et la paume vers la camera : on le couche paume vers le sol.
local HAND_ROTATION = CFrame.Angles(math.rad(-90), 0, 0)
local FIST_MODEL_NAME = "PoingGeanteModele"
local GRAB_LIFT = 10
local GRAB_PALM_HEIGHT = 1.5
local RETURN_SECONDS = 0.3

type Grab = {
    character: Model,
    humanoid: Humanoid,
    root: BasePart,
    started: number,
    from: CFrame,
    center: Vector3,
    rootRotation: CFrame,
    handScale: number,
    palmOffset: Vector3,
    fist: Model?,
    fistParts: { BasePart },
    fistScale: number,
    fistOffset: Vector3,
    closed: boolean,
    screamed: boolean,
    previousStun: number?,
    stunUntil: number,
    onClose: () -> (),
    onScream: () -> (),
    onRelease: () -> (),
}

local HandChaseController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local edge: UIStroke
local rumble: Sound
local shadow: Part? = nil
local decal: Decal? = nil
local hand: Model? = nil
local handParts: { BasePart } = {}
local shown = Vector3.zero
local fade = 0
local grab: Grab? = nil
local returnFrom: CFrame? = nil
local returnStarted = 0

local function cloneHand(name: string, visibleName: string): (Model?, { BasePart })
    local template = ReplicatedStorage:FindFirstChild(name)
    if template == nil or not template:IsA("Model") then
        return nil, {}
    end
    local copy = template:Clone()
    local parts: { BasePart } = {}
    for _, descendant in copy:GetDescendants() do
        if descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound") then
            descendant:Destroy()
        elseif descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanQuery = false
            descendant.CanTouch = false
            descendant.LocalTransparencyModifier = 1
            table.insert(parts, descendant)
        end
    end
    if #parts == 0 then
        copy:Destroy()
        return nil, {}
    end
    copy.Name = visibleName
    copy.Parent = Workspace
    return copy, parts
end

local function buildHand(): ()
    if hand == nil then
        hand, handParts = cloneHand(HAND_MODEL_NAME, "MainGeanteVisible")
    end
end

local function showParts(parts: { BasePart }, opacity: number): ()
    for _, part in parts do
        part.LocalTransparencyModifier = 1 - opacity
    end
end

-- Repere dans le modele avant ScaleTo : la paume ouverte est sous le milieu des doigts (axe Y du modele).
-- Le poing est centre sur sa boite ; les deux reperes restent au meme endroit pendant le fondu.
local function gripOffset(model: Model?, open: boolean): Vector3
    if model == nil then
        return Vector3.zero
    end
    local box, size = model:GetBoundingBox()
    return model:GetPivot():PointToObjectSpace(box.Position) + Vector3.new(0, if open then -size.Y * 0.15 else 0, 0)
end

local function finishGrab(current: Grab, cancelled: boolean): ()
    grab = nil
    if current.fist then
        current.fist:Destroy()
    end
    local model = hand
    if model and model.Parent then
        model:ScaleTo(current.handScale)
        showParts(handParts, 1)
        returnFrom = model:GetPivot()
        returnStarted = os.clock()
    end
    if cancelled then
        -- Ne toucher qu'a l'ancien personnage, jamais a celui qui vient de reapparaitre.
        if current.character:GetAttribute("EtourdiJusqua") == current.stunUntil then
            current.character:SetAttribute("EtourdiJusqua", current.previousStun)
        end
        if current.closed and current.humanoid.Parent then
            current.humanoid.PlatformStand = false
            if current.humanoid.Health > 0 then
                current.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
    else
        current.onRelease()
    end
end

local function stepGrab(): ()
    local current = grab
    if current == nil then
        return
    end
    if
        player.Character ~= current.character
        or not current.character:IsDescendantOf(Workspace)
        or not current.root:IsDescendantOf(current.character)
        or not current.humanoid:IsDescendantOf(current.character)
        or current.humanoid.Health <= 0
    then
        finishGrab(current, true)
        return
    end
    local elapsed = os.clock() - current.started
    local duration = Tuning.HAND_GRAB_SECONDS
    local dive = duration / 3
    local close = duration / 9
    local center = current.center
    local model = hand
    if elapsed < dive then
        center = current.root.Position + Vector3.new(0, GRAB_PALM_HEIGHT, 0)
        current.center = center
        if model then
            local goal = CFrame.new(center) * HAND_ROTATION * CFrame.new(-current.palmOffset)
            model:PivotTo(current.from:Lerp(goal, (elapsed / dive) ^ 2))
            showParts(handParts, 1)
        end
    else
        if not current.closed then
            current.closed = true
            current.center = current.root.Position + Vector3.new(0, GRAB_PALM_HEIGHT, 0)
            current.onClose()
        end
        local lift = math.clamp((elapsed - dive) / (duration - dive), 0, 1)
        center = current.center + Vector3.new(0, GRAB_LIFT * lift * lift * (3 - 2 * lift), 0)
        local blend = math.clamp((elapsed - dive) / close, 0, 1)
        local squeeze = math.sin(blend * math.pi)
        local fist = current.fist
        if model then
            local scale = if fist then 1 else 1 - 0.22 * squeeze - 0.1 * blend
            model:ScaleTo(current.handScale * scale)
            model:PivotTo(CFrame.new(center) * HAND_ROTATION * CFrame.new(-current.palmOffset * scale))
            showParts(handParts, if fist then 1 - blend else 1)
        end
        if fist then
            local scale = 1 - 0.1 * squeeze
            fist:ScaleTo(current.fistScale * scale)
            fist:PivotTo(CFrame.new(center) * HAND_ROTATION * CFrame.new(-current.fistOffset * scale))
            showParts(current.fistParts, blend)
        end
        current.humanoid.PlatformStand = true
        current.root.AssemblyLinearVelocity = Vector3.zero
        current.root.AssemblyAngularVelocity = Vector3.zero
        current.root.CFrame = CFrame.new(center - Vector3.new(0, GRAB_PALM_HEIGHT, 0)) * current.rootRotation
    end
    if elapsed >= duration * (0.55 / 0.9) and not current.screamed then
        current.screamed = true
        current.onScream()
    end
    if elapsed >= duration then
        finishGrab(current, false)
    end
end

local function buildShadow(at: Vector3): ()
    local part = Instance.new("Part")
    part.Name = "OmbreMain"
    part.Size = Vector3.new(SHADOW_SIZE, 0.05, SHADOW_SIZE)
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Transparency = 1
    part.CFrame = CFrame.new(at)
    part.Parent = Workspace
    local image = Instance.new("Decal")
    image.Face = Enum.NormalId.Top
    image.Texture = SHADOW_TEXTURE
    image.Color3 = SHADOW_COLOR
    image.Transparency = 1
    image.Parent = part
    -- fumee noire qui roule sous la main, comme les zones d'ombre (Ui/Smoke)
    local smoke = Smoke.emitter(part, SHADOW_SIZE / 2, 10)
    smoke.Enabled = true
    shadow, decal, shown = part, image, at
    buildHand()
end

local function step(dt: number): ()
    stepGrab()
    local giant = Workspace:FindFirstChild("Geant")
    local isActive = giant ~= nil and giant:GetAttribute("MainActive") == true
    local goal = if giant then giant:GetAttribute("MainPosition") else nil
    fade = math.clamp(fade + (if isActive or grab ~= nil then dt / FADE_IN else -dt / FADE_OUT), 0, 1)
    if isActive and typeof(goal) == "Vector3" then
        if shadow == nil then
            buildShadow(goal)
        end
        shown = shown:Lerp(goal, math.clamp(dt * FOLLOW_RATE, 0, 1))
    end

    local part, image = shadow, decal
    if part == nil or image == nil then
        edge.Transparency = 1
        return
    end
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    local distance = math.huge
    if root and root:IsA("BasePart") then
        local offset = root.Position - shown
        distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
    end
    local near = 1 - math.clamp((distance - SHADOW_SIZE / 2) / NEAR_DISTANCE, 0, 1)
    local breathe = 1 + math.sin(os.clock() * 3) * 0.04
    local size = (SHADOW_SIZE + (SHADOW_NEAR_SIZE - SHADOW_SIZE) * near) * breathe
    part.Size = Vector3.new(size, 0.05, size)
    part.CFrame = CFrame.new(shown + Vector3.new(0, 0.08, 0))
    image.Transparency = 1 - fade * (SHADOW_MIN_OPACITY + (1 - SHADOW_MIN_OPACITY) * near)

    local model = hand
    if model and grab == nil then
        local t = os.clock()
        local height = HAND_HIGH + (HAND_LOW - HAND_HIGH) * near + math.sin(t * 2.5) * 1.5
        local sway = CFrame.Angles(0, math.sin(t * 1.3) * 0.15, math.sin(t * 2.1) * 0.05)
        local pose = CFrame.new(shown + Vector3.new(0, height, 0)) * sway * HAND_ROTATION
        local returning = returnFrom
        if returning then
            local alpha = math.clamp((os.clock() - returnStarted) / RETURN_SECONDS, 0, 1)
            pose = returning:Lerp(pose, alpha * alpha * (3 - 2 * alpha))
            if alpha >= 1 then
                returnFrom = nil
            end
        end
        model:PivotTo(pose)
        for _, handPart in handParts do
            handPart.LocalTransparencyModifier = 1 - fade
        end
    end

    local hear = 1 - math.clamp((distance - NEAR_DISTANCE) / (FAR_DISTANCE - NEAR_DISTANCE), 0, 1)
    rumble.Volume = RUMBLE_MAX_VOLUME * fade * hear
    if rumble.Volume > 0.01 then
        if not rumble.IsPlaying then
            rumble:Play()
        end
    elseif rumble.IsPlaying then
        rumble:Stop()
    end

    local targetId = if giant then giant:GetAttribute("MainCibleUserId") else nil
    if isActive and targetId == player.UserId then
        local pulse = (math.sin(os.clock() * 6) + 1) / 2
        edge.Transparency = 0.3 + 0.35 * pulse
    else
        edge.Transparency = 1
    end

    if fade <= 0 and not isActive and grab == nil then
        part:Destroy()
        shadow, decal = nil, nil
        if hand then
            hand:Destroy()
            hand = nil
            handParts = {}
        end
        returnFrom = nil
    end
end

function HandChaseController:IsGrabbing(): boolean
    return grab ~= nil
end

-- EventController fournit les effets : aucune dependance inverse vers ce controleur.
function HandChaseController:Grab(
    character: Model,
    humanoid: Humanoid,
    root: BasePart,
    onClose: () -> (),
    onScream: () -> (),
    onRelease: () -> ()
): ()
    if grab ~= nil or humanoid.Health <= 0 or player.Character ~= character then
        return
    end
    local hadHand = hand ~= nil and fade > 0
    if shadow == nil then
        buildShadow(root.Position - Vector3.new(0, 3, 0))
    end
    buildHand()
    local model = hand
    local from = CFrame.new(root.Position + Vector3.new(0, HAND_HIGH, 0)) * HAND_ROTATION
    if model then
        if hadHand then
            from = model:GetPivot()
        end
        model:PivotTo(from)
        showParts(handParts, 1)
    end
    local fist, fistParts = cloneHand(FIST_MODEL_NAME, "PoingGeanteVisible")
    local now = os.clock()
    local previous = character:GetAttribute("EtourdiJusqua")
    local previousStun = if typeof(previous) == "number" then previous else nil
    local stunUntil = math.max(previousStun or 0, now + Tuning.HAND_GRAB_SECONDS + Tuning.CATCH_STUN_SECONDS)
    character:SetAttribute("EtourdiJusqua", stunUntil)
    returnFrom = nil
    fade = 1
    grab = {
        character = character,
        humanoid = humanoid,
        root = root,
        started = now,
        from = from,
        center = root.Position + Vector3.new(0, GRAB_PALM_HEIGHT, 0),
        rootRotation = root.CFrame.Rotation,
        handScale = if model then model:GetScale() else 1,
        palmOffset = gripOffset(model, true),
        fist = fist,
        fistParts = fistParts,
        fistScale = if fist then fist:GetScale() else 1,
        fistOffset = gripOffset(fist, false),
        closed = false,
        screamed = false,
        previousStun = previousStun,
        stunUntil = stunUntil,
        onClose = onClose,
        onScream = onScream,
        onRelease = onRelease,
    }
end

function HandChaseController:Init(): () end

function HandChaseController:Start(): ()
    gui = Instance.new("ScreenGui")
    gui.Name = "MainGeante"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 7
    gui.Parent = player:WaitForChild("PlayerGui")

    -- Bord rouge : le trait est dessine autour du cadre, qui est donc retreci de son epaisseur.
    local frame = Instance.new("Frame")
    frame.Name = "BordCible"
    frame.BackgroundTransparency = 1
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.Size = UDim2.new(1, -EDGE_THICKNESS * 2, 1, -EDGE_THICKNESS * 2)
    frame.Parent = gui
    edge = Instance.new("UIStroke")
    edge.Color = Theme.RED
    edge.Thickness = EDGE_THICKNESS
    edge.Transparency = 1
    edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    edge.Parent = frame

    rumble = Instance.new("Sound")
    rumble.Name = "GrondementMain"
    rumble.SoundId = RUMBLE_ID
    rumble.Looped = true
    rumble.Volume = 0
    rumble.SoundGroup = Sfx.group("Effets")
    rumble.Parent = SoundService

    local notice = Remotes.Get("ChaseNotice") :: RemoteEvent
    notice.OnClientEvent:Connect(function(kind: string, cash: number)
        if kind == "survived" then
            Sfx.play("fanfare")
            Theme.toast(gui, string.format("Tu as échappé au bébé ! +%d tétines", cash), Theme.GREEN)
        end
    end)

    RunService.RenderStepped:Connect(step)
end

return HandChaseController
