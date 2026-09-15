--!strict

--[[
    Screamer
    Demande utilisateur du 15/09 : quand le bebe attrape le joueur, sa tete qui pleure fonce sur l'ecran (vitesse
    moyenne), avec un rire d'enfant inquietant. Local au joueur attrape (le remote Caught ne va qu'a lui).

    - ScreenGui dedie au-dessus de tout le HUD, cree a la demande ;
    - approche de APPROACH secondes : la camera du ViewportFrame avance de FAR a NEAR fois la taille du bebe devant
      son visage (acceleration Quad In), tremblement qui grandit, flash rouge a l'impact ;
    - tenue HOLD, fondu FADE, puis tout est detruit ; un seul screamer a la fois ;
    - rire « Baby Laughing Giggling Breathing 6 Months Old 10 » (Pro Sound Effects), ralenti et reverbere, dans le
      groupe « Effets » du menu Parametres.

        if Screamer.isBabyReason(reason) then Screamer.play() end
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local BabyHead = require(script.Parent.BabyHead)
local Sfx = require(script.Parent.Sfx)

-- Raisons du remote Caught qui viennent du bebe (GiantService:Catch, main geante « hand » comprise) ; mom, dog et
-- hit n'en sont pas.
local BABY_REASONS = { moved = true, jumped = true, seen = true, hand = true }

local APPROACH = 0.7
local HOLD = 0.3
local FADE = 0.45
local FAR = 3.2
-- 0,35 ne montrait plus que les yeux (capture screamer-moved du 15/09) : le visage entier doit rester lisible.
local NEAR = 0.55
local SHAKE_PIXELS = 14
-- ViewportFrame un peu plus grand que l'ecran : le tremblement ne decouvre pas le jeu sur les bords.
local OVERSIZE = 1.08
-- Fond presque noir : a 0,35 le HUD restait lisible autour de la tete (captures screamer-a/b du 15/09).
local BACKDROP_TRANSPARENCY = 0.06

local LAUGH_ID = "rbxassetid://9125368136"
local LAUGH_VOLUME = 0.7
local LAUGH_SPEED = 0.8

local Screamer = {}

local playing = false

function Screamer.isBabyReason(reason: unknown): boolean
    return typeof(reason) == "string" and BABY_REASONS[reason] == true
end

local function laugh(): ()
    local s = Instance.new("Sound")
    s.Name = "RireScreamer"
    s.SoundId = LAUGH_ID
    s.Volume = LAUGH_VOLUME
    s.PlaybackSpeed = LAUGH_SPEED
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

function Screamer.play(): ()
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

    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "Bebe"
    viewport.BackgroundTransparency = 1
    viewport.Size = UDim2.fromScale(OVERSIZE, OVERSIZE)
    viewport.AnchorPoint = Vector2.new(0.5, 0.5)
    viewport.Position = UDim2.fromScale(0.5, 0.5)
    viewport.Ambient = Color3.fromRGB(175, 165, 185)
    viewport.LightColor = Color3.fromRGB(255, 235, 225)
    viewport.Parent = group

    local flash = Instance.new("Frame")
    flash.Name = "Flash"
    flash.BackgroundColor3 = Color3.fromRGB(200, 20, 40)
    flash.BackgroundTransparency = 1
    flash.BorderSizePixel = 0
    flash.Size = UDim2.fromScale(1, 1)
    flash.ZIndex = 2
    flash.Parent = group

    local head = BabyHead.build(viewport)
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

    laugh()
    TweenService:Create(group, TweenInfo.new(APPROACH * 0.6), { BackgroundTransparency = BACKDROP_TRANSPARENCY }):Play()

    local started = os.clock()
    local impacted = false
    local connection: RBXScriptConnection? = nil
    connection = RunService.RenderStepped:Connect(function()
        local t = os.clock() - started
        local a = math.clamp(t / APPROACH, 0, 1)
        local eased = a * a
        local distance = (FAR + (NEAR - FAR) * eased) * head.size.Y
        local roll = math.rad(math.sin(t * 29) * 4 * eased)
        camera.CFrame = CFrame.lookAt(head.point + head.frame.LookVector * distance, head.point, head.frame.UpVector)
            * CFrame.Angles(0, 0, roll)
        local shake = SHAKE_PIXELS * eased
        viewport.Position = UDim2.new(0.5, math.sin(t * 47) * shake, 0.5, math.cos(t * 43) * shake)
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
