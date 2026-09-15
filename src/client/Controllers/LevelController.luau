--!strict

--[[
    LevelController
    Le niveau du joueur a l'ecran (LevelService publie Level, Xp, XpNeeded, Title, XpGain, LevelReward) :
    - barre d'XP juste sous le compteur de tetines (haut gauche) : pastille du niveau, barre qui se remplit en
      douceur, titre et XP ; « +40 XP » qui s'envole avec une etoile a chaque gain ;
    - montee de niveau : grosse celebration au centre (« NIVEAU 12 ! » qui rebondit, rayons qui tournent, etoiles
      qui jaillissent, fanfare), recompenses en icones (tetines, cosmetique), nouveau titre, et la prochaine grosse
      recompense. Plusieurs montees d'affilee passent l'une apres l'autre.
    Ecran a part (ScreenGui « Niveau ») : aucune modification du HUD existant.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Levels = require(Shared:WaitForChild("Levels"))

local Theme = require(script.Parent.Parent.Ui.Theme)

-- « Mascot Party - Mnemonic1 » (KPM, bibliotheque audio de Roblox) : petite fanfare joyeuse et courte.
local LEVEL_UP_SOUND = "rbxassetid://9045119921"
local CELEBRATION_SECONDS = 3.8
-- Bloc des tetines du HUD : en (14, 62), 108 de haut a l'echelle HUD ; la barre se pose juste dessous.
local MONEY_TOP, MONEY_HEIGHT, GAP = 62, 108, 6

local LevelController = {}

local player = Players.LocalPlayer

local function numberAttribute(name: string, default: number): number
    local value = player:GetAttribute(name)
    return if typeof(value) == "number" then value else default
end

local function fade(object: Instance, seconds: number): ()
    local items = object:GetDescendants()
    table.insert(items, object)
    for _, item in items do
        local goal: { [string]: number } = {}
        if item:IsA("TextLabel") then
            goal.TextTransparency = 1
        elseif item:IsA("ImageLabel") then
            goal.ImageTransparency = 1
        elseif item:IsA("Frame") and item.BackgroundTransparency < 1 then
            goal.BackgroundTransparency = 1
        elseif item:IsA("UIStroke") then
            goal.Transparency = 1
        end
        if next(goal) then
            TweenService:Create(item, TweenInfo.new(seconds), goal):Play()
        end
    end
end

-- Pastille « icone + texte » des recompenses.
local function pill(parent: Instance, name: string, icon: string, text: string, color: Color3): ()
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.Size = UDim2.fromOffset(250, 58)
    frame.BackgroundColor3 = Theme.NAVY
    frame.BackgroundTransparency = 0.1
    frame.Parent = parent
    Theme.corner(frame, 29)
    Theme.stroke(frame, 2, Theme.WHITE)
    Theme.image(frame, "Icone", icon, UDim2.fromOffset(46, 46), UDim2.new(0, 8, 0.5, 0), Vector2.new(0, 0.5))
    local label =
        Theme.text(frame, "Texte", text, UDim2.new(1, -70, 0, 36), UDim2.new(0, 60, 0.5, 0), color, Vector2.new(0, 0.5))
    label.TextXAlignment = Enum.TextXAlignment.Left
end

function LevelController:Init(): () end

function LevelController:Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "Niveau"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 5
    gui.Parent = player:WaitForChild("PlayerGui")

    -- Barre d'XP (dessinee en 350 x 52, mise a l'echelle comme le HUD)
    local bar = Instance.new("Frame")
    bar.Name = "BarreXp"
    bar.BackgroundTransparency = 1
    bar.Size = UDim2.fromOffset(350, 52)
    bar.Parent = gui
    Theme.fit(bar, Theme.HUD_FACTOR)
    local function place(): ()
        local k = Theme.viewportFactor() * Theme.HUD_FACTOR
        bar.Position = UDim2.fromOffset(14, MONEY_TOP + (MONEY_HEIGHT + GAP) * k)
    end
    place()
    Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place)

    local badge = Instance.new("Frame")
    badge.Name = "Pastille"
    badge.Size = UDim2.fromOffset(52, 52)
    badge.BackgroundColor3 = Theme.NAVY
    badge.Parent = bar
    Theme.corner(badge, 26)
    Theme.stroke(badge, 3, Theme.YELLOW)
    local levelLabel = Theme.text(
        badge,
        "Niveau",
        "1",
        UDim2.fromScale(0.7, 0.62),
        UDim2.fromScale(0.5, 0.5),
        Theme.YELLOW,
        Vector2.new(0.5, 0.5)
    )

    local track = Instance.new("Frame")
    track.Name = "Jauge"
    track.Position = UDim2.fromOffset(60, 6)
    track.Size = UDim2.fromOffset(290, 22)
    track.BackgroundColor3 = Theme.NAVY_DARK
    track.ClipsDescendants = true
    track.Parent = bar
    Theme.corner(track, 11)
    Theme.stroke(track, 2, Theme.WHITE)
    local fill = Instance.new("Frame")
    fill.Name = "Remplissage"
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = Theme.WHITE
    fill.BorderSizePixel = 0
    fill.Parent = track
    Theme.corner(fill, 11)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new(Theme.MINT, Theme.YELLOW)
    gradient.Parent = fill

    local info =
        Theme.text(bar, "Infos", "", UDim2.fromOffset(290, 20), UDim2.fromOffset(60, 31), Theme.SOFT_TEXT, Vector2.zero)
    info.TextXAlignment = Enum.TextXAlignment.Left

    local shownLevel = numberAttribute("Level", 1)

    local function refresh(animate: boolean): ()
        local level = numberAttribute("Level", 1)
        local xp = numberAttribute("Xp", 0)
        local needed = math.max(numberAttribute("XpNeeded", Levels.XpNeeded(level)), 1)
        local fraction = if level >= Levels.MAX_LEVEL then 1 else math.clamp(xp / needed, 0, 1)
        levelLabel.Text = tostring(level)
        local title = player:GetAttribute("Title")
        local titleText = if typeof(title) == "string" then title else Levels.TitleFor(level)
        info.Text = if level >= Levels.MAX_LEVEL
            then titleText .. "  ·  MAX"
            else string.format("%s  ·  %s / %s XP", titleText, Theme.formatNumber(xp), Theme.formatNumber(needed))
        if not animate then
            fill.Size = UDim2.fromScale(fraction, 1)
        elseif level > shownLevel then
            -- la barre finit de se remplir, repart de zero puis monte a la nouvelle valeur
            local full =
                TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, 1) })
            full.Completed:Connect(function()
                fill.Size = UDim2.fromScale(0, 1)
                TweenService
                    :Create(fill, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(fraction, 1) })
                    :Play()
            end)
            full:Play()
        else
            TweenService
                :Create(fill, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(fraction, 1) })
                :Play()
        end
        shownLevel = level
    end
    refresh(false)
    for _, name in { "Xp", "XpNeeded", "Title" } do
        player:GetAttributeChangedSignal(name):Connect(function()
            refresh(true)
        end)
    end

    -- « +40 XP » qui s'envole de la fin de la barre
    player:GetAttributeChangedSignal("XpGain"):Connect(function()
        local raw = player:GetAttribute("XpGain")
        if typeof(raw) ~= "string" then
            return
        end
        local amount = tonumber(string.match(raw, "^%d+:(%d+)"))
        if amount == nil or amount <= 0 then
            return
        end
        local pop = Instance.new("Frame")
        pop.Name = "GainXp"
        pop.BackgroundTransparency = 1
        pop.Size = UDim2.fromOffset(120, 30)
        pop.Position = UDim2.fromOffset(230, -2)
        pop.Parent = bar
        Theme.image(pop, "Etoile", "etoile", UDim2.fromOffset(26, 26), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5))
        local text = Theme.text(
            pop,
            "Texte",
            string.format("+%s XP", Theme.formatNumber(amount)),
            UDim2.fromOffset(90, 26),
            UDim2.new(0, 30, 0.5, 0),
            Theme.YELLOW,
            Vector2.new(0, 0.5)
        )
        text.TextXAlignment = Enum.TextXAlignment.Left
        TweenService:Create(pop, TweenInfo.new(1.1, Enum.EasingStyle.Quad), { Position = UDim2.fromOffset(230, -40) })
            :Play()
        task.delay(0.5, function()
            fade(pop, 0.6)
        end)
        task.delay(1.2, function()
            pop:Destroy()
        end)
    end)

    -- Celebration de montee de niveau
    local queue: { { level: number, reward: any } } = {}
    local playing = false

    local function celebrate(level: number, reward: any): ()
        local holder = Instance.new("Frame")
        holder.Name = "MonteeNiveau"
        holder.BackgroundTransparency = 1
        holder.Size = UDim2.fromOffset(720, 430)
        -- Sous le bandeau d'evenement s'il est affiche : son compte a rebours (maman, orage...) reste lisible
        -- (capture combo-fil : « NIVEAU 2 ! » passait sous « CAUCHEMAR ! »).
        local playerGui = player:FindFirstChildOfClass("PlayerGui")
        local banner = if playerGui then playerGui:FindFirstChild("BandeauEvenement", true) else nil
        local bannerShown = banner ~= nil and banner:IsA("GuiObject") and banner.Visible
        holder.Position = UDim2.fromScale(0.5, if bannerShown then 0.6 else 0.42)
        holder.AnchorPoint = Vector2.new(0.5, 0.5)
        holder.Parent = gui
        local scale = Theme.fit(holder, 0.9)
        local target = scale.Scale

        -- rayons (chacun tourne : la rotation d'un parent ne s'applique pas a ses enfants)
        local rays: { Frame } = {}
        for i = 1, 12 do
            local ray = Instance.new("Frame")
            ray.Name = "Rayon" .. i
            ray.Size = UDim2.fromOffset(34, 440)
            ray.Position = UDim2.fromOffset(360, 190)
            ray.AnchorPoint = Vector2.new(0.5, 0.5)
            ray.BackgroundColor3 = Theme.YELLOW
            ray.BackgroundTransparency = 0.55
            ray.BorderSizePixel = 0
            ray.Rotation = i * 15
            ray.Parent = holder
            local rayGradient = Instance.new("UIGradient")
            rayGradient.Rotation = 90
            rayGradient.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.5, 0.2),
                NumberSequenceKeypoint.new(1, 1),
            })
            rayGradient.Parent = ray
            table.insert(rays, ray)
        end
        local started = os.clock()
        local spin = RunService.RenderStepped:Connect(function()
            local angle = (os.clock() - started) * 40
            for i, ray in rays do
                ray.Rotation = i * 15 + angle
            end
        end)

        local titleLabel = Theme.text(
            holder,
            "Titre",
            string.format("NIVEAU %d !", level),
            UDim2.fromOffset(700, 110),
            UDim2.fromOffset(360, 190),
            Theme.YELLOW,
            Vector2.new(0.5, 0.5)
        )
        local titleStroke = titleLabel:FindFirstChildOfClass("UIStroke")
        if titleStroke then
            titleStroke.Thickness = 5
        end
        local pop = Instance.new("UIScale")
        pop.Scale = 0.2
        pop.Parent = titleLabel
        TweenService:Create(pop, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
            :Play()

        local newTitle = if typeof(reward) == "table" and typeof(reward.title) == "string" then reward.title else nil
        if newTitle then
            Theme.text(
                holder,
                "NouveauTitre",
                "Nouveau titre : " .. newTitle,
                UDim2.fromOffset(560, 38),
                UDim2.fromOffset(360, 262),
                Theme.PINK,
                Vector2.new(0.5, 0.5)
            )
        end

        local row = Instance.new("Frame")
        row.Name = "Recompenses"
        row.BackgroundTransparency = 1
        row.Size = UDim2.fromOffset(700, 58)
        row.Position = UDim2.fromOffset(360, 322)
        row.AnchorPoint = Vector2.new(0.5, 0.5)
        row.Parent = holder
        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.VerticalAlignment = Enum.VerticalAlignment.Center
        layout.Padding = UDim.new(0, 16)
        layout.Parent = row
        local cash = if typeof(reward) == "table" and typeof(reward.cash) == "number" then reward.cash else 0
        if cash > 0 then
            pill(row, "Tetines", "tetine", "+" .. Theme.formatNumber(cash), Theme.YELLOW)
        end
        local cosmeticId = if typeof(reward) == "table" and typeof(reward.cosmetic) == "string"
            then reward.cosmetic
            else nil
        local item = if cosmeticId then Catalog.Get(cosmeticId) else nil
        if item then
            pill(row, "Cosmetique", item.icon, item.name, Theme.MINT)
        end

        local nextMilestone = Levels.NextMilestone(level)
        Theme.text(
            holder,
            "Prochaine",
            if nextMilestone
                then string.format("Prochaine grosse récompense : niveau %d", nextMilestone)
                else "Niveau maximum !",
            UDim2.fromOffset(560, 30),
            UDim2.fromOffset(360, 385),
            Theme.SOFT_TEXT,
            Vector2.new(0.5, 0.5)
        )

        -- etoiles qui jaillissent du centre
        for i = 1, 10 do
            local star = Theme.image(
                holder,
                "Eclat" .. i,
                "etoile",
                UDim2.fromOffset(34, 34),
                UDim2.fromOffset(360, 190),
                Vector2.new(0.5, 0.5)
            )
            local angle = (i / 10) * math.pi * 2
            local distance = 230 + (i % 3) * 40
            TweenService
                :Create(star, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
                    Position = UDim2.fromOffset(
                        360 + math.cos(angle) * distance,
                        190 + math.sin(angle) * distance * 0.6
                    ),
                })
                :Play()
            task.delay(0.5, function()
                fade(star, 0.4)
            end)
        end

        local sound = Instance.new("Sound")
        sound.SoundId = LEVEL_UP_SOUND
        sound.Volume = 0.6
        sound.Parent = SoundService
        sound:Play()
        task.delay(6, function()
            sound:Destroy()
        end)

        task.wait(CELEBRATION_SECONDS)
        fade(holder, 0.3)
        TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Scale = target * 1.15 }):Play()
        task.wait(0.35)
        spin:Disconnect()
        holder:Destroy()
    end

    local lastLevel = numberAttribute("Level", 1)
    player:GetAttributeChangedSignal("Level"):Connect(function()
        local level = numberAttribute("Level", 1)
        refresh(true)
        if level <= lastLevel then
            lastLevel = level
            return
        end
        lastLevel = level
        local raw = player:GetAttribute("LevelReward")
        local reward: any = nil
        if typeof(raw) == "string" then
            local ok, decoded = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            reward = if ok then decoded else nil
        end
        table.insert(queue, { level = level, reward = reward })
        if playing then
            return
        end
        playing = true
        task.spawn(function()
            while #queue > 0 do
                local entry = table.remove(queue, 1)
                if entry then
                    celebrate(entry.level, entry.reward)
                end
            end
            playing = false
        end)
    end)
end

return LevelController
