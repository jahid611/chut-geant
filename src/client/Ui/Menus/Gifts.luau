--!strict

--[[
    Menu « Cadeaux » (colonne de gauche, MenuController) :
    - a gauche, la recompense de connexion : 7 cartes jour (icone tetine, jour 7 = gros cadeau), bouton Recuperer ;
    - a droite, la roue quotidienne : 8 cases avec icones (tetine, etoile = XP, eclair = recharge des pouvoirs) ;
      le serveur choisit la case, la roue tourne 5 tours puis s'arrete dessus sous le repere.
    Etat : attributs joueur Daily_Streak, Daily_LoginClaimable, Daily_WheelReady, Daily_ResetAt (DailyService).

    Mise en page : tout est en proportion d'une zone qui coupe au bord du panneau (jamais de debordement).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Retention = require(Shared:WaitForChild("Retention"))

local Modal = require(script.Parent.Parent:WaitForChild("Modal"))
local Sfx = require(script.Parent.Parent:WaitForChild("Sfx"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

-- rayon des cases, en fraction du disque
local SLOT_RADIUS = 0.33
local SPIN_SECONDS = 3.6

local SLOT_ICON: { [string]: string } = {
    cash = "tetine",
    xp = "etoile",
    recharge = "pouvoirFurie",
}

local Menu = {}

local function invoke(kind: string): (boolean, string, any)
    local ok, success, message, reward = pcall(function()
        return (Remotes.Get("DailyReward") :: RemoteFunction):InvokeServer(kind)
    end)
    if not ok then
        return false, "Le serveur ne répond pas, réessaie.", nil
    end
    return success == true, if typeof(message) == "string" then message else "C'est fait !", reward
end

-- Carte d'un jour de connexion, en proportion de sa zone.
local function dayCard(
    parent: Instance,
    day: number,
    position: UDim2,
    size: UDim2,
    past: boolean,
    today: boolean,
    isBig: boolean
): ()
    local frame = Instance.new("Frame")
    frame.Name = "Jour" .. day
    frame.BackgroundColor3 = if past then Theme.NAVY_DARK else Theme.NAVY_LIGHT
    frame.BorderSizePixel = 0
    frame.Position = position
    frame.Size = size
    frame.ClipsDescendants = true
    frame.Parent = parent
    Theme.corner(frame, 16)
    Theme.stroke(
        frame,
        if today then 4 else 2,
        if today then Theme.YELLOW elseif past then Theme.MINT else Color3.fromRGB(120, 140, 210)
    )
    Theme.label(
        frame,
        "Jour",
        "J" .. day,
        UDim2.new(1, -10, 0.22, 0),
        UDim2.fromScale(0.5, 0.04),
        if isBig then Theme.YELLOW else Theme.WHITE,
        Vector2.new(0.5, 0),
        24
    )
    Theme.icon(
        frame,
        "Icone",
        if isBig then "menuCadeaux" else "tetine",
        UDim2.fromScale(0.8, 0.44),
        UDim2.fromScale(0.5, 0.52),
        Vector2.new(0.5, 0.5),
        Theme.PINK
    )
    Theme.label(
        frame,
        "Montant",
        if past then "Reçu" else Theme.formatNumber(Retention.LOGIN_CASH[day]),
        UDim2.new(1, -10, 0.2, 0),
        UDim2.fromScale(0.5, 0.97),
        if past then Theme.MINT else Theme.YELLOW,
        Vector2.new(0.5, 1),
        22
    )
end

function Menu.open(gui: Instance): ()
    if Modal.isOpen(gui) then
        return
    end
    local player = Players.LocalPlayer
    local modal = Modal.open(gui, "CADEAUX", Theme.WHITE, UDim2.fromOffset(1000, 620))
    Theme.icon(
        modal.panel,
        "IconeTitre",
        "menuCadeaux",
        UDim2.fromOffset(62, 62),
        UDim2.new(0.2, -6, 0, 16),
        Vector2.new(1, 0),
        Theme.PINK
    )
    local body = Modal.body(modal, 92, 20)

    -- Connexion (gauche)
    local login = Instance.new("Frame")
    login.Name = "Connexion"
    login.BackgroundTransparency = 1
    login.Size = UDim2.new(0.55, -10, 1, 0)
    login.ClipsDescendants = true
    login.Parent = body

    local function renderLogin(): ()
        for _, child in login:GetChildren() do
            child:Destroy()
        end
        local streak = player:GetAttribute("Daily_Streak")
        local current = if typeof(streak) == "number" then math.clamp(streak, 1, #Retention.LOGIN_CASH) else 1
        local claimable = player:GetAttribute("Daily_LoginClaimable") == true

        local top = Instance.new("Frame")
        top.Name = "Entete"
        top.BackgroundTransparency = 1
        top.Size = UDim2.fromScale(1, 0.12)
        top.Parent = login
        Theme.icon(
            top,
            "Icone",
            "menuCadeaux",
            UDim2.fromScale(0.12, 0.9),
            UDim2.fromScale(0, 0.5),
            Vector2.new(0, 0.5)
        )
        Theme.label(
            top,
            "Titre",
            "Connexion",
            UDim2.fromScale(0.45, 0.8),
            UDim2.fromScale(0.13, 0.5),
            Theme.PINK,
            Vector2.new(0, 0.5),
            30,
            Enum.TextXAlignment.Left
        )
        Theme.pill(
            top,
            "Serie",
            "etoile",
            string.format("Série : %d", current),
            UDim2.fromScale(0.38, 0.72),
            UDim2.fromScale(1, 0.5),
            Vector2.new(1, 0.5),
            Theme.SOFT_TEXT,
            22
        )

        local days = Instance.new("Frame")
        days.Name = "Jours"
        days.BackgroundTransparency = 1
        days.Position = UDim2.fromScale(0, 0.15)
        days.Size = UDim2.fromScale(1, 0.66)
        days.Parent = login
        for day = 1, #Retention.LOGIN_CASH do
            local isBig = day == #Retention.LOGIN_CASH
            local past = day < current or (day == current and not claimable)
            local today = day == current and claimable
            local position: UDim2
            local size: UDim2
            if day <= 4 then
                position = UDim2.fromScale((day - 1) * 0.25 + 0.01, 0)
                size = UDim2.fromScale(0.23, 0.48)
            elseif not isBig then
                position = UDim2.fromScale((day - 5) * 0.25 + 0.01, 0.52)
                size = UDim2.fromScale(0.23, 0.48)
            else
                position = UDim2.fromScale(0.51, 0.52)
                size = UDim2.fromScale(0.48, 0.48)
            end
            dayCard(days, day, position, size, past, today, isBig)
        end

        local button = Theme.button(
            login,
            "Recuperer",
            if claimable then "Récupérer" else "Demain",
            if claimable then Theme.GREEN else Theme.GREY,
            UDim2.fromScale(0.7, 0.14),
            UDim2.fromScale(0.5, 0.99),
            Vector2.new(0.5, 1)
        )
        Theme.limitText(button, 30)
        if claimable then
            button.Activated:Connect(function()
                button.Text = "..."
                local success, message = invoke("login")
                Theme.toast(gui, message, if success then Theme.GREEN else Theme.RED)
                renderLogin()
            end)
        end
    end

    -- Roue (droite)
    local wheelArea = Instance.new("Frame")
    wheelArea.Name = "Roue"
    wheelArea.BackgroundTransparency = 1
    wheelArea.Size = UDim2.new(0.45, -10, 1, 0)
    wheelArea.Position = UDim2.new(0.55, 10, 0, 0)
    wheelArea.ClipsDescendants = true
    wheelArea.Parent = body

    local wheelTop = Instance.new("Frame")
    wheelTop.Name = "Entete"
    wheelTop.BackgroundTransparency = 1
    wheelTop.Size = UDim2.fromScale(1, 0.12)
    wheelTop.Parent = wheelArea
    Theme.icon(
        wheelTop,
        "Icone",
        "menuRoue",
        UDim2.fromScale(0.16, 0.9),
        UDim2.fromScale(0.12, 0.5),
        Vector2.new(0, 0.5),
        Theme.PINK
    )
    Theme.label(
        wheelTop,
        "Titre",
        "Roue du jour",
        UDim2.fromScale(0.6, 0.8),
        UDim2.fromScale(0.3, 0.5),
        Theme.PINK,
        Vector2.new(0, 0.5),
        30,
        Enum.TextXAlignment.Left
    )

    local disc = Instance.new("Frame")
    disc.Name = "Disque"
    disc.BackgroundColor3 = Theme.NAVY_LIGHT
    disc.BorderSizePixel = 0
    disc.Size = UDim2.fromScale(0.92, 0.68)
    disc.Position = UDim2.fromScale(0.5, 0.15)
    disc.AnchorPoint = Vector2.new(0.5, 0)
    disc.Parent = wheelArea
    local discAspect = Instance.new("UIAspectRatioConstraint")
    discAspect.AspectRatio = 1
    discAspect.Parent = disc
    local discCorner = Instance.new("UICorner")
    discCorner.CornerRadius = UDim.new(0.5, 0)
    discCorner.Parent = disc
    Theme.stroke(disc, 4, Theme.WHITE)

    local rotor = Instance.new("Frame")
    rotor.Name = "Rotor"
    rotor.BackgroundTransparency = 1
    rotor.Size = UDim2.fromScale(1, 1)
    rotor.Parent = disc
    local count = #Retention.WHEEL
    local bubbles: { Frame } = {}
    -- La rotation d'un Frame ne deplace pas ses enfants : chaque case est replacee sur le cercle a chaque angle.
    local wheelAngle = Instance.new("NumberValue")
    wheelAngle.Name = "AngleRoue"
    wheelAngle.Parent = rotor
    local function layoutWheel(): ()
        for i, bubble in bubbles do
            local degrees = (i - 1) * 360 / count + wheelAngle.Value
            local angle = math.rad(degrees)
            bubble.Position = UDim2.fromScale(0.5 + math.sin(angle) * SLOT_RADIUS, 0.5 - math.cos(angle) * SLOT_RADIUS)
            bubble.Rotation = degrees
        end
    end
    wheelAngle.Changed:Connect(layoutWheel)
    for i, slot in Retention.WHEEL do
        local bubble = Instance.new("Frame")
        bubble.Name = "Case" .. i
        bubble.BackgroundColor3 = slot.color
        bubble.BorderSizePixel = 0
        bubble.Size = UDim2.fromScale(0.3, 0.16)
        bubble.AnchorPoint = Vector2.new(0.5, 0.5)
        bubble.Parent = rotor
        table.insert(bubbles, bubble)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0.4, 0)
        corner.Parent = bubble
        Theme.stroke(bubble, 2, Theme.WHITE)
        local iconKey = SLOT_ICON[slot.kind] or "tetine"
        if slot.kind == "recharge" then
            Theme.icon(
                bubble,
                "Icone",
                iconKey,
                UDim2.fromScale(0.9, 0.86),
                UDim2.fromScale(0.5, 0.5),
                Vector2.new(0.5, 0.5),
                Theme.YELLOW
            )
        else
            Theme.icon(
                bubble,
                "Icone",
                iconKey,
                UDim2.fromScale(0.36, 0.86),
                UDim2.fromScale(0.04, 0.5),
                Vector2.new(0, 0.5),
                Theme.YELLOW
            )
            Theme.label(
                bubble,
                "Texte",
                Theme.formatNumber(slot.amount),
                UDim2.fromScale(0.58, 0.78),
                UDim2.fromScale(0.97, 0.5),
                Theme.WHITE,
                Vector2.new(1, 0.5),
                20
            )
        end
    end
    layoutWheel()
    local hub = Instance.new("Frame")
    hub.Name = "Centre"
    hub.BackgroundColor3 = Theme.PINK
    hub.BorderSizePixel = 0
    hub.Size = UDim2.fromScale(0.2, 0.2)
    hub.Position = UDim2.fromScale(0.5, 0.5)
    hub.AnchorPoint = Vector2.new(0.5, 0.5)
    hub.Parent = disc
    local hubCorner = Instance.new("UICorner")
    hubCorner.CornerRadius = UDim.new(0.5, 0)
    hubCorner.Parent = hub
    Theme.stroke(hub, 3, Theme.WHITE)
    Theme.icon(hub, "Icone", "etoile", UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

    -- repere en haut de la roue
    local pointer = Instance.new("Frame")
    pointer.Name = "Repere"
    pointer.BackgroundColor3 = Theme.YELLOW
    pointer.BorderSizePixel = 0
    pointer.Size = UDim2.fromScale(0.08, 0.08)
    pointer.Rotation = 45
    pointer.Position = UDim2.fromScale(0.5, 0)
    pointer.AnchorPoint = Vector2.new(0.5, 0.5)
    pointer.ZIndex = 3
    pointer.Parent = disc
    Theme.stroke(pointer, 3, Theme.WHITE)

    local spinning = false
    local spinButton = Theme.button(
        wheelArea,
        "Tourner",
        "Tourner",
        Theme.GREEN,
        UDim2.fromScale(0.8, 0.14),
        UDim2.fromScale(0.5, 0.99),
        Vector2.new(0.5, 1)
    )
    Theme.limitText(spinButton, 28)

    local function refreshWheelButton(): ()
        if spinning then
            return
        end
        local ready = player:GetAttribute("Daily_WheelReady") == true
        spinButton.BackgroundColor3 = if ready then Theme.GREEN else Theme.GREY
        if ready then
            spinButton.Text = "Tourner"
        else
            local resetAt = player:GetAttribute("Daily_ResetAt")
            local left = if typeof(resetAt) == "number" then resetAt - Workspace:GetServerTimeNow() else 0
            spinButton.Text = Retention.FormatDuration(left)
        end
    end

    spinButton.Activated:Connect(function()
        if spinning or player:GetAttribute("Daily_WheelReady") ~= true then
            return
        end
        spinning = true
        spinButton.Text = "..."
        local success, message, reward = invoke("wheel")
        local index = if success and typeof(reward) == "table" then tonumber(reward.index) else nil
        if index == nil then
            spinning = false
            Theme.toast(gui, message, Theme.RED)
            refreshWheelButton()
            return
        end
        -- case gagnante sous le repere (en haut) apres 5 tours
        local current = wheelAngle.Value
        local base = current - current % 360
        local target = base + 360 * 5 + ((-(index - 1) * 360 / count) % 360)
        local tween = TweenService:Create(
            wheelAngle,
            TweenInfo.new(SPIN_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { Value = target }
        )
        -- cliquetis a chaque case qui passe sous le repere (il ralentit avec la roue), fanfare a l'arret
        local lastSector = math.floor(current / (360 / count))
        local ticking = wheelAngle.Changed:Connect(function(value: number)
            local sector = math.floor(value / (360 / count))
            if sector ~= lastSector then
                lastSector = sector
                Sfx.play("tick")
            end
        end)
        tween.Completed:Connect(function()
            ticking:Disconnect()
            spinning = false
            if modal.root.Parent then
                Sfx.play("fanfare")
                Theme.toast(gui, message, Theme.GREEN)
                refreshWheelButton()
            end
        end)
        tween:Play()
    end)

    renderLogin()
    refreshWheelButton()
    local connections = {
        player:GetAttributeChangedSignal("Daily_LoginClaimable"):Connect(renderLogin),
        player:GetAttributeChangedSignal("Daily_Streak"):Connect(renderLogin),
        player:GetAttributeChangedSignal("Daily_WheelReady"):Connect(refreshWheelButton),
    }
    modal.root.Destroying:Connect(function()
        for _, connection in connections do
            connection:Disconnect()
        end
    end)
end

return Menu
