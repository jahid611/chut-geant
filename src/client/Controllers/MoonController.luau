--!strict

--[[
    MoonController
    Annonces de progression cote joueur :
    - « Pleine lune » (MoonService) : grand texte flottant a l'annonce, lune du ciel plus grosse et une legere teinte
      bleutee ; en haut a droite, sous le badge d'etat du bebe, une icone de pleine lune ronde qui SE VIDE en temps
      reel (la partie lumineuse descend jusqu'a la fin), halo qui pulse et temps restant court dessous (15/09 : la
      carte « PLEINE LUNE 2:41 » etait moche) ; tout est remis a la fin ;
    - decouvertes de la collection (remote CollectionState) : message pour chaque jouet ou mutation trouve et grand
      texte quand un set est complet.
    Evenement suivi par le remote MoonEvent et l'attribut MoonUntil du workspace (arrivee pendant la lune).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Assets = require(script.Parent.Parent.Ui.Assets)
local Theme = require(script.Parent.Parent.Ui.Theme)

-- Icone de pleine lune (px avant l'echelle HUD) et badge d'etat du bebe de HudController, sous lequel elle se place
-- (250 x 86, a 14 px du haut et du bord droit, meme echelle Theme.HUD_FACTOR).
local ICON = 92
local BABY_BADGE = Vector2.new(250, 86)
local HUD_MARGIN = 14

local MOON_COLOR = Color3.fromRGB(200, 215, 255)
local MOON_SIZE = 26
local TINT_NAME = "TeintePleineLune"

local MoonController = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local badge: Frame? = nil
local moonToken = 0
local savedMoonSize: number? = nil

-- Grand texte flottant au centre haut, qui disparait tout seul (meme style que les bandeaux d'evenements).
local function announce(title: string, subtitle: string, color: Color3): ()
    local screen = gui
    if screen == nil then
        return
    end
    local holder = Instance.new("Frame")
    holder.Name = "AnnonceProgression"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(760, 140)
    holder.Position = UDim2.fromScale(0.5, 0.3)
    holder.AnchorPoint = Vector2.new(0.5, 0.5)
    holder.Parent = screen
    local scale = Theme.fit(holder, 0.8)
    local target = scale.Scale
    scale.Scale = target * 0.6
    TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = target }):Play()
    local titleLabel =
        Theme.text(holder, "Titre", title, UDim2.new(1, 0, 0, 72), UDim2.fromScale(0.5, 0), color, Vector2.new(0.5, 0))
    local stroke = titleLabel:FindFirstChildOfClass("UIStroke")
    if stroke then
        stroke.Thickness = 4
    end
    Theme.text(
        holder,
        "SousTitre",
        subtitle,
        UDim2.new(0.9, 0, 0, 34),
        UDim2.new(0.5, 0, 0, 78),
        Theme.WHITE,
        Vector2.new(0.5, 0)
    )
    task.delay(4, function()
        if holder.Parent then
            holder:Destroy()
        end
    end)
end

local function setMoonLook(on: boolean): ()
    local sky = Lighting:FindFirstChildOfClass("Sky")
    local tint = Lighting:FindFirstChild(TINT_NAME)
    if on then
        if sky and savedMoonSize == nil then
            savedMoonSize = sky.MoonAngularSize
            TweenService:Create(sky, TweenInfo.new(3), { MoonAngularSize = MOON_SIZE }):Play()
        end
        if tint == nil then
            local effect = Instance.new("ColorCorrectionEffect")
            effect.Name = TINT_NAME
            effect.TintColor = Color3.new(1, 1, 1)
            effect.Parent = Lighting
            TweenService:Create(effect, TweenInfo.new(3), { TintColor = MOON_COLOR, Brightness = 0.03 }):Play()
        end
    else
        local size = savedMoonSize
        if sky and size then
            TweenService:Create(sky, TweenInfo.new(3), { MoonAngularSize = size }):Play()
        end
        savedMoonSize = nil
        if tint then
            tint:Destroy()
        end
    end
end

local function stopMoon(): ()
    moonToken += 1
    setMoonLook(false)
    local current = badge
    if current then
        current:Destroy()
        badge = nil
    end
end

local function startMoon(endsAt: number, fresh: boolean): ()
    local screen = gui
    if screen == nil or endsAt <= Workspace:GetServerTimeNow() then
        return
    end
    stopMoon()
    moonToken += 1
    local token = moonToken
    setMoonLook(true)
    if fresh then
        announce("PLEINE LUNE !", "Tétines x2 et jouets plus rares pendant 3 minutes", MOON_COLOR)
    end

    -- Cadre : halo + disque en haut, temps restant dessous.
    local width = ICON + 28
    local holder = Instance.new("Frame")
    holder.Name = "LunePleine"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(width, width + 34)
    holder.AnchorPoint = Vector2.new(1, 0)
    holder.Parent = screen
    local scale = Theme.fit(holder, Theme.HUD_FACTOR)
    -- Centre sous le badge du bebe : l'echelle agit autour du point d'ancrage (coin haut droit), donc on recalcule la
    -- position avec l'echelle courante pour rester aligne et sous le badge a toutes les tailles d'ecran.
    local function place(): ()
        local s = scale.Scale
        local badgeCenter = HUD_MARGIN + BABY_BADGE.X / 2 * s
        holder.Position = UDim2.new(1, -(badgeCenter - width / 2 * s), 0, HUD_MARGIN + BABY_BADGE.Y * s + 10)
    end
    scale:GetPropertyChangedSignal("Scale"):Connect(place)
    place()

    local discCenter = UDim2.fromOffset(width / 2, width / 2)
    local halo = Instance.new("Frame")
    halo.Name = "Halo"
    halo.AnchorPoint = Vector2.new(0.5, 0.5)
    halo.Position = discCenter
    halo.Size = UDim2.fromOffset(ICON + 10, ICON + 10)
    halo.BackgroundColor3 = MOON_COLOR
    halo.BackgroundTransparency = 0.8
    halo.BorderSizePixel = 0
    halo.Parent = holder
    local haloCorner = Instance.new("UICorner")
    haloCorner.CornerRadius = UDim.new(0.5, 0)
    haloCorner.Parent = halo
    local haloStroke = Instance.new("UIStroke")
    haloStroke.Color = MOON_COLOR
    haloStroke.Thickness = 4
    haloStroke.Transparency = 0.45
    haloStroke.Parent = halo
    local pulse = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    TweenService:Create(halo, pulse, { Size = UDim2.fromOffset(ICON + 26, ICON + 26), BackgroundTransparency = 0.93 })
        :Play()
    TweenService:Create(haloStroke, pulse, { Transparency = 0.85 }):Play()

    -- Disque rond (CanvasGroup arrondi) : lune eteinte au fond, lune allumee dans un cadre qui se reduit par le haut.
    local disc = Instance.new("CanvasGroup")
    disc.Name = "Disque"
    disc.AnchorPoint = Vector2.new(0.5, 0.5)
    disc.Position = discCenter
    disc.Size = UDim2.fromOffset(ICON, ICON)
    disc.BackgroundColor3 = Theme.NAVY_DARK
    disc.BackgroundTransparency = 0
    disc.BorderSizePixel = 0
    disc.Parent = holder
    local discCorner = Instance.new("UICorner")
    discCorner.CornerRadius = UDim.new(0.5, 0)
    discCorner.Parent = disc
    local moonImage = Assets.menuPleineLune
    local dim = Instance.new("ImageLabel")
    dim.Name = "LuneEteinte"
    dim.BackgroundTransparency = 1
    dim.Image = moonImage
    dim.ImageColor3 = Color3.fromRGB(70, 82, 125)
    dim.ImageTransparency = 0.3
    dim.ScaleType = Enum.ScaleType.Fit
    dim.Size = UDim2.fromScale(1, 1)
    dim.Parent = disc
    local level = Instance.new("Frame")
    level.Name = "Niveau"
    level.BackgroundTransparency = 1
    level.AnchorPoint = Vector2.new(0.5, 1)
    level.Position = UDim2.fromScale(0.5, 1)
    level.Size = UDim2.fromScale(1, 1)
    level.ClipsDescendants = true
    level.Parent = disc
    local lit = Instance.new("ImageLabel")
    lit.Name = "LuneAllumee"
    lit.BackgroundTransparency = 1
    lit.Image = moonImage
    lit.ScaleType = Enum.ScaleType.Fit
    lit.AnchorPoint = Vector2.new(0.5, 1)
    lit.Position = UDim2.fromScale(0.5, 1)
    lit.Size = UDim2.fromOffset(ICON, ICON)
    lit.Parent = level
    local rim = Instance.new("UIStroke")
    rim.Color = MOON_COLOR
    rim.Thickness = 3
    rim.Transparency = 0.2
    rim.Parent = disc

    local label = Theme.text(
        holder,
        "Temps",
        "",
        UDim2.fromOffset(width, 30),
        UDim2.fromOffset(width / 2, width + 2),
        MOON_COLOR,
        Vector2.new(0.5, 0)
    )
    badge = holder

    local duration = Progression.MOON_DURATION_SECONDS
    task.spawn(function()
        while token == moonToken do
            local left = endsAt - Workspace:GetServerTimeNow()
            if left <= 0 then
                stopMoon()
                break
            end
            level.Size = UDim2.fromScale(1, math.clamp(left / duration, 0, 1))
            label.Text = string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
            task.wait(0.1)
        end
    end)
end

function MoonController:Init(): () end

function MoonController:Start(): ()
    local screen = Instance.new("ScreenGui")
    screen.Name = "Progression"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 7
    screen.Parent = player:WaitForChild("PlayerGui")
    gui = screen

    local moonEvent = Remotes.Get("MoonEvent") :: RemoteEvent
    moonEvent.OnClientEvent:Connect(function(phase: string, endsAt: number)
        if phase == "start" then
            startMoon(endsAt, true)
        else
            stopMoon()
        end
    end)
    local current = Workspace:GetAttribute("MoonUntil")
    if typeof(current) == "number" then
        startMoon(current, false)
    end

    local collection = Remotes.Get("CollectionState") :: RemoteEvent
    collection.OnClientEvent:Connect(function(state: any)
        if typeof(state) ~= "table" then
            return
        end
        local items = if typeof(state.items) == "table" then state.items else {}
        for i, item in items do
            task.delay((i - 1) * 2.6, function()
                Theme.toast(
                    screen,
                    string.format(
                        "Nouveau dans ta collection : %s (+%s tétines)",
                        tostring(item.name),
                        Theme.formatNumber(if typeof(item.reward) == "number" then item.reward else 0)
                    ),
                    Theme.MINT
                )
            end)
        end
        local sets = if typeof(state.sets) == "table" then state.sets else {}
        if #sets > 0 then
            task.delay(#items * 2.6, function()
                announce("SET COMPLET !", "Bonus de revenu permanent débloqué", Theme.YELLOW)
            end)
        end
    end)
end

return MoonController
