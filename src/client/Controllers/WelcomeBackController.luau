--!strict

--[[
    WelcomeBackController
    Coffre cadeau de retour (WelcomeBackService, attribut WelcomeBackTier) : fenetre « Bon retour, voleur ! » avec un
    cadeau anime qui se dandine. Au clic (cadeau ou bouton) : il tremble, le couvercle saute, eclair et etoiles, puis
    les recompenses (tetines, XP, cosmetique) sortent du cadeau avec leur icone.
    Attend la fin du tutoriel et qu'aucun menu ne soit ouvert avant de s'afficher.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Modal = require(script.Parent.Parent.Ui.Modal)
local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

local PANEL = Vector2.new(640, 600)
local GIFT_Y = 200
local PILL_SIZE = Vector2.new(184, 58)
local BOX_COLOR = Color3.fromRGB(255, 132, 188)
local LID_COLOR = Color3.fromRGB(232, 96, 160)

local WelcomeBackController = {}

local player = Players.LocalPlayer
local opened = false

local function tierOf(): number?
    local tier = player:GetAttribute("WelcomeBackTier")
    return if typeof(tier) == "number" then tier else nil
end

local function busy(): boolean
    local menus = player:GetAttribute("MenusOuverts")
    if typeof(menus) == "number" and menus > 0 then
        return true
    end
    if player:GetAttribute("VueCoffre") == true then
        return true
    end
    return player:GetAttribute("TutorialStep") ~= nil and player:GetAttribute("TutorialDone") ~= true
end

local function absenceText(): string
    local hours = player:GetAttribute("WelcomeBackHours")
    if typeof(hours) ~= "number" then
        return "Un cadeau t'attend !"
    end
    local days = math.floor(hours / 24)
    if days >= 2 then
        return string.format("%d jours sans toi ! Un cadeau t'attend.", days)
    end
    return string.format("%d h sans toi ! Un cadeau t'attend.", hours)
end

local function block(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, radius: number): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.BackgroundColor3 = color
    frame.BorderSizePixel = 0
    frame.Size = size
    frame.Position = position
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Parent = parent
    Theme.corner(frame, radius)
    return frame
end

-- Cadeau dessine : boite rose, ruban jaune, couvercle avec noeud (le couvercle est separe pour sauter).
local function buildGift(parent: Instance): (Frame, Frame, Frame)
    local gift = Instance.new("Frame")
    gift.Name = "Cadeau"
    gift.BackgroundTransparency = 1
    gift.Size = UDim2.fromOffset(220, 220)
    gift.Position = UDim2.new(0.5, 0, 0, GIFT_Y)
    gift.AnchorPoint = Vector2.new(0.5, 0.5)
    gift.Parent = parent

    local box = block(gift, "Boite", UDim2.fromOffset(170, 120), UDim2.fromOffset(110, 150), BOX_COLOR, 14)
    Theme.stroke(box, 4, Theme.WHITE)
    block(box, "Ruban", UDim2.fromOffset(30, 120), UDim2.fromScale(0.5, 0.5), Theme.YELLOW, 4)

    local lid = block(gift, "Couvercle", UDim2.fromOffset(196, 44), UDim2.fromOffset(110, 80), LID_COLOR, 12)
    Theme.stroke(lid, 4, Theme.WHITE)
    lid.ZIndex = 3
    local band = block(lid, "Ruban", UDim2.fromOffset(32, 44), UDim2.fromScale(0.5, 0.5), Theme.YELLOW, 4)
    band.ZIndex = 3
    for side = -1, 1, 2 do
        local loop = block(lid, "Boucle", UDim2.fromOffset(52, 34), UDim2.new(0.5, side * 26, 0, -14), Theme.YELLOW, 16)
        loop.Rotation = side * 28
        loop.ZIndex = 4
        Theme.stroke(loop, 3, Theme.WHITE)
    end
    local knot = block(lid, "Noeud", UDim2.fromOffset(26, 26), UDim2.new(0.5, 0, 0, -10), Theme.YELLOW, 13)
    knot.ZIndex = 5

    -- Rayons lumineux qui tournent derriere le cadeau.
    local rays = Instance.new("Frame")
    rays.Name = "Rayons"
    rays.BackgroundTransparency = 1
    rays.Size = UDim2.fromOffset(300, 300)
    rays.Position = UDim2.new(0.5, 0, 0, GIFT_Y)
    rays.AnchorPoint = Vector2.new(0.5, 0.5)
    rays.ZIndex = 0
    rays.Parent = parent
    for i = 1, 10 do
        local ray = Instance.new("Frame")
        ray.Name = "Rayon" .. i
        ray.BorderSizePixel = 0
        ray.BackgroundColor3 = Theme.YELLOW
        ray.BackgroundTransparency = 0.7
        ray.AnchorPoint = Vector2.new(0.5, 1)
        ray.Position = UDim2.fromScale(0.5, 0.5)
        ray.Size = UDim2.fromOffset(16, 140)
        ray.Rotation = (i - 1) * 36
        ray.ZIndex = 0
        ray.Parent = rays
        Theme.corner(ray, 8)
    end
    return gift, lid, rays
end

type Reward = { key: string, text: string, color: Color3 }

local function rewardsOf(result: any): { Reward }
    local list: { Reward } = {}
    if typeof(result) ~= "table" then
        return list
    end
    if typeof(result.cash) == "number" then
        table.insert(list, { key = "tetine", text = "+" .. Theme.formatNumber(result.cash), color = Theme.YELLOW })
    end
    if typeof(result.xp) == "number" then
        table.insert(list, { key = "etoile", text = "+" .. Theme.formatNumber(result.xp) .. " XP", color = Theme.MINT })
    end
    if typeof(result.cosmetic) == "string" then
        local item = Catalog.Get(result.cosmetic)
        if item then
            table.insert(list, { key = item.icon, text = item.name, color = Theme.PINK })
        end
    end
    return list
end

local function open(gui: ScreenGui): ()
    if opened or tierOf() == nil then
        return
    end
    opened = true
    local tier = tierOf() or 1
    Sfx.play("fanfare", { volume = 0.25 })
    local modal = Modal.open(gui, "Bon retour, voleur !", Theme.YELLOW, UDim2.fromOffset(PANEL.X, PANEL.Y))
    local body = Modal.body(modal)

    Theme.label(
        body,
        "Absence",
        absenceText(),
        UDim2.new(1, -20, 0, 36),
        UDim2.fromScale(0.5, 0),
        Theme.SOFT_TEXT,
        Vector2.new(0.5, 0),
        26,
        Enum.TextXAlignment.Center
    )

    local gift, lid, rays = buildGift(body)
    if tier >= 2 then
        -- gros cadeau apres une longue absence
        local big = Instance.new("UIScale")
        big.Scale = 1.12
        big.Parent = gift
    end
    local hint = Theme.label(
        body,
        "Indice",
        if tier >= 2 then "Le GROS cadeau des 3 jours !" else "Clique sur le cadeau !",
        UDim2.new(1, -20, 0, 30),
        UDim2.new(0.5, 0, 0, 330),
        Theme.WHITE,
        Vector2.new(0.5, 0),
        24,
        Enum.TextXAlignment.Center
    )

    local button = Theme.button(
        body,
        "Ouvrir",
        "Ouvrir !",
        Theme.GREEN,
        UDim2.fromOffset(260, 70),
        UDim2.new(0.5, 0, 1, -6),
        Vector2.new(0.5, 1)
    )

    local clickZone = Instance.new("TextButton")
    clickZone.Name = "ZoneClic"
    clickZone.Text = ""
    clickZone.BackgroundTransparency = 1
    clickZone.Size = UDim2.fromScale(1, 1)
    clickZone.ZIndex = 6
    clickZone.Parent = gift

    -- Dandinement du cadeau et rotation des rayons tant que la fenetre est ouverte.
    local state = "idle"
    local clock = 0
    local connection = RunService.RenderStepped:Connect(function(dt: number)
        clock += dt
        rays.Rotation = (rays.Rotation + dt * 25) % 360
        if state == "idle" then
            gift.Rotation = math.sin(clock * 3) * 5
        elseif state == "shake" then
            gift.Rotation = math.sin(clock * 40) * 9
        else
            gift.Rotation = 0
        end
    end)
    modal.root.Destroying:Connect(function()
        connection:Disconnect()
    end)

    local function burst(): ()
        local flash =
            block(body, "Eclair", UDim2.fromOffset(40, 40), UDim2.new(0.5, 0, 0, GIFT_Y - 40), Theme.WHITE, 20)
        flash.ZIndex = 7
        TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {
            Size = UDim2.fromOffset(380, 380),
            BackgroundTransparency = 1,
        }):Play()
        task.delay(0.5, function()
            flash:Destroy()
        end)
        for i = 1, 12 do
            local angle = math.rad((i - 1) * 30 + math.random(-10, 10))
            local star = Theme.image(
                body,
                "Etincelle",
                "etoile",
                UDim2.fromOffset(30, 30),
                UDim2.new(0.5, 0, 0, GIFT_Y - 40),
                Vector2.new(0.5, 0.5)
            )
            star.ZIndex = 8
            local distance = math.random(130, 220)
            TweenService:Create(star, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = UDim2.new(
                    0.5,
                    math.cos(angle) * distance,
                    0,
                    GIFT_Y - 40 + math.sin(angle) * distance * 0.7
                ),
                Rotation = math.random(-180, 180),
                Size = UDim2.fromOffset(14, 14),
            }):Play()
            if star:IsA("ImageLabel") then
                TweenService:Create(star, TweenInfo.new(0.7), { ImageTransparency = 1 }):Play()
            end
            task.delay(0.75, function()
                star:Destroy()
            end)
        end
    end

    local function showRewards(rewards: { Reward }): ()
        local count = #rewards
        local gap = 14
        local total = count * PILL_SIZE.X + math.max(count - 1, 0) * gap
        for i, reward in rewards do
            local x = -total / 2 + PILL_SIZE.X / 2 + (i - 1) * (PILL_SIZE.X + gap)
            local pill = Theme.pill(
                body,
                "Recompense" .. i,
                reward.key,
                reward.text,
                UDim2.fromOffset(PILL_SIZE.X * 0.3, PILL_SIZE.Y * 0.3),
                UDim2.new(0.5, 0, 0, GIFT_Y),
                Vector2.new(0.5, 0.5),
                reward.color,
                24
            )
            pill.ZIndex = 9
            Theme.stroke(pill, 3, reward.color)
            task.delay((i - 1) * 0.18, function()
                TweenService:Create(pill, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                    Size = UDim2.fromOffset(PILL_SIZE.X, PILL_SIZE.Y),
                    Position = UDim2.new(0.5, x, 0, 395),
                }):Play()
                Sfx.play("deposit", { speed = 1 + i * 0.1 })
            end)
        end
    end

    local busyClaim = false
    local done = false
    local function claim(): ()
        if done then
            modal.close()
            return
        end
        if busyClaim then
            return
        end
        busyClaim = true
        button.Text = "..."
        state = "shake"
        clock = 0
        Sfx.play("click")
        task.wait(0.5)
        local remote = Remotes.Get("WelcomeBack") :: RemoteFunction
        -- InvokeServer renvoie (ok, recompense) : pcall les passe apres son propre « ok ».
        local called, success, payload = pcall(function()
            return remote:InvokeServer("claim")
        end)
        state = "open"
        if not called or success ~= true then
            busyClaim = false
            state = "idle"
            button.Text = "Ouvrir !"
            Sfx.play("refuse")
            Theme.toast(gui, "Le cadeau résiste... réessaie !", Theme.RED)
            return
        end
        done = true
        Sfx.play("giftOpen")
        TweenService:Create(lid, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.fromOffset(170, -60),
            Rotation = 38,
            BackgroundTransparency = 1,
        }):Play()
        for _, child in lid:GetDescendants() do
            if child:IsA("Frame") then
                TweenService:Create(child, TweenInfo.new(0.55), { BackgroundTransparency = 1 }):Play()
            elseif child:IsA("UIStroke") then
                TweenService:Create(child, TweenInfo.new(0.55), { Transparency = 1 }):Play()
            end
        end
        local lidStroke = lid:FindFirstChildOfClass("UIStroke")
        if lidStroke then
            TweenService:Create(lidStroke, TweenInfo.new(0.55), { Transparency = 1 }):Play()
        end
        burst()
        hint.Text = "Bon retour parmi les voleurs !"
        hint.TextColor3 = Theme.YELLOW
        task.delay(0.25, function()
            Sfx.play("fanfare")
            showRewards(rewardsOf(payload))
        end)
        button.Text = "Super !"
        busyClaim = false
    end
    button.Activated:Connect(claim)
    clickZone.Activated:Connect(claim)
    modal.root.Destroying:Connect(function()
        -- Fermee sans ouvrir : le cadeau reste en attente cote serveur (profile.daily.welcomePending) et revient a
        -- la prochaine connexion ; « opened » reste vrai pour ne pas la rouvrir en boucle pendant cette session.
        opened = true
    end)
end

function WelcomeBackController:Init(): () end

function WelcomeBackController:Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "CadeauRetour"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 12
    gui.Parent = player:WaitForChild("PlayerGui")

    -- Laisse passer les fenetres d'arrivee (recompense du jour...) puis ouvre des que la voie est libre.
    task.spawn(function()
        task.wait(4)
        while gui.Parent do
            if not opened and tierOf() ~= nil and not busy() then
                open(gui)
            end
            task.wait(1)
        end
    end)
end

return WelcomeBackController
