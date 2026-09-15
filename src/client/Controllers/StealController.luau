--!strict

--[[
    StealController
    Vol entre joueurs et verrou de base, cote joueur :
    - cache le bouton « Voler » sur ses propres coffres et le bouton « Verrouiller » des bases des autres ;
    - alarme quand on se fait voler : bandeau rouge, son, fleche vers le coffre pille pendant ALERT_SECONDS ;
    - messages courts (vol en cours, reussi, jouet rendu, refus) ;
    - bouton rond « Verrouiller » avec un cadenas, a droite de l'ecran, visible quand on est dans sa base : verrou
      en cours (secondes restantes) ou recharge.
    Remotes : StealNotice (serveur -> client), LockBase (client -> serveur).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Zone = require(Shared:WaitForChild("Zone"))

local Assets = require(script.Parent.Parent.Ui.Assets)
local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

local ALERT_SECONDS = 8
local BASE_TAG = "Base"

local StealController = {}

local player = Players.LocalPlayer
local gui: ScreenGui

-- Boutons de proximite qui ne concernent pas ce joueur : caches localement (le serveur verifie tout).
local function filterPrompt(instance: Instance): ()
    if not instance:IsA("ProximityPrompt") then
        return
    end
    local prompt = instance
    if prompt.Name == "PromptVol" then
        local folder = prompt:FindFirstAncestorWhichIsA("Folder")
        while folder and string.match(folder.Name, "^Base_%d+$") == nil do
            folder = folder:FindFirstAncestorWhichIsA("Folder")
        end
        if folder and folder.Name == "Base_" .. player.UserId then
            prompt.Enabled = false
        end
    elseif prompt.Name == "PromptVerrou" then
        local desk = prompt.Parent
        if desk == nil then
            return
        end
        local function sync(): ()
            prompt.Enabled = desk:GetAttribute("OwnerUserId") == player.UserId
        end
        desk:GetAttributeChangedSignal("OwnerUserId"):Connect(sync)
        sync()
    end
end

local function bannerText(parent: Instance, name: string, text: string, height: number, y: number, color: Color3)
    local label =
        Theme.text(parent, name, text, UDim2.new(1, 0, 0, height), UDim2.new(0.5, 0, 0, y), color, Vector2.new(0.5, 0))
    local stroke = label:FindFirstChildOfClass("UIStroke")
    if stroke then
        stroke.Thickness = 4
    end
    return label
end

-- Gros bandeau d'alarme au milieu haut de l'ecran.
local function alarmBanner(thiefName: string): ()
    local old = gui:FindFirstChild("AlarmeVol")
    if old then
        old:Destroy()
    end
    local holder = Instance.new("Frame")
    holder.Name = "AlarmeVol"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(760, 130)
    holder.Position = UDim2.fromScale(0.5, 0.3)
    holder.AnchorPoint = Vector2.new(0.5, 0.5)
    holder.Parent = gui
    local scale = Theme.fit(holder, 0.8)
    local target = scale.Scale
    scale.Scale = target * 0.6
    TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = target }):Play()
    bannerText(holder, "Titre", "UN VOLEUR DANS TA BASE !", 70, 0, Theme.RED)
    bannerText(holder, "SousTitre", thiefName .. " vole un de tes jouets", 38, 76, Theme.WHITE)
    task.delay(4, function()
        if holder.Parent then
            holder:Destroy()
        end
    end)
end

-- Fleche au bord de l'ecran vers le coffre pille.
local function pointTo(target: Vector3): ()
    local old = gui:FindFirstChild("FlecheVol")
    if old then
        old:Destroy()
    end
    local arrow = Instance.new("ImageLabel")
    arrow.Name = "FlecheVol"
    arrow.BackgroundTransparency = 1
    arrow.Size = UDim2.fromOffset(84, 84)
    arrow.AnchorPoint = Vector2.new(0.5, 0.5)
    arrow.ImageColor3 = Theme.RED
    arrow.ScaleType = Enum.ScaleType.Fit
    arrow.Parent = gui
    arrow.Image = Assets.fleche or ""
    local untilTime = os.clock() + ALERT_SECONDS
    local connection: RBXScriptConnection? = nil
    connection = RunService.RenderStepped:Connect(function()
        if os.clock() > untilTime or arrow.Parent == nil then
            if connection then
                connection:Disconnect()
            end
            arrow:Destroy()
            return
        end
        local camera = Workspace.CurrentCamera
        local viewport = camera.ViewportSize
        local point, onScreen = camera:WorldToViewportPoint(target)
        local center = viewport / 2
        local direction = Vector2.new(point.X, point.Y) - center
        if point.Z < 0 then
            direction = -direction
        end
        if direction.Magnitude < 1 then
            direction = Vector2.new(0, -1)
        end
        local margin = 90
        local position: Vector2
        if onScreen and point.Z > 0 then
            position = Vector2.new(
                math.clamp(point.X, margin, viewport.X - margin),
                math.clamp(point.Y - 70, margin, viewport.Y - margin)
            )
            arrow.Rotation = 90
        else
            local unit = direction.Unit
            local radius = math.min(center.X, center.Y) - margin
            position = center + unit * radius
            arrow.Rotation = math.deg(math.atan2(unit.Y, unit.X))
        end
        arrow.Position = UDim2.fromOffset(position.X, position.Y)
    end)
end

local function onNotice(kind: string, a: any, b: any): ()
    if kind == "robbed" then
        Sfx.play("alarm")
        alarmBanner(if typeof(a) == "string" then a else "Quelqu'un")
        if typeof(b) == "Vector3" then
            pointTo(b)
        end
    elseif kind == "stealing" then
        Theme.toast(gui, "Jouet volé ! Ramène-le vite dans ta base", Theme.PINK)
    elseif kind == "success" then
        Sfx.play("fanfare")
        Theme.toast(gui, string.format("Vol réussi ! +%d XP", if typeof(a) == "number" then a else 0), Theme.GREEN)
    elseif kind == "dropped" then
        Theme.toast(gui, "Le jouet volé est retourné chez son propriétaire", Theme.YELLOW)
    elseif kind == "returned" then
        Theme.toast(gui, "Ton jouet est revenu dans ton coffre !", Theme.GREEN)
    elseif kind == "lost" then
        Theme.toast(gui, (if typeof(a) == "string" then a else "Le voleur") .. " a gardé ton jouet...", Theme.RED)
    elseif kind == "refused" then
        Sfx.play("refuse")
        Theme.toast(gui, if typeof(a) == "string" then a else "Impossible", Theme.YELLOW)
    elseif kind == "notice" then
        Theme.toast(gui, if typeof(a) == "string" then a else "", Theme.BLUE)
    end
end

-- Cadenas dessine en formes arrondies (anse + corps + trou de serrure).
local function padlock(parent: Instance, color: Color3): ()
    local shackle = Instance.new("Frame")
    shackle.Name = "Anse"
    shackle.BackgroundTransparency = 1
    shackle.Size = UDim2.fromScale(0.38, 0.38)
    shackle.Position = UDim2.fromScale(0.5, 0.36)
    shackle.AnchorPoint = Vector2.new(0.5, 0.5)
    shackle.Parent = parent
    Theme.corner(shackle, 999)
    Theme.stroke(shackle, 6, color)
    local body = Instance.new("Frame")
    body.Name = "Corps"
    body.BackgroundColor3 = color
    body.BorderSizePixel = 0
    body.Size = UDim2.fromScale(0.52, 0.36)
    body.Position = UDim2.fromScale(0.5, 0.62)
    body.AnchorPoint = Vector2.new(0.5, 0.5)
    body.Parent = parent
    Theme.corner(body, 8)
    local hole = Instance.new("Frame")
    hole.Name = "Serrure"
    hole.BackgroundColor3 = Theme.NAVY_DARK
    hole.BorderSizePixel = 0
    hole.Size = UDim2.fromScale(0.18, 0.4)
    hole.Position = UDim2.fromScale(0.5, 0.5)
    hole.AnchorPoint = Vector2.new(0.5, 0.5)
    hole.Parent = body
    Theme.corner(hole, 4)
end

local function ownBase(): BasePart?
    for _, base in CollectionService:GetTagged(BASE_TAG) do
        if
            base:IsA("BasePart")
            and base:IsDescendantOf(Workspace)
            and base:GetAttribute("OwnerUserId") == player.UserId
        then
            return base
        end
    end
    return nil
end

local function buildLockButton(): ()
    local holder = Instance.new("Frame")
    holder.Name = "Verrou"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(130, 150)
    holder.Position = UDim2.new(1, -14, 0.56, 0)
    holder.AnchorPoint = Vector2.new(1, 0.5)
    holder.Visible = false
    holder.Parent = gui
    Theme.fit(holder, Theme.HUD_FACTOR)

    local button = Instance.new("TextButton")
    button.Name = "Bouton"
    button.Text = ""
    button.AutoButtonColor = true
    button.BackgroundColor3 = Theme.NAVY
    button.Size = UDim2.fromOffset(100, 100)
    button.Position = UDim2.fromScale(0.5, 0)
    button.AnchorPoint = Vector2.new(0.5, 0)
    button.Parent = holder
    Theme.corner(button, 50)
    local ring = Theme.stroke(button, 4, Theme.PINK)
    padlock(button, Theme.YELLOW)

    local label = Theme.text(
        holder,
        "Texte",
        "Verrouiller",
        UDim2.new(1, 0, 0, 34),
        UDim2.new(0.5, 0, 0, 108),
        Theme.WHITE,
        Vector2.new(0.5, 0)
    )

    button.Activated:Connect(function()
        Sfx.play("click")
        local remote = Remotes.Get("LockBase") :: RemoteEvent
        remote:FireServer()
    end)

    task.spawn(function()
        while holder.Parent do
            task.wait(0.25)
            local character = player.Character
            local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
            local base = ownBase()
            local menus = player:GetAttribute("MenusOuverts")
            local inMenu = (typeof(menus) == "number" and menus > 0) or player:GetAttribute("VueCoffre") == true
            holder.Visible = not inMenu
                and base ~= nil
                and root ~= nil
                and root:IsA("BasePart")
                and Zone.Contains(base, root.Position)
            local now = Workspace:GetServerTimeNow()
            local lockUntil = player:GetAttribute("BaseLockUntil")
            local readyAt = player:GetAttribute("BaseLockReadyAt")
            if typeof(lockUntil) == "number" and lockUntil > now then
                label.Text = string.format("%d s", math.ceil(lockUntil - now))
                label.TextColor3 = Theme.PINK
                ring.Color = Theme.PINK
                button.BackgroundColor3 = Color3.fromRGB(120, 50, 100)
            elseif typeof(readyAt) == "number" and readyAt > now then
                local left = math.ceil(readyAt - now)
                label.Text = string.format("%d:%02d", left // 60, left % 60)
                label.TextColor3 = Theme.SOFT_TEXT
                ring.Color = Theme.GREY
                button.BackgroundColor3 = Theme.NAVY_DARK
            else
                label.Text = "Verrouiller"
                label.TextColor3 = Theme.WHITE
                ring.Color = Theme.YELLOW
                button.BackgroundColor3 = Theme.NAVY
            end
        end
    end)
end

function StealController:Init(): () end

function StealController:Start(): ()
    gui = Instance.new("ScreenGui")
    gui.Name = "Vol"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 7
    gui.Parent = player:WaitForChild("PlayerGui")

    local remote = Remotes.Get("StealNotice") :: RemoteEvent
    remote.OnClientEvent:Connect(onNotice)

    for _, descendant in Workspace:GetDescendants() do
        filterPrompt(descendant)
    end
    Workspace.DescendantAdded:Connect(filterPrompt)

    buildLockButton()
end

return StealController
