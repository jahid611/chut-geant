--!strict

--[[
    TutorialController
    Affichage du tutoriel des nouveaux joueurs (TutorialService, Shared/Tutorial) :
    - bulle de dialogue a droite de l'ecran (icone, titre, phrase courte, points d'avancement, bouton pour les
      etapes d'information, « Passer le tutoriel » discret sous la bulle) ;
    - fleche 3D (Beam lumineux depuis le joueur + fleche qui flotte au-dessus) vers l'attribut TutorialTarget ;
    - surbrillance qui pulse autour de l'element d'interface vise (compteur de tetines, bouton boutique, jauge,
      colonne des menus) avec une fleche qui le montre ;
    - fin : recompense affichee et petite fanfare.
    Rien ne bloque le jeu ; tout se cache pendant les menus (MenusOuverts), la vue coffre (VueCoffre) et dans la
    cuisine (Piece == "Cuisine" : les etapes parlent du bebe, c'est le chien qui y dort).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tutorial = require(Shared:WaitForChild("Tutorial"))

local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

local STEP_COUNT = Tutorial.FINAL_STEP - 1

local TutorialController = {}

local player = Players.LocalPlayer

-- Chemin d'objets dans PlayerGui (ex. { "HUD", "Boutons", "Boutique" }).
local function findUi(path: { string }): GuiObject?
    local node: Instance? = player:FindFirstChild("PlayerGui")
    for _, name in path do
        if node == nil then
            return nil
        end
        node = node:FindFirstChild(name, true)
    end
    return if node and node:IsA("GuiObject") then node else nil
end

function TutorialController:Init(): () end

function TutorialController:Start(): ()
    local remote = Remotes.Get("TutorialAction") :: RemoteEvent

    local gui = Instance.new("ScreenGui")
    gui.Name = "Tutoriel"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 8
    gui.Enabled = false
    gui.Parent = player:WaitForChild("PlayerGui")

    -- Bulle, a droite au milieu (libre : ni HUD, ni barres du bas, ni colonne des menus)
    local holder = Instance.new("Frame")
    holder.Name = "Bulle"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(470, 206)
    holder.Position = UDim2.new(1, -16, 0.46, 0)
    holder.AnchorPoint = Vector2.new(1, 0.5)
    holder.Parent = gui
    -- a HUD_FACTOR x 1,15 la bulle etait illisible en jeu (capture du 16/09) : nettement plus grande
    local holderScale = Theme.fit(holder, Theme.HUD_FACTOR * 1.9)

    local panel = Theme.panel(holder, "Panneau", UDim2.new(1, 0, 0, 172), UDim2.fromScale(0, 0), Vector2.zero)
    panel.ClipsDescendants = true
    local iconSlot = Instance.new("Frame")
    iconSlot.Name = "Emplacement"
    iconSlot.BackgroundTransparency = 1
    iconSlot.Size = UDim2.fromOffset(104, 104)
    iconSlot.Position = UDim2.new(0, 14, 0.5, -8)
    iconSlot.AnchorPoint = Vector2.new(0, 0.5)
    iconSlot.Parent = panel
    local title = Theme.label(
        panel,
        "Titre",
        "",
        UDim2.new(1, -146, 0, 40),
        UDim2.fromOffset(130, 12),
        Theme.YELLOW,
        Vector2.zero,
        32,
        Enum.TextXAlignment.Left
    )
    local text = Theme.label(
        panel,
        "Texte",
        "",
        UDim2.new(1, -146, 0, 50),
        UDim2.fromOffset(130, 54),
        Theme.WHITE,
        Vector2.zero,
        24,
        Enum.TextXAlignment.Left
    )
    text.TextWrapped = true

    -- Points d'avancement (etapes 1 a 6)
    local pips = Instance.new("Frame")
    pips.Name = "Points"
    pips.BackgroundTransparency = 1
    pips.Size = UDim2.fromOffset(STEP_COUNT * 22, 14)
    pips.Position = UDim2.new(0, 132, 1, -26)
    pips.AnchorPoint = Vector2.new(0, 0.5)
    pips.Parent = panel
    local dots: { Frame } = {}
    for i = 1, STEP_COUNT do
        local dot = Instance.new("Frame")
        dot.Name = "Point" .. i
        dot.BorderSizePixel = 0
        dot.Size = UDim2.fromOffset(14, 14)
        dot.Position = UDim2.fromOffset((i - 1) * 22, 0)
        dot.Parent = pips
        Theme.corner(dot, 7)
        table.insert(dots, dot)
    end

    -- Recompense de fin (tetines + traînee), a la place des points
    local rewards = Instance.new("Frame")
    rewards.Name = "Recompenses"
    rewards.BackgroundTransparency = 1
    rewards.Size = UDim2.fromOffset(170, 40)
    rewards.Position = UDim2.new(0, 130, 1, -28)
    rewards.AnchorPoint = Vector2.new(0, 0.5)
    rewards.Visible = false
    rewards.Parent = panel
    Theme.icon(rewards, "Tetine", "tetine", UDim2.fromOffset(38, 38), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5))
    Theme.label(
        rewards,
        "Montant",
        "+" .. Theme.formatNumber(Tutorial.REWARD_CASH),
        UDim2.fromOffset(84, 30),
        UDim2.new(0, 42, 0.5, 0),
        Theme.YELLOW,
        Vector2.new(0, 0.5),
        24,
        Enum.TextXAlignment.Left
    )
    Theme.icon(
        rewards,
        "Trainee",
        "iconeTraineeArc",
        UDim2.fromOffset(38, 38),
        UDim2.new(0, 128, 0.5, 0),
        Vector2.new(0, 0.5),
        Theme.PINK
    )

    local action = Theme.button(
        panel,
        "Action",
        "Suivant",
        Theme.GREEN,
        UDim2.fromOffset(150, 46),
        UDim2.new(1, -14, 1, -12),
        Vector2.new(1, 1)
    )
    local skip = Instance.new("TextButton")
    skip.Name = "Passer"
    skip.BackgroundTransparency = 1
    skip.Text = "Passer le tutoriel"
    skip.Font = Theme.FONT
    skip.TextScaled = true
    skip.TextColor3 = Theme.SOFT_TEXT
    skip.Size = UDim2.fromOffset(170, 24)
    skip.Position = UDim2.new(1, -10, 0, 180)
    skip.AnchorPoint = Vector2.new(1, 0)
    skip.Parent = holder
    Theme.limitText(skip, 20)

    -- Surbrillance d'un element d'interface + fleche qui le montre
    local ring = Instance.new("Frame")
    ring.Name = "Surbrillance"
    ring.BackgroundTransparency = 1
    ring.Visible = false
    ring.Parent = gui
    Theme.corner(ring, 22)
    local ringStroke = Theme.stroke(ring, 5, Theme.YELLOW)
    local pointer =
        Theme.icon(gui, "FlecheUi", "fleche", UDim2.fromOffset(58, 58), UDim2.fromOffset(0, 0), Vector2.new(0.5, 0.5))
    pointer.Visible = false

    -- Fleche 3D : faisceau depuis le joueur et fleche qui flotte au-dessus de la cible
    local targetPart = Instance.new("Part")
    targetPart.Name = "CibleTutoriel"
    targetPart.Anchored = true
    targetPart.CanCollide = false
    targetPart.CanQuery = false
    targetPart.CanTouch = false
    targetPart.Transparency = 1
    targetPart.Size = Vector3.new(1, 1, 1)
    local targetAttachment = Instance.new("Attachment")
    targetAttachment.Parent = targetPart
    local beam = Instance.new("Beam")
    beam.Name = "FaisceauTutoriel"
    beam.Attachment1 = targetAttachment
    beam.Color = ColorSequence.new(Theme.YELLOW, Theme.PINK)
    beam.Transparency = NumberSequence.new(0.15, 0.5)
    beam.LightEmission = 1
    beam.FaceCamera = true
    beam.Width0 = 0.9
    beam.Width1 = 0.5
    beam.Segments = 12
    beam.CurveSize0 = 6
    beam.CurveSize1 = -2
    beam.Parent = targetPart
    local board = Instance.new("BillboardGui")
    board.Name = "FlecheCible"
    board.Size = UDim2.fromScale(5, 5)
    board.StudsOffset = Vector3.new(0, 6, 0)
    board.AlwaysOnTop = true
    board.LightInfluence = 0
    board.MaxDistance = 1000
    board.Parent = targetPart
    local boardArrow =
        Theme.icon(board, "Fleche", "fleche", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
    boardArrow.Rotation = 90

    local currentStep: number? = nil

    local function visibleNow(): boolean
        local menus = player:GetAttribute("MenusOuverts")
        local menuOpen = typeof(menus) == "number" and menus > 0
        return currentStep ~= nil
            and not menuOpen
            and player:GetAttribute("VueCoffre") ~= true
            and player:GetAttribute("Piece") ~= "Cuisine"
    end

    local function refreshTarget(): ()
        local target = player:GetAttribute("TutorialTarget")
        local character = player.Character
        local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
        if typeof(target) ~= "Vector3" or root == nil or not visibleNow() then
            targetPart.Parent = nil
            return
        end
        local start = root:FindFirstChild("DepartTutoriel")
        if start == nil then
            local attachment = Instance.new("Attachment")
            attachment.Name = "DepartTutoriel"
            attachment.Position = Vector3.new(0, -1.5, 0)
            attachment.Parent = root
            start = attachment
        end
        beam.Attachment0 = start :: Attachment
        local goal = target + Vector3.new(0, 2, 0)
        if targetPart.Parent == nil then
            targetPart.Position = goal
            targetPart.Parent = Workspace
        else
            TweenService:Create(targetPart, TweenInfo.new(0.4, Enum.EasingStyle.Sine), { Position = goal }):Play()
        end
    end

    local function setIcon(key: string): ()
        for _, child in iconSlot:GetChildren() do
            child:Destroy()
        end
        Theme.icon(iconSlot, "Icone", key, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
    end

    local function show(step: number?): ()
        currentStep = step
        local def = if step then Tutorial.STEPS[step] else nil
        if step == nil or def == nil then
            gui.Enabled = false
            targetPart.Parent = nil
            return
        end
        title.Text = def.title
        text.Text = def.text
        setIcon(def.icon)
        action.Visible = def.manual
        action.Text = def.button or "Suivant"
        local final = step == Tutorial.FINAL_STEP
        pips.Visible = not final
        rewards.Visible = final
        skip.Visible = not final
        for i, dot in dots do
            dot.BackgroundColor3 = if i < step then Theme.MINT elseif i == step then Theme.YELLOW else Theme.NAVY_LIGHT
        end
        gui.Enabled = visibleNow()
        refreshTarget()
        -- petit rebond d'apparition
        local base = holderScale.Scale
        holderScale.Scale = base * 0.85
        TweenService:Create(holderScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = base }):Play()
        Sfx.play(if final then "fanfare" else "pickup")
    end

    action.Activated:Connect(function()
        if currentStep == Tutorial.FINAL_STEP then
            remote:FireServer("close")
            show(nil)
        else
            remote:FireServer("next")
        end
    end)
    skip.Activated:Connect(function()
        remote:FireServer("skip")
        show(nil)
    end)

    local function onStep(): ()
        local step = player:GetAttribute("TutorialStep")
        show(if typeof(step) == "number" then step else nil)
    end
    player:GetAttributeChangedSignal("TutorialStep"):Connect(onStep)
    player:GetAttributeChangedSignal("TutorialTarget"):Connect(refreshTarget)
    for _, name in { "MenusOuverts", "VueCoffre", "Piece" } do
        player:GetAttributeChangedSignal(name):Connect(function()
            gui.Enabled = visibleNow()
            refreshTarget()
        end)
    end
    player.CharacterAdded:Connect(function()
        task.wait(1)
        refreshTarget()
    end)
    onStep()

    -- Surbrillance et fleches animees
    RunService.RenderStepped:Connect(function()
        local def = if currentStep then Tutorial.STEPS[currentStep] else nil
        local t = os.clock()
        boardArrow.Position = UDim2.fromScale(0.5, 0.5 + math.sin(t * 4) * 0.08)
        local target = if def and def.target == "ui" and def.ui and gui.Enabled then findUi(def.ui) else nil
        if target == nil or not target.Visible then
            ring.Visible = false
            pointer.Visible = false
            return
        end
        local position, size = target.AbsolutePosition, target.AbsoluteSize
        -- AbsolutePosition part du dessous de la barre Roblox, l'ecran du tutoriel (IgnoreGuiInset) part du haut : sans
        -- ce decalage, cadre et fleche tombaient une barre trop haut (captures utilisateur du 15/09).
        if gui.IgnoreGuiInset then
            position += Vector2.new(0, GuiService:GetGuiInset().Y)
        end
        local pad = 8
        ring.Visible = true
        ring.Position = UDim2.fromOffset(position.X - pad, position.Y - pad)
        ring.Size = UDim2.fromOffset(size.X + pad * 2, size.Y + pad * 2)
        ringStroke.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(t * 5))
        local viewport = Workspace.CurrentCamera.ViewportSize
        local center = position + size / 2
        local bob = math.sin(t * 5) * 8
        pointer.Visible = true
        if center.Y < viewport.Y * 0.2 and center.X > viewport.X * 0.3 and center.X < viewport.X * 0.7 then
            -- en haut au centre (jauge) : fleche dessous, vers le haut
            pointer.Rotation = -90
            pointer.Position = UDim2.fromOffset(center.X, position.Y + size.Y + pad + 36 + bob)
        elseif center.X < viewport.X / 2 then
            -- a gauche : fleche a droite, vers la gauche
            pointer.Rotation = 180
            pointer.Position = UDim2.fromOffset(position.X + size.X + pad + 36 + bob, center.Y)
        else
            -- a droite : fleche a gauche, vers la droite
            pointer.Rotation = 0
            pointer.Position = UDim2.fromOffset(position.X - pad - 36 - bob, center.Y)
        end
    end)
end

return TutorialController
