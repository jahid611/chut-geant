--!strict

--[[
    BabyPovController
    Bulle « POV du bébé » (retour utilisateur du 15/09) : tant que le bebe pleure (GiantState Waking ou Hunting,
    regards « IL REGARDE » compris), une grosse bulle ronde en bas a gauche montre sa vraie tete en gros, vue du
    dessus juste au-dessus du visage (ViewportFrame avec une copie du modele workspace.Geant.Pleure), qui tremble,
    avec des larmes et une bordure rouge qui pulse. Dessous, le temps de pleur restant (endsAt du serveur) en gros
    chiffres avec l'icone du bebe. Disparait en fondu quand il se rendort.

    Placement : a droite de la colonne des menus (qui est au milieu a gauche), en bas, loin de la barre de pouvoirs
    et de la carte du jouet porte (en bas au centre).
    Camera : repere du modele (voir BabyVisualService) ; tete = cote UpVector de sa boite, visage = LookVector.
    A verifier par capture.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local BabyHead = require(script.Parent.Parent.Ui.BabyHead)
local Theme = require(script.Parent.Parent.Ui.Theme)

local BUBBLE = 300
local PILL_HEIGHT = 64

local BabyPovController = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local root: CanvasGroup? = nil
local token = 0

local function hide(): ()
    token += 1
    local current = root
    root = nil
    if current == nil then
        return
    end
    local tween = TweenService:Create(current, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { GroupTransparency = 1 })
    tween.Completed:Connect(function()
        current:Destroy()
    end)
    tween:Play()
end

local function tear(parent: Frame, x: number, delay: number, myToken: number): ()
    local drop = Instance.new("Frame")
    drop.Name = "Larme"
    drop.BackgroundColor3 = Color3.fromRGB(140, 205, 255)
    drop.BackgroundTransparency = 0.15
    drop.BorderSizePixel = 0
    drop.Size = UDim2.fromOffset(14, 24)
    drop.AnchorPoint = Vector2.new(0.5, 0)
    drop.ZIndex = 5
    drop.Parent = parent
    Theme.corner(drop, 7)
    task.spawn(function()
        task.wait(delay)
        while token == myToken and drop.Parent do
            drop.Position = UDim2.fromScale(x, 0.46)
            drop.BackgroundTransparency = 0.15
            local fall = TweenService:Create(drop, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.fromScale(x, 0.8),
                BackgroundTransparency = 1,
            })
            fall:Play()
            task.wait(1.1)
        end
    end)
end

local function show(endsAt: number): ()
    local existing = root
    if existing then
        existing:SetAttribute("EndsAt", endsAt)
        return
    end
    local screen = gui
    local giant = Workspace:FindFirstChild("Geant")
    local crying = if giant then giant:FindFirstChild("Pleure") else nil
    if screen == nil or crying == nil or not crying:IsA("Model") then
        return
    end
    token += 1
    local myToken = token

    local group = Instance.new("CanvasGroup")
    group.Name = "PovBebe"
    group.BackgroundTransparency = 1
    group.GroupTransparency = 1
    group.Size = UDim2.fromOffset(BUBBLE, BUBBLE + PILL_HEIGHT + 10)
    group.Position = UDim2.new(0, 110, 1, -24)
    group.AnchorPoint = Vector2.new(0, 1)
    group:SetAttribute("EndsAt", endsAt)
    group.Parent = screen
    Theme.fit(group, Theme.HUD_FACTOR)
    root = group

    local bubble = Instance.new("Frame")
    bubble.Name = "Bulle"
    bubble.BackgroundColor3 = Color3.fromRGB(34, 24, 56)
    bubble.Size = UDim2.fromOffset(BUBBLE, BUBBLE)
    bubble.Position = UDim2.fromScale(0.5, 0)
    bubble.AnchorPoint = Vector2.new(0.5, 0)
    bubble.ClipsDescendants = true
    bubble.Parent = group
    Theme.corner(bubble, BUBBLE // 2)
    local ring = Theme.stroke(bubble, 8, Theme.RED)

    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "Tete"
    viewport.BackgroundTransparency = 1
    viewport.Size = UDim2.fromScale(1, 1)
    viewport.Ambient = Color3.fromRGB(175, 170, 195)
    viewport.LightColor = Color3.fromRGB(255, 240, 230)
    viewport.Parent = bubble
    Theme.corner(viewport, BUBBLE // 2)

    -- copie du bebe qui pleure dans sa pose couchee de reference (Ui/BabyHead)
    local head = BabyHead.build(viewport)
    if head == nil then
        hide()
        return
    end
    -- 0,2 / 0,55 cadrait le front de trop pres (capture du 15/09) : visage entier, un peu plus loin.
    local eye = head.point + head.frame.LookVector * math.max(head.size.Y * 0.8, 4)
    local camera = Instance.new("Camera")
    camera.FieldOfView = 40
    camera.CFrame = CFrame.lookAt(eye, head.point, head.frame.UpVector)
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    viewport.LightDirection = -head.frame.LookVector

    tear(bubble, 0.4, 0, myToken)
    tear(bubble, 0.6, 0.5, myToken)

    -- Temps de pleur restant
    local pill = Instance.new("Frame")
    pill.Name = "Temps"
    pill.BackgroundColor3 = Color3.fromRGB(30, 22, 48)
    pill.Size = UDim2.fromOffset(200, PILL_HEIGHT)
    pill.Position = UDim2.fromScale(0.5, 1)
    pill.AnchorPoint = Vector2.new(0.5, 1)
    pill.Parent = group
    Theme.corner(pill, PILL_HEIGHT // 2)
    Theme.stroke(pill, 3, Theme.RED)
    Theme.image(pill, "Icone", "bebeDort", UDim2.fromOffset(48, 48), UDim2.new(0, 10, 0.5, 0), Vector2.new(0, 0.5))
    local label = Theme.text(
        pill,
        "Secondes",
        "",
        UDim2.new(1, -74, 1, -10),
        UDim2.new(0, 66, 0.5, 0),
        Theme.WHITE,
        Vector2.new(0, 0.5)
    )
    label.TextScaled = true

    TweenService:Create(group, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { GroupTransparency = 0 }):Play()
    task.spawn(function()
        local started = os.clock()
        while token == myToken and group.Parent do
            local t = os.clock() - started
            -- tremblement du cri et pulsation de la bordure
            viewport.Position = UDim2.fromOffset(math.sin(t * 41) * 3, math.cos(t * 37) * 3)
            local pulse = (math.sin(t * 6) + 1) / 2
            ring.Color = Theme.RED:Lerp(Color3.fromRGB(255, 205, 210), pulse)
            ring.Thickness = 6 + 5 * pulse
            local ends = group:GetAttribute("EndsAt")
            local left = if typeof(ends) == "number" then ends - Workspace:GetServerTimeNow() else 0
            label.Text = string.format("%d s", math.max(math.ceil(left), 0))
            task.wait()
        end
    end)
end

function BabyPovController:Init(): () end

function BabyPovController:Start(): ()
    local screen = Instance.new("ScreenGui")
    screen.Name = "PovBebe"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 4
    screen.Parent = player:WaitForChild("PlayerGui")
    gui = screen

    local giantState = Remotes.Get("GiantState") :: RemoteEvent
    giantState.OnClientEvent:Connect(function(state: string, endsAt: number)
        if state == "Waking" or state == "Hunting" then
            show(if typeof(endsAt) == "number" then endsAt else 0)
        else
            hide()
        end
    end)
end

return BabyPovController
