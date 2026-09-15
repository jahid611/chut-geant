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

local Sfx = require(script.Parent.Parent.Ui.Sfx)
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

local HandChaseController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local edge: UIStroke
local rumble: Sound
local shadow: Part? = nil
local decal: Decal? = nil
local shown = Vector3.zero
local fade = 0

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
    shadow, decal, shown = part, image, at
end

local function step(dt: number): ()
    local giant = Workspace:FindFirstChild("Geant")
    local isActive = giant ~= nil and giant:GetAttribute("MainActive") == true
    local goal = if giant then giant:GetAttribute("MainPosition") else nil
    fade = math.clamp(fade + (if isActive then dt / FADE_IN else -dt / FADE_OUT), 0, 1)
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

    if fade <= 0 and not isActive then
        part:Destroy()
        shadow, decal = nil, nil
    end
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
