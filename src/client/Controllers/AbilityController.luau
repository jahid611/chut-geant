--!strict

--[[
    AbilityController
    Barre de pouvoirs collee en bas au centre (remontee au-dessus de la carte du jouet porte et de l'aide
    « G : poser / F : lancer » quand on porte quelque chose) : une case ronde par pouvoir possede (attributs
    Owned_<id>, Shared/Abilities pour l'ordre, les touches et les couleurs), avec la touche et le nom court.
    - Effet ACTIF (<Id>Until) : remplissage de la couleur du pouvoir qui se vide et secondes restantes en jaune ;
    - recharge (<Id>ReadyAt) : voile sombre qui descend et secondes en blanc.
    Touches : R Furie, T Tetine, Y Hochet, H Doudou, V Ventouse, C Cape, X Berceuse (+ manette et boutons tactiles).
    Le client envoie l'intention (remote UseAbility avec la direction et l'origine du rayon de visee : sous la souris
    au clavier, centre de l'ecran au tactile ou au clic sur la case), le serveur verifie tout.
    Effets locaux sur AbilityCast : halo autour du personnage ; pour la ventouse du joueur local, « Raté ! » ou
    « Trop lourd ! ».
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Assets = require(script.Parent.Parent.Ui.Assets)
local Theme = require(script.Parent.Parent.Ui.Theme)

local SLOT = 84
local GAP = 12

local AbilityController = {}

local player = Players.LocalPlayer

type Slot = { frame: Frame, veil: Frame, active: Frame, seconds: TextLabel, ring: UIStroke }

local function actionName(id: string): string
    return "Pouvoir_" .. id
end

local function keyLabel(key: Enum.KeyCode): string
    return key.Name
end

-- Rayon de visee : sous la souris au clavier/souris, sinon (tactile, manette, clic sur la case) centre de l'ecran.
local function aimRay(fromScreenCenter: boolean): Ray
    local camera = Workspace.CurrentCamera
    if not fromScreenCenter and UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
        local mouse = UserInputService:GetMouseLocation()
        return camera:ViewportPointToRay(mouse.X, mouse.Y)
    end
    local viewport = camera.ViewportSize
    return camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
end

local function use(id: string, fromScreenCenter: boolean): ()
    local remote = Remotes.Get("UseAbility") :: RemoteEvent
    local ray = aimRay(fromScreenCenter)
    remote:FireServer(id, ray.Direction, ray.Origin)
end

local function buildSlot(parent: Instance, ability: Abilities.Ability): Slot
    local frame = Instance.new("Frame")
    frame.Name = ability.id
    frame.Size = UDim2.fromOffset(SLOT, SLOT)
    frame.BackgroundColor3 = ability.color
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Theme.corner(frame, SLOT // 2)
    local ring = Theme.stroke(frame, 3, Theme.WHITE)

    local item = Catalog.Get(ability.id)
    local iconId = if item then Assets[item.icon] else nil
    if iconId and iconId ~= "rbxassetid://0" then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icone"
        icon.BackgroundTransparency = 1
        icon.Image = iconId
        icon.ScaleType = Enum.ScaleType.Fit
        icon.Size = UDim2.fromScale(0.78, 0.78)
        icon.Position = UDim2.fromScale(0.5, 0.46)
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Parent = frame
    else
        Theme.text(
            frame,
            "Nom",
            ability.short,
            UDim2.new(1, -10, 0.34, 0),
            UDim2.fromScale(0.5, 0.5),
            Theme.WHITE,
            Vector2.new(0.5, 0.5)
        )
    end

    -- Voile de recharge : descend du haut vers le bas au fil de la recharge (masque par l'arrondi du cadre).
    local clip = Instance.new("CanvasGroup")
    clip.Name = "Recharge"
    clip.BackgroundTransparency = 1
    clip.Size = UDim2.fromScale(1, 1)
    clip.Parent = frame
    Theme.corner(clip, SLOT // 2)
    local veil = Instance.new("Frame")
    veil.Name = "Voile"
    veil.BackgroundColor3 = Theme.NAVY_DARK
    veil.BackgroundTransparency = 0.35
    veil.BorderSizePixel = 0
    veil.AnchorPoint = Vector2.new(0, 1)
    veil.Position = UDim2.fromScale(0, 1)
    veil.Size = UDim2.fromScale(1, 0)
    veil.Parent = clip
    -- Effet actif : remplissage de la couleur du pouvoir, plus clair, qui se vide jusqu'a la fin de l'effet.
    local active = Instance.new("Frame")
    active.Name = "Actif"
    active.BackgroundColor3 = ability.color:Lerp(Color3.new(1, 1, 1), 0.35)
    active.BackgroundTransparency = 0.25
    active.BorderSizePixel = 0
    active.AnchorPoint = Vector2.new(0, 1)
    active.Position = UDim2.fromScale(0, 1)
    active.Size = UDim2.fromScale(1, 0)
    active.Parent = clip
    local seconds = Theme.text(
        frame,
        "Secondes",
        "",
        UDim2.fromScale(0.6, 0.4),
        UDim2.fromScale(0.5, 0.5),
        Theme.WHITE,
        Vector2.new(0.5, 0.5)
    )
    seconds.ZIndex = 3

    local keyBadge = Instance.new("Frame")
    keyBadge.Name = "Touche"
    keyBadge.BackgroundColor3 = Theme.NAVY
    keyBadge.Size = UDim2.fromOffset(30, 30)
    keyBadge.Position = UDim2.fromOffset(-4, -4)
    keyBadge.ZIndex = 4
    keyBadge.Parent = frame
    Theme.corner(keyBadge, 15)
    Theme.stroke(keyBadge, 2, Theme.WHITE)
    local keyText = Theme.text(
        keyBadge,
        "Texte",
        keyLabel(ability.key),
        UDim2.fromScale(0.7, 0.7),
        UDim2.fromScale(0.5, 0.5),
        Theme.WHITE,
        Vector2.new(0.5, 0.5)
    )
    keyText.ZIndex = 5

    local label = Theme.text(
        frame,
        "NomCourt",
        ability.short,
        UDim2.fromOffset(SLOT + 16, 22),
        UDim2.new(0.5, 0, 1, 4),
        Theme.WHITE,
        Vector2.new(0.5, 0)
    )
    label.ZIndex = 4
    return { frame = frame, veil = veil, active = active, seconds = seconds, ring = ring }
end

-- Texte bref qui monte et s'efface au-dessus de la barre (tir de ventouse rate, jouet trop lourd).
local function floatText(parent: Instance, message: string, color: Color3): ()
    local label = Theme.text(
        parent,
        "Retour",
        message,
        UDim2.fromOffset(420, 40),
        UDim2.new(0.5, 0, 0, -10),
        color,
        Vector2.new(0.5, 1)
    )
    label.ZIndex = 8
    TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad), {
        Position = UDim2.new(0.5, 0, 0, -60),
        TextTransparency = 1,
    }):Play()
    local stroke = label:FindFirstChildOfClass("UIStroke")
    if stroke then
        TweenService:Create(stroke, TweenInfo.new(1.1), { Transparency = 1 }):Play()
    end
    task.delay(1.2, function()
        label:Destroy()
    end)
end

-- Bref halo autour du personnage qui a utilise un pouvoir.
local function flash(userId: number, abilityId: string): ()
    local caster = Players:GetPlayerByUserId(userId)
    local character = if caster then caster.Character else nil
    local ability = Abilities.Get(abilityId)
    if character == nil or ability == nil then
        return
    end
    local highlight = Instance.new("Highlight")
    highlight.Name = "HaloPouvoir"
    highlight.FillColor = ability.color
    highlight.OutlineColor = ability.color
    highlight.FillTransparency = 0.5
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    highlight.Parent = character
    TweenService:Create(highlight, TweenInfo.new(0.6), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
    task.delay(0.7, function()
        highlight:Destroy()
    end)
end

function AbilityController:Init(): () end

function AbilityController:Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "Pouvoirs"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 6
    gui.Parent = player:WaitForChild("PlayerGui")
    local bar = Instance.new("Frame")
    bar.Name = "BarrePouvoirs"
    bar.BackgroundTransparency = 1
    bar.Size = UDim2.fromOffset(#Abilities.LIST * (SLOT + GAP), SLOT + 30)
    bar.Position = UDim2.new(0.5, 0, 1, -10)
    bar.AnchorPoint = Vector2.new(0.5, 1)
    bar.Parent = gui
    local barScale = Theme.fit(bar, Theme.HUD_FACTOR)
    -- Collee en bas ; quand on porte un jouet, au-dessus de la carte du jouet (HudController : 142 de haut a 18 du
    -- bas) et de l'aide « G : poser / F : lancer » (CarryController : 40 de haut, juste au-dessus de la carte), meme
    -- echelle HUD.
    local function placeBar(): ()
        local s = barScale.Scale
        local bottom = 10
        if player:GetAttribute("CarriedToyId") ~= nil then
            local cardTop = 18 + 142 * s + 34 -- + la ligne « + sac » au-dessus de la carte
            local hintTop = 18 + 142 * s + 6 + 40 * s -- l'aide est posee juste au-dessus de la carte
            bottom = math.max(cardTop, hintTop) + 10
        end
        bar.Position = UDim2.new(0.5, 0, 1, -math.floor(bottom))
        -- Haut de la barre en pixels depuis le bas de l'ecran : la barre d'armes (WeaponBarController) se pose juste
        -- au-dessus. Sans pouvoir possede la barre est vide et ne prend pas de place.
        local owned = 0
        for _, ability in Abilities.LIST do
            if player:GetAttribute("Owned_" .. ability.id) ~= nil then
                owned += 1
            end
        end
        local height = if owned > 0 then (SLOT + 30) * s else 0
        player:SetAttribute("BarrePouvoirsHaut", math.floor(bottom + height))
    end
    player.AttributeChanged:Connect(function(name: string)
        if string.sub(name, 1, 6) == "Owned_" then
            placeBar()
        end
    end)
    player:GetAttributeChangedSignal("CarriedToyId"):Connect(placeBar)
    barScale:GetPropertyChangedSignal("Scale"):Connect(placeBar)
    placeBar()
    -- Cachee pendant qu'un menu est ouvert (attribut MenusOuverts pose par Ui/Modal) : elle passait par-dessus.
    -- Et pendant la vue « Mes jouets » (attribut VueCoffre de Ui/ChestView) : elle chevauchait ses boutons.
    local function refreshMenus(): ()
        local open = player:GetAttribute("MenusOuverts")
        gui.Enabled = not (typeof(open) == "number" and open > 0) and player:GetAttribute("VueCoffre") ~= true
    end
    player:GetAttributeChangedSignal("MenusOuverts"):Connect(refreshMenus)
    player:GetAttributeChangedSignal("VueCoffre"):Connect(refreshMenus)
    refreshMenus()
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0, GAP)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = bar

    local slots: { [string]: Slot } = {}

    local function refresh(): ()
        for index, ability in Abilities.LIST do
            local owned = player:GetAttribute("Owned_" .. ability.id) ~= nil
            local slot = slots[ability.id]
            local action = actionName(ability.id)
            if owned and slot == nil then
                slot = buildSlot(bar, ability)
                slot.frame.LayoutOrder = index
                slots[ability.id] = slot
                local id = ability.id
                local keys: { Enum.KeyCode } = { ability.key }
                local pad = ability.gamepad
                if pad then
                    table.insert(keys, pad)
                end
                ContextActionService:BindAction(
                    action,
                    function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
                        if state ~= Enum.UserInputState.Begin then
                            return Enum.ContextActionResult.Pass
                        end
                        -- touche clavier : visee sous la souris ; bouton tactile ou manette : centre de l'ecran
                        use(id, false)
                        return Enum.ContextActionResult.Sink
                    end,
                    true,
                    table.unpack(keys)
                )
                ContextActionService:SetTitle(action, ability.short)
                local input = slot.frame
                input.Active = true
                local button = Instance.new("TextButton")
                button.Name = "Clic"
                button.Text = ""
                button.BackgroundTransparency = 1
                button.Size = UDim2.fromScale(1, 1)
                button.ZIndex = 6
                button.Parent = input
                button.Activated:Connect(function()
                    -- la souris est sur la case : on vise le centre de l'ecran
                    use(id, true)
                end)
            elseif not owned and slot then
                slot.frame:Destroy()
                slots[ability.id] = nil
                ContextActionService:UnbindAction(action)
            end
        end
    end
    for _, ability in Abilities.LIST do
        player:GetAttributeChangedSignal("Owned_" .. ability.id):Connect(refresh)
    end
    refresh()

    local cast = Remotes.Get("AbilityCast") :: RemoteEvent
    cast.OnClientEvent:Connect(function(abilityId: any, userId: any, _position: any, result: any)
        if typeof(abilityId) ~= "string" or typeof(userId) ~= "number" then
            return
        end
        if userId == player.UserId and abilityId == "SuctionGun" and typeof(result) == "string" then
            if result == "miss" then
                floatText(bar, "Raté !", Theme.RED)
                return
            elseif result == "heavy" then
                floatText(bar, "Trop lourd ! Améliore ta ventouse", Theme.RED)
                return
            elseif result == "full" then
                floatText(bar, "Tes mains sont pleines", Theme.YELLOW)
                return
            end
        end
        flash(userId, abilityId)
    end)

    task.spawn(function()
        while gui.Parent do
            local now = Workspace:GetServerTimeNow()
            for id, slot in slots do
                local ability = Abilities.Get(id)
                if ability == nil then
                    continue
                end
                local readyAt = player:GetAttribute(id .. "ReadyAt")
                local untilTime = player:GetAttribute(id .. "Until")
                local activeLeft = if typeof(untilTime) == "number" then untilTime - now else 0
                if activeLeft > 0 then
                    -- effet en cours : temps restant en temps reel, anneau jaune qui pulse
                    slot.ring.Color = Theme.YELLOW
                    slot.ring.Thickness = 4 + math.abs(math.sin(now * 6)) * 2
                    slot.active.Size =
                        UDim2.fromScale(1, math.clamp(activeLeft / math.max(ability.duration, 0.1), 0, 1))
                    slot.veil.Size = UDim2.fromScale(1, 0)
                    slot.seconds.Text = if activeLeft < 10
                        then string.format("%.1f", activeLeft)
                        else string.format("%d", math.ceil(activeLeft))
                    slot.seconds.TextColor3 = Theme.YELLOW
                elseif typeof(readyAt) == "number" and readyAt > now then
                    local left = readyAt - now
                    local total = if left <= Abilities.SUCTION_MISS_COOLDOWN + 0.05 and id == "SuctionGun"
                        then Abilities.SUCTION_MISS_COOLDOWN
                        else ability.cooldown
                    slot.ring.Color = Theme.WHITE
                    slot.ring.Thickness = 3
                    slot.active.Size = UDim2.fromScale(1, 0)
                    slot.veil.Size = UDim2.fromScale(1, math.clamp(left / math.max(total, 1), 0, 1))
                    slot.seconds.Text = string.format("%d", math.ceil(left))
                    slot.seconds.TextColor3 = Theme.WHITE
                else
                    slot.ring.Color = Theme.WHITE
                    slot.ring.Thickness = 3
                    slot.active.Size = UDim2.fromScale(1, 0)
                    slot.veil.Size = UDim2.fromScale(1, 0)
                    slot.seconds.Text = ""
                end
            end
            task.wait(0.1)
        end
    end)
end

return AbilityController
