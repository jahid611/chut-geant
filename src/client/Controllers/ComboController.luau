--!strict

--[[
    ComboController
    Combo de discretion (ComboService, attribut joueur Combo) : badge compact colle a droite de la jauge CHUT en
    haut au centre. Juste sous la jauge il n'y a que ~14 px avant les bandeaux d'evenements (EventController,
    y = 118) : le badge est donc cale a droite de la jauge, centre sur sa hauteur, sans chevaucher le badge du bebe.
    - « x3 » en gros avec une etoile, eclats qui grossissent et tournent avec le combo ;
    - montee : « COMBO x3 ! » qui rebondit et son ; cassure : « Combo perdu ! » gris qui tombe et s'efface ;
    - cache a x1, pendant les menus (MenusOuverts) et la vue coffre (VueCoffre).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

local MAX_COMBO = 5
local COLORS: { Color3 } = {
    Theme.WHITE,
    Color3.fromRGB(140, 225, 170),
    Color3.fromRGB(255, 214, 90),
    Color3.fromRGB(255, 150, 70),
    Color3.fromRGB(255, 95, 140),
}

local ComboController = {}

local player = Players.LocalPlayer

local function comboOf(): number
    local value = player:GetAttribute("Combo")
    return if typeof(value) == "number" then math.clamp(math.floor(value), 1, MAX_COMBO) else 1
end

function ComboController:Init(): () end

function ComboController:Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "Combo"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 6
    gui.Parent = player:WaitForChild("PlayerGui")

    local holder = Instance.new("Frame")
    holder.Name = "BadgeCombo"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(170, 120)
    holder.AnchorPoint = Vector2.new(0, 0.5)
    holder.Position = UDim2.new(0.5, 310, 0, 60)
    holder.Visible = false
    holder.Parent = gui
    local scale = Theme.fit(holder, Theme.HUD_FACTOR)

    -- Cale le badge a droite de la jauge « Bruit » du HUD quand elle existe (sans modifier HudController).
    local function place(): ()
        local hud = player.PlayerGui:FindFirstChild("HUD")
        local noise = if hud then hud:FindFirstChild("Bruit") else nil
        if noise and noise:IsA("GuiObject") and noise.AbsoluteSize.X > 0 then
            local right = noise.AbsolutePosition.X + noise.AbsoluteSize.X
            local middle = noise.AbsolutePosition.Y + noise.AbsoluteSize.Y * 0.42
            holder.Position = UDim2.fromOffset(right + 6, middle)
        end
    end

    -- Eclats derriere le chiffre : 8 rayons fins qui tournent, plus nombreux et plus grands avec le combo.
    local burst = Instance.new("Frame")
    burst.Name = "Eclats"
    burst.BackgroundTransparency = 1
    burst.Size = UDim2.fromOffset(120, 120)
    burst.Position = UDim2.fromOffset(60, 60)
    burst.AnchorPoint = Vector2.new(0.5, 0.5)
    burst.Parent = holder
    local rays: { Frame } = {}
    for i = 1, 8 do
        local ray = Instance.new("Frame")
        ray.Name = "Rayon" .. i
        ray.BorderSizePixel = 0
        ray.AnchorPoint = Vector2.new(0.5, 1)
        ray.Position = UDim2.fromScale(0.5, 0.5)
        ray.Size = UDim2.fromOffset(8, 50)
        ray.Rotation = (i - 1) * 45
        ray.BackgroundTransparency = 0.35
        ray.Parent = burst
        Theme.corner(ray, 4)
        table.insert(rays, ray)
    end

    local disc = Instance.new("Frame")
    disc.Name = "Pastille"
    disc.BackgroundColor3 = Theme.NAVY_DARK
    disc.Size = UDim2.fromOffset(84, 84)
    disc.Position = UDim2.fromOffset(60, 60)
    disc.AnchorPoint = Vector2.new(0.5, 0.5)
    disc.Parent = holder
    Theme.corner(disc, 42)
    local ring = Theme.stroke(disc, 4, Theme.YELLOW)

    Theme.image(disc, "Etoile", "etoile", UDim2.fromOffset(34, 34), UDim2.new(0.5, 0, 0, -8), Vector2.new(0.5, 0))
    local count = Theme.text(
        disc,
        "Multiplicateur",
        "x2",
        UDim2.fromOffset(76, 44),
        UDim2.new(0.5, 0, 0.5, 10),
        Theme.WHITE,
        Vector2.new(0.5, 0.5)
    )
    local label = Theme.text(
        holder,
        "Libelle",
        "COMBO",
        UDim2.fromOffset(70, 22),
        UDim2.fromOffset(136, 60),
        Theme.WHITE,
        Vector2.new(0.5, 0.5)
    )

    local visibleCombo = 1
    local function refreshVisible(): ()
        local menus = player:GetAttribute("MenusOuverts")
        local hidden = (typeof(menus) == "number" and menus > 0) or player:GetAttribute("VueCoffre") == true
        holder.Visible = visibleCombo >= 2 and not hidden
    end

    local function paint(combo: number): ()
        local color = COLORS[combo] or Theme.WHITE
        count.Text = "x" .. combo
        count.TextColor3 = color
        label.TextColor3 = color
        ring.Color = color
        for i, ray in rays do
            ray.BackgroundColor3 = color
            -- plus de rayons visibles et plus longs avec le combo
            ray.Visible = i <= combo * 2 - 2
            ray.Size = UDim2.fromOffset(8, 30 + combo * 8)
        end
    end

    -- Texte d'annonce sous le badge : « COMBO x3 ! » qui rebondit, ou « Combo perdu ! » gris qui tombe.
    local function announce(text: string, color: Color3, falling: boolean): ()
        local popup = Theme.text(
            gui,
            "AnnonceCombo",
            text,
            UDim2.fromOffset(260, 44),
            UDim2.fromOffset(
                holder.AbsolutePosition.X + holder.AbsoluteSize.X / 2,
                holder.AbsolutePosition.Y + holder.AbsoluteSize.Y + 4
            ),
            color,
            Vector2.new(0.5, 0)
        )
        local popupScale = Instance.new("UIScale")
        popupScale.Scale = scale.Scale * (if falling then 1 else 0.4)
        popupScale.Parent = popup
        if falling then
            TweenService:Create(popup, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = popup.Position + UDim2.fromOffset(0, 40),
                TextTransparency = 1,
            }):Play()
        else
            TweenService:Create(popupScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = scale.Scale }):Play()
            task.delay(0.9, function()
                TweenService:Create(popup, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
            end)
        end
        local stroke = popup:FindFirstChildOfClass("UIStroke")
        if stroke then
            TweenService:Create(stroke, TweenInfo.new(1.3), { Transparency = 1 }):Play()
        end
        task.delay(1.4, function()
            popup:Destroy()
        end)
    end

    local function onCombo(): ()
        local combo = comboOf()
        local previous = visibleCombo
        visibleCombo = combo
        place()
        if combo >= 2 then
            paint(combo)
        end
        refreshVisible()
        if combo > previous and combo >= 2 then
            -- petit rebond du badge
            disc.Size = UDim2.fromOffset(110, 110)
            TweenService:Create(disc, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(84, 84) })
                :Play()
            announce("COMBO x" .. combo .. " !", COLORS[combo] or Theme.YELLOW, false)
            Sfx.play("comboUp", { speed = 0.9 + combo * 0.1 })
        elseif combo < previous and previous >= 2 then
            announce("Combo perdu !", Theme.GREY, true)
            Sfx.play("comboBreak")
        end
    end

    player:GetAttributeChangedSignal("Combo"):Connect(onCombo)
    player:GetAttributeChangedSignal("MenusOuverts"):Connect(refreshVisible)
    player:GetAttributeChangedSignal("VueCoffre"):Connect(refreshVisible)
    visibleCombo = comboOf()
    paint(math.max(visibleCombo, 2))
    refreshVisible()

    -- rotation lente des eclats et recalage si l'ecran change
    RunService.RenderStepped:Connect(function(dt: number)
        if holder.Visible then
            burst.Rotation = (burst.Rotation + dt * (20 + visibleCombo * 12)) % 360
        end
    end)
    task.spawn(function()
        while gui.Parent do
            place()
            task.wait(1)
        end
    end)
end

return ComboController
