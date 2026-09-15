--!strict

--[[
    Screamer
    Demande utilisateur du 15/09 : quand le bebe attrape le joueur, sa tete qui pleure fonce sur l'ecran (vitesse
    moyenne), avec un rire d'enfant inquietant ; meme chose avec la tete de maman quand elle attrape quelqu'un. Local
    au joueur attrape (le remote Caught ne va qu'a lui).

    - ScreenGui dedie au-dessus de tout le HUD, cree a la demande ;
    - approche de APPROACH secondes : la camera du ViewportFrame avance de far a near fois la taille de reference
      devant le visage (acceleration Quad In), tremblement qui grandit, flash rouge a l'impact ;
    - tenue HOLD, fondu FADE, puis tout est detruit ; un seul screamer a la fois ;
    - son : bebe = rire « Baby Laughing Giggling Breathing 6 Months Old 10 » ralenti et reverbere ; maman = cri court
      « Female Voices 2 Women Short Screams Yells 1 » un peu plus grave (Pro Sound Effects) ; groupe « Effets ».

        if Screamer.isScareReason(reason) then Screamer.play(if reason == "mom" then "mom" else "baby") end
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BabyHead = require(script.Parent.BabyHead)
local Sfx = require(script.Parent.Sfx)

-- Raisons du remote Caught qui viennent du bebe (GiantService:Catch, main geante « hand » comprise) ; mom, dog et
-- hit n'en sont pas.
local BABY_REASONS = { moved = true, jumped = true, seen = true, hand = true }

local APPROACH = 0.7
local HOLD = 0.3
local FADE = 0.45
local SHAKE_PIXELS = 14
-- ViewportFrame un peu plus grand que l'ecran : le tremblement ne decouvre pas le jeu sur les bords.
local OVERSIZE = 1.08
-- Fond presque noir : a 0,35 le HUD restait lisible autour de la tete (captures screamer-a/b du 15/09).
local BACKDROP_TRANSPARENCY = 0.06

type Head = { point: Vector3, frame: CFrame, unit: number }
type Kind = {
    far: number,
    near: number,
    soundId: string,
    volume: number,
    speed: number,
    ambient: Color3,
    build: (ViewportFrame) -> Head?,
    -- Image 2D a la place du modele 3D (tete de maman en colere choisie par l'utilisateur) ; "" = modele 3D.
    imageId: string?,
}

-- Image « femme jumpscare » de l'utilisateur, televersee sur Roblox (rbxassetid://...) ; vide tant qu'elle ne l'est pas.
local MOM_IMAGE_ID = "rbxassetid://97997221493943"
-- Proportions de l'image (largeur / hauteur) et hauteur du visage dans l'image (0 = haut) : le zoom se fait sur lui.
-- (image recadree en carre de 1024 px sur le visage, assets/concepts/drive/maman/maman-jumpscare-visage.png)
local MOM_IMAGE_RATIO = 1
local MOM_IMAGE_FACE_Y = 0.5
-- Hauteur de l'image en fraction de l'ecran, au debut et a l'impact (visage en tres gros plan).
local IMAGE_START = 0.3
local IMAGE_END = 1.9

-- Maman : copie du modele « Maman » range dans le modele de la porte (tag MomDoor), posee a PoseVisible (face a la
-- chambre). Tete = haut de la boite englobante ; MOM_FACE_SIGN inverse l'avant si le modele regarde vers -LookVector.
local MOM_FACE_SIGN = 1
local MOM_HEAD_HEIGHT = 0.37

local function buildMom(viewport: ViewportFrame): Head?
    for _, hinge in CollectionService:GetTagged("MomDoor") do
        local door = hinge.Parent
        local mom = if door and hinge:IsDescendantOf(Workspace) then door:FindFirstChild("Maman") else nil
        if mom and mom:IsA("Model") then
            local clone = mom:Clone()
            for _, descendant in clone:GetDescendants() do
                if
                    descendant:IsA("Light")
                    or descendant:IsA("LuaSourceContainer")
                    or descendant:IsA("ParticleEmitter")
                    or descendant:IsA("Sound")
                then
                    descendant:Destroy()
                elseif descendant:IsA("BasePart") then
                    descendant.Anchored = true
                end
            end
            local pose = mom:GetAttribute("PoseVisible")
            if typeof(pose) == "CFrame" then
                clone:PivotTo(pose)
            end
            clone.Parent = viewport
            local center, size = clone:GetBoundingBox()
            local frame =
                CFrame.lookAt(center.Position, center.Position + center.LookVector * MOM_FACE_SIGN, center.UpVector)
            return { point = center.Position + center.UpVector * size.Y * MOM_HEAD_HEIGHT, frame = frame, unit = size.Y }
        end
    end
    return nil
end

local function buildBaby(viewport: ViewportFrame): Head?
    local head = BabyHead.build(viewport)
    return if head then { point = head.point, frame = head.frame, unit = head.size.Y } else nil
end

local KINDS: { [string]: Kind } = {
    -- 0,35 ne montrait plus que les yeux (capture screamer-moved du 15/09) : le visage entier doit rester lisible.
    baby = {
        far = 3.2,
        near = 0.55,
        soundId = "rbxassetid://9125368136",
        volume = 0.7,
        speed = 0.8,
        ambient = Color3.fromRGB(175, 165, 185),
        build = buildBaby,
    },
    mom = {
        imageId = MOM_IMAGE_ID,
        far = 1.8,
        near = 0.2,
        soundId = "rbxassetid://9114399356",
        volume = 0.6,
        speed = 0.9,
        ambient = Color3.fromRGB(185, 160, 150),
        build = buildMom,
    },
}

local Screamer = {}

local playing = false

-- Image de maman chargee des le demarrage : au premier jumpscare, le visage n'apparaissait pas encore (capture du
-- 15/09, fond noir seul pendant l'approche).
task.spawn(function()
    if MOM_IMAGE_ID ~= "" then
        local preload = Instance.new("ImageLabel")
        preload.Image = MOM_IMAGE_ID
        pcall(function()
            game:GetService("ContentProvider"):PreloadAsync({ preload })
        end)
    end
end)

function Screamer.isBabyReason(reason: unknown): boolean
    return typeof(reason) == "string" and BABY_REASONS[reason] == true
end

-- Captures qui declenchent un screamer (et remplacent le « boing » comique) : bebe et maman.
function Screamer.isScareReason(reason: unknown): boolean
    return Screamer.isBabyReason(reason) or reason == "mom"
end

local function scream(kind: Kind): ()
    local s = Instance.new("Sound")
    s.Name = "SonScreamer"
    s.SoundId = kind.soundId
    s.Volume = kind.volume
    s.PlaybackSpeed = kind.speed
    s.SoundGroup = Sfx.group("Effets")
    local reverb = Instance.new("ReverbSoundEffect")
    reverb.DecayTime = 1.6
    reverb.Density = 0.8
    reverb.Diffusion = 0.9
    reverb.DryLevel = 0
    reverb.WetLevel = -4
    reverb.Parent = s
    s.Parent = SoundService
    s.Ended:Connect(function()
        s:Destroy()
    end)
    -- filet de securite si le son ne se charge pas (Ended ne viendrait jamais)
    task.delay(10, function()
        if s.Parent then
            s:Destroy()
        end
    end)
    s:Play()
end

-- kindName : "baby" (defaut) ou "mom".
function Screamer.play(kindName: string?): ()
    local kind = KINDS[kindName or "baby"] or KINDS.baby
    if playing then
        return
    end
    local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui == nil then
        return
    end
    playing = true

    local screen = Instance.new("ScreenGui")
    screen.Name = "Screamer"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 100
    screen.Parent = playerGui

    local group = Instance.new("CanvasGroup")
    group.Name = "Tete"
    group.BackgroundColor3 = Color3.new(0, 0, 0)
    group.BackgroundTransparency = 1
    group.BorderSizePixel = 0
    group.Size = UDim2.fromScale(1, 1)
    group.Parent = screen

    local flash = Instance.new("Frame")
    flash.Name = "Flash"
    flash.BackgroundColor3 = Color3.fromRGB(200, 20, 40)
    flash.BackgroundTransparency = 1
    flash.BorderSizePixel = 0
    flash.Size = UDim2.fromScale(1, 1)
    flash.ZIndex = 2
    flash.Parent = group

    -- update(eased, t, shake) : place la tete a chaque image selon l'avancement de l'approche.
    local update: (number, number, number) -> ()
    local imageId = kind.imageId
    if imageId and imageId ~= "" then
        -- Image 2D : elle grossit autour du visage (AnchorPoint sur le visage), hauteur relative a l'ecran.
        local image = Instance.new("ImageLabel")
        image.Name = "Visage"
        image.BackgroundTransparency = 1
        image.Image = imageId
        image.ScaleType = Enum.ScaleType.Stretch
        image.SizeConstraint = Enum.SizeConstraint.RelativeYY
        image.AnchorPoint = Vector2.new(0.5, MOM_IMAGE_FACE_Y)
        image.Position = UDim2.fromScale(0.5, 0.5)
        image.Parent = group
        update = function(eased: number, t: number, shake: number): ()
            local height = IMAGE_START + (IMAGE_END - IMAGE_START) * eased
            image.Size = UDim2.fromScale(height * MOM_IMAGE_RATIO, height)
            image.Rotation = math.sin(t * 29) * 3 * eased
            image.Position = UDim2.new(0.5, math.sin(t * 47) * shake, 0.5, math.cos(t * 43) * shake)
        end
    else
        local viewport = Instance.new("ViewportFrame")
        viewport.Name = "Visage"
        viewport.BackgroundTransparency = 1
        viewport.Size = UDim2.fromScale(OVERSIZE, OVERSIZE)
        viewport.AnchorPoint = Vector2.new(0.5, 0.5)
        viewport.Position = UDim2.fromScale(0.5, 0.5)
        viewport.Ambient = kind.ambient
        viewport.LightColor = Color3.fromRGB(255, 235, 225)
        viewport.Parent = group
        local head = kind.build(viewport)
        if head == nil then
            screen:Destroy()
            playing = false
            return
        end
        local camera = Instance.new("Camera")
        camera.FieldOfView = 40
        camera.Parent = viewport
        viewport.CurrentCamera = camera
        viewport.LightDirection = -head.frame.LookVector
        update = function(eased: number, t: number, shake: number): ()
            local distance = (kind.far + (kind.near - kind.far) * eased) * head.unit
            local roll = math.rad(math.sin(t * 29) * 4 * eased)
            camera.CFrame = CFrame.lookAt(
                head.point + head.frame.LookVector * distance,
                head.point,
                head.frame.UpVector
            ) * CFrame.Angles(0, 0, roll)
            viewport.Position = UDim2.new(0.5, math.sin(t * 47) * shake, 0.5, math.cos(t * 43) * shake)
        end
    end

    scream(kind)
    -- Image 2D : fond noir complet presque tout de suite, sinon les bords du carre de l'image se voyaient sur la
    -- chambre assombrie (capture du 15/09).
    local usesImage = imageId ~= nil and imageId ~= ""
    TweenService:Create(
        group,
        TweenInfo.new(if usesImage then 0.12 else APPROACH * 0.6),
        { BackgroundTransparency = if usesImage then 0 else BACKDROP_TRANSPARENCY }
    ):Play()

    local started = os.clock()
    local impacted = false
    local connection: RBXScriptConnection? = nil
    connection = RunService.RenderStepped:Connect(function()
        local t = os.clock() - started
        local a = math.clamp(t / APPROACH, 0, 1)
        local eased = a * a
        update(eased, t, SHAKE_PIXELS * eased)
        if a >= 1 and not impacted then
            impacted = true
            flash.BackgroundTransparency = 0.45
            TweenService:Create(flash, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
        end
        if t >= APPROACH + HOLD + FADE and connection then
            connection:Disconnect()
            screen:Destroy()
            playing = false
        end
    end)
    task.delay(APPROACH + HOLD, function()
        if screen.Parent then
            TweenService:Create(group, TweenInfo.new(FADE, Enum.EasingStyle.Sine), { GroupTransparency = 1 }):Play()
        end
    end)
end

return Screamer
