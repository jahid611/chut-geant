--!strict

--[[
    EmoteController
    Roue d'emotes rapides (idee du carnet docs/IDEES.md) : communiquer sans chat.
    - Maintenir Z (ou le stick droit enfonce L3 a la manette ; DPadUp est deja pris par un pouvoir) ouvre une roue de
      6 emotes au centre de l'ecran ; on relache en visant une case (souris ou stick) pour l'envoyer.
    - Bouton rond « Émotes » en bas a droite, juste au-dessus des boutons ronds du HUD : un tap ouvre la roue, un
      tap sur une case l'envoie (tactile), un tap a cote la ferme.
    - Tous les joueurs voient une bulle au-dessus de la tete de l'emetteur (icone + mot, qui rebondit, 3 s) et un
      petit geste du bras (Transform ecrit a chaque PreSimulation, comme CarryController), sauf si le joueur porte un
      jouet, danse ou tient une arme.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

type Emote = { id: string, word: string, icon: string?, color: Color3 }

-- icon = cle d'Ui/Assets ; nil = pictogramme dessine (point d'exclamation)
local EMOTES: { Emote } = {
    { id = "Shush", word = "Chut !", icon = "bebeDort", color = Theme.PINK },
    { id = "Come", word = "Viens !", icon = "fleche", color = Theme.BLUE },
    { id = "Watch", word = "Attention !", icon = nil, color = Theme.YELLOW },
    { id = "Bravo", word = "Bravo !", icon = "etoile", color = Theme.MINT },
    { id = "Help", word = "Au secours !", icon = "pouvoirDoudou", color = Theme.RED },
    { id = "Thanks", word = "Merci !", icon = "menuAmis", color = Theme.PINK },
}

local WHEEL_ACTION = "RoueEmotes"
local WHEEL_SIZE = 520
local SLOT_SIZE = 150
local SLOT_RADIUS = 175
local DEAD_ZONE = 50
local BUBBLE_SECONDS = 3
local GESTURE_SECONDS = 1.4
-- bloc des boutons ronds du HUD (HudController : 410 x 158, colle en bas a droite a 10 px)
local HUD_BUTTONS_HEIGHT = 158

local EmoteController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local wheel: Frame
local appear: UIScale
local slotFrames: { GuiObject } = {}
local selected: number? = nil
local openedByTouch = false

-- gestes en cours : userId -> { id, started }
local gestures: { [number]: { id: string, started: number } } = {}

local function emoteById(id: string): Emote?
    for _, emote in EMOTES do
        if emote.id == id then
            return emote
        end
    end
    return nil
end

local function iconInto(parent: Instance, emote: Emote, size: UDim2, position: UDim2): ()
    if emote.icon then
        Theme.image(parent, "Icone", emote.icon, size, position, Vector2.new(0.5, 0.5))
        return
    end
    -- « Attention ! » : rond jaune avec un point d'exclamation
    local circle = Instance.new("Frame")
    circle.Name = "Icone"
    circle.BackgroundColor3 = emote.color
    circle.Size = size
    circle.Position = position
    circle.AnchorPoint = Vector2.new(0.5, 0.5)
    circle.Parent = parent
    local aspect = Instance.new("UIAspectRatioConstraint")
    aspect.Parent = circle
    Theme.corner(circle, 999)
    Theme.stroke(circle, 3, Theme.WHITE)
    Theme.text(
        circle,
        "Signe",
        "!",
        UDim2.fromScale(0.7, 0.8),
        UDim2.fromScale(0.5, 0.5),
        Theme.NAVY_DARK,
        Vector2.new(0.5, 0.5)
    )
end

local function send(index: number): ()
    local emote = EMOTES[index]
    if emote == nil then
        return
    end
    Sfx.play("click")
    local remote = Remotes.Get("Emote") :: RemoteEvent
    remote:FireServer(emote.id)
end

local function highlight(index: number?): ()
    selected = index
    for i, frame in slotFrames do
        local stroke = frame:FindFirstChildOfClass("UIStroke")
        local scale = frame:FindFirstChildOfClass("UIScale")
        local active = i == index
        if stroke then
            stroke.Color = if active then Theme.YELLOW else Theme.WHITE
            stroke.Thickness = if active then 6 else 3
        end
        if scale then
            TweenService:Create(scale, TweenInfo.new(0.12), { Scale = if active then 1.12 else 1 }):Play()
        end
    end
end

local function menusOpen(): boolean
    local open = player:GetAttribute("MenusOuverts")
    return (typeof(open) == "number" and open > 0) or player:GetAttribute("VueCoffre") == true
end

local function openWheel(byTouch: boolean): ()
    if wheel.Visible or menusOpen() then
        return
    end
    openedByTouch = byTouch
    highlight(nil)
    wheel.Visible = true
    appear.Scale = 0.7
    TweenService:Create(appear, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local function closeWheel(sendSelected: boolean): ()
    if not wheel.Visible then
        return
    end
    wheel.Visible = false
    local index = selected
    highlight(nil)
    if sendSelected and index then
        send(index)
    end
end

-- Case visee depuis le centre de l'ecran : souris (position) ou stick (direction).
local function slotFromDirection(direction: Vector2): number?
    if direction.Magnitude < 0.01 then
        return nil
    end
    -- case 1 en haut, puis dans le sens des aiguilles d'une montre (y ecran vers le bas)
    local angle = math.atan2(direction.X, -direction.Y)
    if angle < 0 then
        angle += math.pi * 2
    end
    local step = math.pi * 2 / #EMOTES
    return (math.floor((angle + step / 2) / step) % #EMOTES) + 1
end

local function updateSelection(): ()
    if not wheel.Visible or openedByTouch then
        return
    end
    local gamepad = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
    for _, input in gamepad do
        if input.KeyCode == Enum.KeyCode.Thumbstick2 or input.KeyCode == Enum.KeyCode.Thumbstick1 then
            local stick = Vector2.new(input.Position.X, -input.Position.Y)
            if stick.Magnitude > 0.5 then
                highlight(slotFromDirection(stick))
                return
            end
        end
    end
    if UserInputService.MouseEnabled then
        local mouse = UserInputService:GetMouseLocation()
        local center = Workspace.CurrentCamera.ViewportSize / 2
        local offset = mouse - center
        if offset.Magnitude > DEAD_ZONE then
            highlight(slotFromDirection(offset))
        else
            highlight(nil)
        end
    end
end

local function buildWheel(): ()
    wheel = Instance.new("Frame")
    wheel.Name = "Roue"
    wheel.BackgroundTransparency = 1
    wheel.Size = UDim2.fromOffset(WHEEL_SIZE, WHEEL_SIZE)
    wheel.Position = UDim2.fromScale(0.5, 0.5)
    wheel.AnchorPoint = Vector2.new(0.5, 0.5)
    wheel.Visible = false
    wheel.Parent = gui
    Theme.fitInside(wheel, Vector2.new(WHEEL_SIZE, WHEEL_SIZE), 0.8)
    -- deux UIScale ne se cumulent pas sur le meme objet : l'apparition vit sur un cadre interieur
    local inner = Instance.new("Frame")
    inner.Name = "Interieur"
    inner.BackgroundTransparency = 1
    inner.Size = UDim2.fromScale(1, 1)
    inner.Parent = wheel
    appear = Instance.new("UIScale")
    appear.Name = "Apparition"
    appear.Parent = inner

    local disc = Instance.new("Frame")
    disc.Name = "Fond"
    disc.BackgroundColor3 = Theme.NAVY_DARK
    disc.BackgroundTransparency = 0.25
    disc.Size = UDim2.fromScale(0.94, 0.94)
    disc.Position = UDim2.fromScale(0.5, 0.5)
    disc.AnchorPoint = Vector2.new(0.5, 0.5)
    disc.Parent = inner
    Theme.corner(disc, 999)
    Theme.stroke(disc, 3, Theme.WHITE)

    Theme.text(
        inner,
        "Aide",
        "Vise et relâche",
        UDim2.fromOffset(170, 40),
        UDim2.fromScale(0.5, 0.5),
        Theme.SOFT_TEXT,
        Vector2.new(0.5, 0.5)
    )

    for i, emote in EMOTES do
        local angle = (i - 1) * math.pi * 2 / #EMOTES
        local x = WHEEL_SIZE / 2 + math.sin(angle) * SLOT_RADIUS
        local y = WHEEL_SIZE / 2 - math.cos(angle) * SLOT_RADIUS
        local slot = Instance.new("TextButton")
        slot.Name = emote.id
        slot.Text = ""
        slot.AutoButtonColor = false
        slot.BackgroundColor3 = Theme.NAVY
        slot.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
        slot.Position = UDim2.fromOffset(x, y)
        slot.AnchorPoint = Vector2.new(0.5, 0.5)
        slot.Parent = inner
        Theme.corner(slot, 999)
        Theme.stroke(slot, 3, Theme.WHITE)
        local scale = Instance.new("UIScale")
        scale.Parent = slot
        iconInto(slot, emote, UDim2.fromScale(0.52, 0.52), UDim2.fromScale(0.5, 0.4))
        local word = Theme.text(
            slot,
            "Mot",
            emote.word,
            UDim2.fromScale(0.86, 0.22),
            UDim2.fromScale(0.5, 0.8),
            emote.color,
            Vector2.new(0.5, 0.5)
        )
        local limit = Instance.new("UITextSizeConstraint")
        limit.MaxTextSize = 26
        limit.Parent = word
        -- tactile : un tap sur la case l'envoie
        slot.Activated:Connect(function()
            if openedByTouch or not UserInputService.KeyboardEnabled then
                selected = i
                closeWheel(true)
            end
        end)
        table.insert(slotFrames, slot)
    end
end

-- Bouton rond « Émotes » au-dessus des boutons ronds du HUD en bas a droite.
local function buildButton(): ()
    local holder = Instance.new("Frame")
    holder.Name = "BoutonEmotes"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(112, 128)
    holder.AnchorPoint = Vector2.new(1, 1)
    holder.Parent = gui
    local scale = Theme.fit(holder, Theme.HUD_FACTOR)
    local function place(): ()
        -- colle au bord droit comme le bloc du HUD, 14 px au-dessus de son haut (158 x echelle)
        holder.Position = UDim2.new(1, -30, 1, -(10 + (HUD_BUTTONS_HEIGHT + 14) * scale.Scale))
    end
    scale:GetPropertyChangedSignal("Scale"):Connect(place)
    place()

    local button = Instance.new("TextButton")
    button.Name = "Rond"
    button.Text = ""
    button.AutoButtonColor = false
    button.BackgroundColor3 = Theme.NAVY
    button.Size = UDim2.fromOffset(92, 92)
    button.Position = UDim2.fromScale(0.5, 0)
    button.AnchorPoint = Vector2.new(0.5, 0)
    button.Parent = holder
    Theme.corner(button, 999)
    Theme.stroke(button, 3, Theme.WHITE)
    Theme.image(
        button,
        "Icone",
        "bebeDort",
        UDim2.fromScale(0.62, 0.62),
        UDim2.fromScale(0.5, 0.5),
        Vector2.new(0.5, 0.5)
    )
    if UserInputService.KeyboardEnabled then
        local badge = Instance.new("Frame")
        badge.Name = "Touche"
        badge.BackgroundColor3 = Theme.NAVY_DARK
        badge.Size = UDim2.fromOffset(30, 30)
        badge.Position = UDim2.fromOffset(-2, -2)
        badge.Parent = button
        Theme.corner(badge, 15)
        Theme.stroke(badge, 2, Theme.WHITE)
        Theme.text(
            badge,
            "Texte",
            "Z",
            UDim2.fromScale(0.7, 0.7),
            UDim2.fromScale(0.5, 0.5),
            Theme.WHITE,
            Vector2.new(0.5, 0.5)
        )
    end
    local label = Theme.text(
        holder,
        "Nom",
        "Émotes",
        UDim2.new(1, 10, 0, 26),
        UDim2.fromScale(0.5, 1),
        Theme.WHITE,
        Vector2.new(0.5, 1)
    )
    local limit = Instance.new("UITextSizeConstraint")
    limit.MaxTextSize = 22
    limit.Parent = label

    button.Activated:Connect(function()
        if wheel.Visible then
            closeWheel(false)
        else
            openWheel(true)
        end
    end)

    local function refresh(): ()
        holder.Visible = not menusOpen()
        if menusOpen() then
            closeWheel(false)
        end
    end
    player:GetAttributeChangedSignal("MenusOuverts"):Connect(refresh)
    player:GetAttributeChangedSignal("VueCoffre"):Connect(refresh)
    refresh()
end

-- Bulle au-dessus de la tete d'un joueur (icone + mot) : pop, flotte, s'efface.
local function showBubble(target: Player, emote: Emote): ()
    local character = target.Character
    local head = if character then character:FindFirstChild("Head") else nil
    if head == nil or not head:IsA("BasePart") then
        return
    end
    local old = head:FindFirstChild("BulleEmote")
    if old then
        old:Destroy()
    end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BulleEmote"
    billboard.Adornee = head
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = 150
    -- au-dessus du niveau (« Niv. N » a 3,9 studs) et du titre de nuit
    billboard.Size = UDim2.fromScale(4.4, 1.6)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
    billboard.Parent = head

    local bubble = Instance.new("Frame")
    bubble.Name = "Bulle"
    bubble.BackgroundColor3 = Theme.NAVY
    bubble.Size = UDim2.fromScale(1, 1)
    bubble.Position = UDim2.fromScale(0.5, 0.5)
    bubble.AnchorPoint = Vector2.new(0.5, 0.5)
    bubble.Parent = billboard
    Theme.corner(bubble, 999)
    local stroke = Theme.stroke(bubble, 3, emote.color)
    local pop = Instance.new("UIScale")
    pop.Scale = 0.2
    pop.Parent = bubble
    iconInto(bubble, emote, UDim2.fromScale(0.3, 0.8), UDim2.fromScale(0.2, 0.5))
    local word = Theme.text(
        bubble,
        "Mot",
        emote.word,
        UDim2.fromScale(0.62, 0.62),
        UDim2.fromScale(0.64, 0.5),
        emote.color,
        Vector2.new(0.5, 0.5)
    )

    TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
    TweenService:Create(billboard, TweenInfo.new(BUBBLE_SECONDS, Enum.EasingStyle.Sine), {
        StudsOffsetWorldSpace = Vector3.new(0, 7, 0),
    }):Play()
    task.delay(BUBBLE_SECONDS - 0.4, function()
        if billboard.Parent == nil then
            return
        end
        local fade = TweenInfo.new(0.4)
        TweenService:Create(bubble, fade, { BackgroundTransparency = 1 }):Play()
        TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
        TweenService:Create(word, fade, { TextTransparency = 1 }):Play()
        for _, descendant in bubble:GetDescendants() do
            if descendant:IsA("ImageLabel") then
                TweenService:Create(descendant, fade, { ImageTransparency = 1 }):Play()
            elseif descendant:IsA("UIStroke") then
                TweenService:Create(descendant, fade, { Transparency = 1 }):Play()
            end
        end
        task.delay(0.45, function()
            billboard:Destroy()
        end)
    end)
end

local function joint(character: Model, limb: string, name: string): Instance?
    local part = character:FindFirstChild(limb)
    local found = if part then part:FindFirstChild(name) else nil
    if found and (found:IsA("AnimationConstraint") or found:IsA("Motor6D")) then
        return found
    end
    return nil
end

local function setTransform(target: Instance?, value: CFrame): ()
    if target == nil then
        return
    end
    -- AnimationConstraint (epaules de ce place) ou Motor6D (anciens rigs) : meme propriete Transform
    if target:IsA("AnimationConstraint") or target:IsA("Motor6D") then
        (target :: any).Transform = value
    end
end

-- Pas de geste si le joueur porte un jouet, danse ou tient une arme (ces poses gagnent).
local function busy(target: Player, character: Model): boolean
    return target:GetAttribute("CarriedToyId") ~= nil
        or target:GetAttribute("Dancing") ~= nil
        or character:FindFirstChildOfClass("Tool") ~= nil
end

local function poseGestures(): ()
    local now = os.clock()
    for userId, gesture in gestures do
        local elapsed = now - gesture.started
        local target = Players:GetPlayerByUserId(userId)
        local character = if target then target.Character else nil
        if target == nil or character == nil or elapsed > GESTURE_SECONDS then
            gestures[userId] = nil
            continue
        end
        if busy(target, character) then
            continue
        end
        -- entree et sortie douces
        local weight = math.clamp(math.min(elapsed / 0.18, (GESTURE_SECONDS - elapsed) / 0.25), 0, 1)
        local wave = math.sin(elapsed * 12)
        local rightShoulder = joint(character, "RightUpperArm", "RightShoulder")
        local rightElbow = joint(character, "RightLowerArm", "RightElbow")
        local leftShoulder = joint(character, "LeftUpperArm", "LeftShoulder")
        local waist = joint(character, "UpperTorso", "Waist")
        local id = gesture.id
        if id == "Shush" then
            -- main vers la bouche
            setTransform(rightShoulder, CFrame.Angles(2.2 * weight, 0, -0.45 * weight))
            setTransform(rightElbow, CFrame.Angles(1.4 * weight, 0, 0))
        elseif id == "Come" then
            -- bras tendu qui fait signe de venir
            setTransform(rightShoulder, CFrame.Angles(1.5 * weight, 0, 0))
            setTransform(rightElbow, CFrame.Angles((0.7 + 0.6 * wave) * weight, 0, 0))
        elseif id == "Watch" then
            -- bras tendu qui pointe
            setTransform(rightShoulder, CFrame.Angles(1.6 * weight, 0, 0))
        elseif id == "Bravo" then
            -- bras leve qui s'agite
            setTransform(rightShoulder, CFrame.Angles(math.pi * weight, 0, 0.25 * wave * weight))
        elseif id == "Help" then
            -- deux bras leves qui s'agitent
            setTransform(rightShoulder, CFrame.Angles(math.pi * weight, 0, 0.4 * wave * weight))
            setTransform(leftShoulder, CFrame.Angles(math.pi * weight, 0, -0.4 * wave * weight))
        elseif id == "Thanks" then
            -- petite reverence
            setTransform(waist, CFrame.Angles(-0.4 * weight, 0, 0))
        end
    end
end

local function onEmote(userId: any, emoteId: any): ()
    if typeof(userId) ~= "number" or typeof(emoteId) ~= "string" then
        return
    end
    local emote = emoteById(emoteId)
    local target = Players:GetPlayerByUserId(userId)
    if emote == nil or target == nil then
        return
    end
    showBubble(target, emote)
    gestures[userId] = { id = emoteId, started = os.clock() }
end

function EmoteController:Init(): () end

function EmoteController:Start(): ()
    gui = Instance.new("ScreenGui")
    gui.Name = "Emotes"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 7
    gui.Parent = player:WaitForChild("PlayerGui")
    buildWheel()
    buildButton()

    -- Maintenir Z / L3 : la roue s'ouvre ; relacher envoie l'emote visee.
    ContextActionService:BindAction(
        WHEEL_ACTION,
        function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
            if state == Enum.UserInputState.Begin then
                openWheel(false)
            elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
                if not openedByTouch then
                    closeWheel(state == Enum.UserInputState.End)
                end
            end
            return Enum.ContextActionResult.Sink
        end,
        false,
        Enum.KeyCode.Z,
        Enum.KeyCode.ButtonL3
    )

    RunService.RenderStepped:Connect(updateSelection)
    RunService.PreSimulation:Connect(poseGestures)

    local remote = Remotes.Get("Emote") :: RemoteEvent
    remote.OnClientEvent:Connect(onEmote)
end

return EmoteController
