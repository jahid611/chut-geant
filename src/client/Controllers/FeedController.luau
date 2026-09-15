--!strict

--[[
    FeedController
    Fil d'actualite du serveur (remote Feed, FeedService) : messages courts empiles en haut a droite, SOUS le badge
    d'etat du bebe et la place de l'icone de pleine lune (MoonController), 4 visibles au plus, le plus recent en haut.
    Chaque message : icone (image du jouet si elle existe, sinon icone de repli), texte dont une partie coloree,
    entree en glissant, disparition apres LIFETIME secondes. Un message identique deja affiche est regroupe (« x2 »)
    et reste plus longtemps.
    Cache pendant les menus (MenusOuverts), la vue coffre (VueCoffre) et le tutoriel (sa bulle occupe la droite).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Assets = require(script.Parent.Parent.Ui.Assets)
local Theme = require(script.Parent.Parent.Ui.Theme)

-- Reperes du HUD (px avant echelle, meme echelle Theme.HUD_FACTOR) : badge du bebe 250 x 86 a 14 px du bord,
-- icone de pleine lune dessous (hauteur ICON + 28 + 34 = 154, a 10 px sous le badge).
local HUD_MARGIN = 14
local BABY_BADGE_HEIGHT = 86
local MOON_BLOCK_HEIGHT = 154
local WIDTH = 380
local ROW_HEIGHT = 54
local GAP = 6
local MAX_ROWS = 4
local LIFETIME = 6

type Row = { frame: CanvasGroup, count: number, token: number, countLabel: TextLabel }

local FeedController = {}

local player = Players.LocalPlayer
local rows: { [string]: Row } = {}
local order: { string } = {}
local counter = 0

local function escape(text: string): string
    return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function hexOf(color: Color3): string
    return string.format(
        "#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

local function iconKey(key: any, fallback: any): string
    if typeof(key) == "string" then
        local id = Assets[key]
        if id and id ~= "rbxassetid://0" then
            return key
        end
    end
    return if typeof(fallback) == "string" then fallback else "tetine"
end

local function removeRow(text: string, instant: boolean): ()
    local row = rows[text]
    if row == nil then
        return
    end
    rows[text] = nil
    local index = table.find(order, text)
    if index then
        table.remove(order, index)
    end
    if instant then
        row.frame:Destroy()
        return
    end
    local fade = TweenService:Create(row.frame, TweenInfo.new(0.35), { GroupTransparency = 1 })
    fade.Completed:Connect(function()
        row.frame:Destroy()
    end)
    fade:Play()
end

local function schedule(text: string, row: Row): ()
    row.token += 1
    local token = row.token
    task.delay(LIFETIME, function()
        if rows[text] == row and row.token == token then
            removeRow(text, false)
        end
    end)
end

function FeedController:Init(): () end

function FeedController:Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "FilActualite"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 4
    gui.Parent = player:WaitForChild("PlayerGui")

    local holder = Instance.new("Frame")
    holder.Name = "Fil"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(WIDTH, MAX_ROWS * ROW_HEIGHT + (MAX_ROWS - 1) * GAP)
    holder.AnchorPoint = Vector2.new(1, 0)
    holder.Parent = gui
    local scale = Theme.fit(holder, Theme.HUD_FACTOR)
    -- l'echelle agit autour du coin haut droit (point d'ancrage) : on recalcule la hauteur de depart a chaque taille
    local function place(): ()
        local s = scale.Scale
        local top = HUD_MARGIN + (BABY_BADGE_HEIGHT + 10 + MOON_BLOCK_HEIGHT + 10) * s
        holder.Position = UDim2.new(1, -HUD_MARGIN, 0, top)
    end
    scale:GetPropertyChangedSignal("Scale"):Connect(place)
    place()

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, GAP)
    layout.Parent = holder

    local function refreshVisible(): ()
        local menus = player:GetAttribute("MenusOuverts")
        local inTutorial = player:GetAttribute("TutorialStep") ~= nil and player:GetAttribute("TutorialDone") ~= true
        gui.Enabled = not (typeof(menus) == "number" and menus > 0)
            and player:GetAttribute("VueCoffre") ~= true
            and not inTutorial
    end
    for _, name in { "MenusOuverts", "VueCoffre", "TutorialStep", "TutorialDone" } do
        player:GetAttributeChangedSignal(name):Connect(refreshVisible)
    end
    refreshVisible()

    local remote = Remotes.Get("Feed") :: RemoteEvent
    remote.OnClientEvent:Connect(function(message: any)
        if typeof(message) ~= "table" then
            return
        end
        local before = if typeof(message.before) == "string" then message.before else ""
        local accent = if typeof(message.accent) == "string" then message.accent else ""
        local after = if typeof(message.after) == "string" then message.after else ""
        local text = before .. accent .. after
        if text == "" then
            return
        end
        counter += 1

        -- Message identique deja affiche : regroupe, remonte en haut et reste plus longtemps.
        local existing = rows[text]
        if existing then
            existing.count += 1
            existing.countLabel.Text = "x" .. existing.count
            existing.countLabel.Visible = true
            existing.frame.LayoutOrder = -counter
            schedule(text, existing)
            return
        end

        while #order >= MAX_ROWS do
            removeRow(order[1], true)
        end

        local color: Color3 = if typeof(message.color) == "Color3" then message.color else Theme.YELLOW
        local frame = Instance.new("CanvasGroup")
        frame.Name = "Message"
        frame.BackgroundColor3 = Theme.NAVY_DARK
        frame.BackgroundTransparency = 0.12
        frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
        frame.LayoutOrder = -counter
        frame.GroupTransparency = 1
        frame.Parent = holder
        Theme.corner(frame, 16)
        local stroke = Theme.stroke(frame, 2, color)
        stroke.Transparency = 0.35

        local inner = Instance.new("Frame")
        inner.Name = "Contenu"
        inner.BackgroundTransparency = 1
        inner.Size = UDim2.fromScale(1, 1)
        inner.Position = UDim2.fromOffset(40, 0)
        inner.Parent = frame

        Theme.icon(
            inner,
            "Icone",
            iconKey(message.icon, message.fallback),
            UDim2.fromOffset(42, 42),
            UDim2.new(0, 8, 0.5, 0),
            Vector2.new(0, 0.5),
            color
        )
        local label = Theme.label(
            inner,
            "Texte",
            "",
            UDim2.new(1, -110, 1, -10),
            UDim2.new(0, 58, 0.5, 0),
            Theme.WHITE,
            Vector2.new(0, 0.5),
            20,
            Enum.TextXAlignment.Left
        )
        label.RichText = true
        label.TextWrapped = true
        label.Text = escape(before)
            .. '<font color="'
            .. hexOf(color)
            .. '">'
            .. escape(accent)
            .. "</font>"
            .. escape(after)

        local countLabel = Theme.label(
            inner,
            "Nombre",
            "x1",
            UDim2.fromOffset(40, 30),
            UDim2.new(1, -8, 0.5, 0),
            color,
            Vector2.new(1, 0.5),
            18,
            Enum.TextXAlignment.Right
        )
        countLabel.Visible = false

        local row: Row = { frame = frame, count = 1, token = 0, countLabel = countLabel }
        rows[text] = row
        table.insert(order, text)
        TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
        TweenService:Create(inner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.fromOffset(0, 0) })
            :Play()
        schedule(text, row)
    end)
end

return FeedController
