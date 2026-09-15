--!strict

--[[
    ChallengeController
    Defi chronometre de la plaque DÉFI (ChallengeService, attributs Challenge*) :
    - chrono compact cale a GAUCHE de la jauge CHUT (le badge combo est a droite, les bandeaux d'evenements a
      y = 118) : pastille avec le temps restant (rouge et battement sous 10 s), titre du defi et une icone par jouet
      a ramener, allumee quand il est depose. Si la pastille des tetines est trop proche (petit ecran), le chrono
      se reduit pour ne jamais la chevaucher ;
    - depart : coup de sifflet et annonce du defi ; reussite : fenetre « DÉFI RÉUSSI ! » avec badge et recompenses
      en icones ; echec : message rouge ;
    - cache pendant les menus (MenusOuverts) et la vue coffre (VueCoffre).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

local BASE = Vector2.new(262, 84)
local MAX_ICONS = 5
local ICON = 30
local URGENT_SECONDS = 10

local ChallengeController = {}

local player = Players.LocalPlayer

local function numberAttr(name: string): number?
    local value = player:GetAttribute(name)
    return if typeof(value) == "number" then value else nil
end

local function formatTime(seconds: number): string
    local s = math.max(math.ceil(seconds), 0)
    return string.format("%d:%02d", s // 60, s % 60)
end

function ChallengeController:Init(): () end

function ChallengeController:Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "Defi"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 6
    gui.Parent = player:WaitForChild("PlayerGui")

    local holder = Instance.new("Frame")
    holder.Name = "Chrono"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(BASE.X, BASE.Y)
    holder.AnchorPoint = Vector2.new(1, 0)
    holder.Position = UDim2.new(0.5, -310, 0, 8)
    holder.Visible = false
    holder.Parent = gui
    -- Echelle propre (pas Theme.fit, qui la remettrait a jour seule) : place() la recalcule avec la reduction.
    local scale = Instance.new("UIScale")
    scale.Scale = Theme.viewportFactor() * Theme.HUD_FACTOR
    scale.Parent = holder

    -- Cale le chrono en haut a gauche de la jauge « Bruit » sans toucher la pastille « Tetines » du HUD.
    local function place(): ()
        local hud = player.PlayerGui:FindFirstChild("HUD")
        local noise = if hud then hud:FindFirstChild("Bruit") else nil
        if not (noise and noise:IsA("GuiObject") and noise.AbsoluteSize.X > 0) then
            return
        end
        local fitScale = Theme.viewportFactor() * Theme.HUD_FACTOR
        local right = noise.AbsolutePosition.X - 8
        -- le cadre « Bruit » deborde au-dessus de l'ecran (titre CHUT !) : sans borne, le chrono sortait par le haut
        local top = math.max(noise.AbsolutePosition.Y + 4, 8)
        local width = BASE.X * fitScale
        local height = BASE.Y * fitScale
        local money = hud and hud:FindFirstChild("Tetines")
        local factor = 1
        if money and money:IsA("GuiObject") and money.Visible then
            local moneyRight = money.AbsolutePosition.X + money.AbsoluteSize.X + 8
            local overlapsY = top + height > money.AbsolutePosition.Y
            if overlapsY and right - width < moneyRight then
                factor = math.clamp((right - moneyRight) / width, 0.45, 1)
            end
        end
        holder.Position = UDim2.fromOffset(right, top)
        scale.Scale = fitScale * factor
    end

    local card = Theme.panel(holder, "Carte", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero)
    Theme.corner(card, 20)
    local cardStroke = card:FindFirstChildOfClass("UIStroke")
    if cardStroke then
        cardStroke.Color = Theme.YELLOW
    end

    local disc = Instance.new("Frame")
    disc.Name = "Pastille"
    disc.BackgroundColor3 = Theme.NAVY_DARK
    disc.Size = UDim2.fromOffset(70, 70)
    disc.Position = UDim2.fromOffset(44, BASE.Y / 2)
    disc.AnchorPoint = Vector2.new(0.5, 0.5)
    disc.Parent = card
    Theme.corner(disc, 35)
    local ring = Theme.stroke(disc, 4, Theme.YELLOW)
    local timeLabel = Theme.text(
        disc,
        "Temps",
        "1:30",
        UDim2.fromOffset(58, 34),
        UDim2.fromScale(0.5, 0.5),
        Theme.WHITE,
        Vector2.new(0.5, 0.5)
    )

    local title = Theme.label(
        card,
        "Titre",
        "DÉFI",
        UDim2.fromOffset(170, 26),
        UDim2.fromOffset(84, 8),
        Theme.YELLOW,
        Vector2.zero,
        22,
        Enum.TextXAlignment.Left
    )
    local iconRow = Instance.new("Frame")
    iconRow.Name = "Progression"
    iconRow.BackgroundTransparency = 1
    iconRow.Size = UDim2.fromOffset(170, ICON + 4)
    iconRow.Position = UDim2.fromOffset(84, 40)
    iconRow.Parent = card
    local icons: { GuiObject } = {}

    local function buildIcons(goal: number, key: string): ()
        for _, icon in icons do
            icon:Destroy()
        end
        table.clear(icons)
        local count = math.clamp(goal, 1, MAX_ICONS)
        for i = 1, count do
            local icon = Theme.icon(
                iconRow,
                "Jouet" .. i,
                key,
                UDim2.fromOffset(ICON, ICON),
                UDim2.fromOffset((i - 1) * (ICON + 4), 2),
                Vector2.zero,
                Theme.GREY
            )
            table.insert(icons, icon)
        end
    end

    local function paintProgress(progress: number, animate: boolean): ()
        for i, icon in icons do
            local lit = i <= progress
            if icon:IsA("ImageLabel") then
                icon.ImageTransparency = if lit then 0 else 0.65
                icon.ImageColor3 = if lit then Theme.WHITE else Theme.GREY
            else
                icon.BackgroundColor3 = if lit then Theme.MINT else Theme.GREY
            end
            if lit and animate and i == progress then
                icon.Size = UDim2.fromOffset(ICON * 1.6, ICON * 1.6)
                TweenService:Create(icon, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
                    Size = UDim2.fromOffset(ICON, ICON),
                }):Play()
            end
        end
    end

    local active = false
    local function refreshVisible(): ()
        local menus = player:GetAttribute("MenusOuverts")
        local hidden = (typeof(menus) == "number" and menus > 0) or player:GetAttribute("VueCoffre") == true
        holder.Visible = active and not hidden
    end

    local lastProgress = 0
    local function onChallenge(): ()
        local endsAt = numberAttr("ChallengeEndsAt")
        local wasActive = active
        active = endsAt ~= nil
        if active and not wasActive then
            local goal = numberAttr("ChallengeGoal") or 1
            local titleText = player:GetAttribute("ChallengeTitle")
            title.Text = if typeof(titleText) == "string" then titleText else "DÉFI"
            local rare = titleText == "Chasseur de raretés"
            buildIcons(goal, if rare then "etoile" else "boutonMesJouets")
            lastProgress = 0
            paintProgress(0, false)
            place()
            Sfx.play("challengeStart")
            local text = player:GetAttribute("ChallengeText")
            if typeof(text) == "string" then
                Theme.toast(gui, text, Theme.YELLOW)
            end
            -- entree : le chrono tombe en rebondissant
            card.Position = UDim2.fromOffset(0, -40)
            TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0, 0) })
                :Play()
        end
        refreshVisible()
    end

    local function onProgress(): ()
        local progress = numberAttr("ChallengeProgress") or 0
        if active and progress > lastProgress then
            paintProgress(progress, true)
            Sfx.play("comboUp", { speed = 1 + progress * 0.08 })
        end
        lastProgress = progress
    end

    -- Fenetre de reussite : titre, badge et recompenses en icones, disparait seule.
    local function celebrate(result: any): ()
        local popup = Instance.new("Frame")
        popup.Name = "DefiReussi"
        popup.BackgroundTransparency = 1
        popup.Size = UDim2.fromOffset(520, 290)
        popup.Position = UDim2.fromScale(0.5, 0.4)
        popup.AnchorPoint = Vector2.new(0.5, 0.5)
        popup.Parent = gui
        local popupScale = Theme.fit(popup, 0.85)
        local target = popupScale.Scale
        popupScale.Scale = target * 0.4
        TweenService:Create(popupScale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = target }):Play()

        local panel = Theme.panel(popup, "Panneau", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero)
        local stroke = panel:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = Theme.YELLOW
            stroke.Thickness = 4
        end
        Theme.text(
            panel,
            "Titre",
            "DÉFI RÉUSSI !",
            UDim2.new(1, -40, 0, 58),
            UDim2.new(0.5, 0, 0, 14),
            Theme.YELLOW,
            Vector2.new(0.5, 0)
        )
        local badgeName = if typeof(result) == "table" and typeof(result.badge) == "string"
            then result.badge
            else "Voleur éclair"
        local wins = if typeof(result) == "table" and typeof(result.wins) == "number" then result.wins else 1
        local badge = Instance.new("Frame")
        badge.Name = "Badge"
        badge.BackgroundColor3 = Theme.NAVY_DARK
        badge.Size = UDim2.fromOffset(360, 66)
        badge.Position = UDim2.new(0.5, 0, 0, 86)
        badge.AnchorPoint = Vector2.new(0.5, 0)
        badge.Parent = panel
        Theme.corner(badge, 33)
        Theme.stroke(badge, 3, Theme.YELLOW)
        local star = Theme.image(
            badge,
            "Etoile",
            "etoile",
            UDim2.fromOffset(54, 54),
            UDim2.new(0, 10, 0.5, 0),
            Vector2.new(0, 0.5)
        )
        star.Rotation = -12
        TweenService:Create(star, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
            Rotation = 12,
        }):Play()
        Theme.label(
            badge,
            "Nom",
            string.format("Badge %s x%d", badgeName, wins),
            UDim2.new(1, -86, 0, 36),
            UDim2.new(0, 72, 0.5, 0),
            Theme.WHITE,
            Vector2.new(0, 0.5),
            26,
            Enum.TextXAlignment.Left
        )
        local cash = if typeof(result) == "table" and typeof(result.cash) == "number" then result.cash else 0
        local xp = if typeof(result) == "table" and typeof(result.xp) == "number" then result.xp else 0
        Theme.pill(
            panel,
            "Tetines",
            "tetine",
            "+" .. Theme.formatNumber(cash),
            UDim2.fromOffset(200, 60),
            UDim2.new(0.5, -8, 0, 184),
            Vector2.new(1, 0),
            Theme.YELLOW,
            26
        )
        Theme.pill(
            panel,
            "Experience",
            "etoile",
            "+" .. Theme.formatNumber(xp) .. " XP",
            UDim2.fromOffset(200, 60),
            UDim2.new(0.5, 8, 0, 184),
            Vector2.zero,
            Theme.MINT,
            26
        )
        task.delay(3.6, function()
            if popup.Parent then
                TweenService:Create(popupScale, TweenInfo.new(0.2), { Scale = target * 0.7 }):Play()
                task.delay(0.2, function()
                    popup:Destroy()
                end)
            end
        end)
    end

    local resultRemote = Remotes.Get("ChallengeResult") :: RemoteEvent
    resultRemote.OnClientEvent:Connect(function(kind: any, data: any)
        if kind == "win" then
            Sfx.play("fanfare")
            celebrate(data)
        elseif kind == "fail" then
            Sfx.play("refuse")
            Theme.toast(gui, "Défi raté : " .. tostring(data), Theme.RED)
        elseif kind == "info" then
            Sfx.play("refuse")
            Theme.toast(gui, tostring(data), Theme.YELLOW)
        end
    end)

    for _, name in { "ChallengeEndsAt", "ChallengeTitle", "ChallengeGoal" } do
        player:GetAttributeChangedSignal(name):Connect(onChallenge)
    end
    player:GetAttributeChangedSignal("ChallengeProgress"):Connect(onProgress)
    player:GetAttributeChangedSignal("MenusOuverts"):Connect(refreshVisible)
    player:GetAttributeChangedSignal("VueCoffre"):Connect(refreshVisible)
    onChallenge()

    -- Temps restant, urgence sous 10 s (rouge, battement et petit tic chaque seconde).
    local lastSecond = -1
    RunService.RenderStepped:Connect(function()
        if not active then
            return
        end
        local endsAt = numberAttr("ChallengeEndsAt")
        if endsAt == nil then
            return
        end
        local remaining = endsAt - workspace:GetServerTimeNow()
        timeLabel.Text = formatTime(remaining)
        local urgent = remaining <= URGENT_SECONDS
        local color = if urgent then Theme.RED else Theme.YELLOW
        ring.Color = color
        timeLabel.TextColor3 = if urgent then Theme.RED else Theme.WHITE
        local second = math.ceil(remaining)
        if urgent and second ~= lastSecond and second > 0 then
            lastSecond = second
            Sfx.play("tick", { speed = 1.2 })
            disc.Size = UDim2.fromOffset(82, 82)
            TweenService:Create(disc, TweenInfo.new(0.25), { Size = UDim2.fromOffset(70, 70) }):Play()
        end
    end)
    task.spawn(function()
        while gui.Parent do
            if active then
                place()
            end
            task.wait(1)
        end
    end)
end

return ChallengeController
