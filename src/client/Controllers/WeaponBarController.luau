--!strict

--[[
    WeaponBarController
    Barre d'armes juste au-dessus de la barre de pouvoirs (demande utilisateur du 15/09 : la barre d'outils Roblox
    chevauchait les pouvoirs, et on devait passer par la boutique pour changer d'arme).

    - La barre d'outils Roblox par defaut est desactivee (CoreGui Backpack).
    - Une case ronde par arme possedee (attributs Owned_<id>, articles Catalog kind "weapon") : icone du catalogue,
      sinon apercu 3D (ReplicatedStorage.ApercusBoutique.<id>), sinon pastille avec l'initiale ; chiffre de touche.
    - Clic, tap ou touche 1 a 9 : equipe l'arme tout de suite (remote EquipCosmetic, slot "weapon") ; recliquer
      l'arme equipee la range. Touche Q : mains vides sans desequiper (l'outil retourne dans le sac).
    - L'arme equipee est mise en avant (plus grande, anneau jaune). Un outil d'arme qui arrive dans le sac est mis en
      main automatiquement, sauf si le joueur porte un jouet.
    - Position : juste au-dessus de la barre de pouvoirs (attribut joueur BarrePouvoirsHaut pose par
      AbilityController, qui remonte quand on porte un jouet). Cachee pendant les menus et la vue coffre.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Assets = require(script.Parent.Parent.Ui.Assets)
local Theme = require(script.Parent.Parent.Ui.Theme)

local SLOT = 70
local SLOT_EQUIPPED = 80
local GAP = 10
local MAX_KEYS = 9
local EMPTY_HANDS_ACTION = "ArmeMainsVides"
local KEY_CODES = {
    Enum.KeyCode.One,
    Enum.KeyCode.Two,
    Enum.KeyCode.Three,
    Enum.KeyCode.Four,
    Enum.KeyCode.Five,
    Enum.KeyCode.Six,
    Enum.KeyCode.Seven,
    Enum.KeyCode.Eight,
    Enum.KeyCode.Nine,
}
local PALETTE = { Theme.PINK, Theme.BLUE, Theme.MINT, Theme.YELLOW, Color3.fromRGB(190, 140, 255) }

local WeaponBarController = {}

local player = Players.LocalPlayer

type Slot = { frame: Frame, stroke: UIStroke, scale: UIScale, id: string }

local function disableCoreBackpack(): ()
    task.spawn(function()
        for _ = 1, 20 do
            local ok = pcall(function()
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
            end)
            if ok then
                return
            end
            task.wait(0.5)
        end
    end)
end

local function ownedWeapons(): { Catalog.Item }
    local list: { Catalog.Item } = {}
    for _, item in Catalog.All() do
        if (item.kind :: string) == "weapon" and player:GetAttribute("Owned_" .. item.id) ~= nil then
            table.insert(list, item)
        end
    end
    return list
end

-- Apercu 3D du modele dans la case (copie legere preparee par le serveur dans ReplicatedStorage).
local function preview(parent: GuiObject, id: string): boolean
    local folder = ReplicatedStorage:FindFirstChild("ApercusBoutique")
    local model = if folder then folder:FindFirstChild(id) else nil
    if model == nil or not (model:IsA("Model") or model:IsA("Tool")) then
        return false
    end
    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "Apercu"
    viewport.BackgroundTransparency = 1
    viewport.Size = UDim2.fromScale(0.86, 0.86)
    viewport.Position = UDim2.fromScale(0.5, 0.5)
    viewport.AnchorPoint = Vector2.new(0.5, 0.5)
    viewport.Ambient = Color3.fromRGB(200, 200, 215)
    viewport.LightColor = Color3.fromRGB(255, 245, 235)
    viewport.Parent = parent
    local clone = model:Clone()
    clone.Parent = viewport
    local center, size
    if clone:IsA("Model") then
        center, size = clone:GetBoundingBox()
    else
        local parts: { BasePart } = {}
        for _, d in clone:GetDescendants() do
            if d:IsA("BasePart") then
                table.insert(parts, d)
            end
        end
        local first: BasePart? = parts[1]
        if first == nil then
            viewport:Destroy()
            return false
        end
        center, size = first.CFrame, first.Size
        for _, part in parts do
            size =
                Vector3.new(math.max(size.X, part.Size.X), math.max(size.Y, part.Size.Y), math.max(size.Z, part.Size.Z))
        end
    end
    local radius = math.max(size.X, size.Y, size.Z) / 2
    local camera = Instance.new("Camera")
    camera.FieldOfView = 40
    local eye = center.Position + Vector3.new(1, 0.7, 1).Unit * radius * 3.2
    camera.CFrame = CFrame.lookAt(eye, center.Position)
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    return true
end

local function equip(id: string): ()
    local remote = Remotes.Get("EquipCosmetic") :: RemoteFunction
    task.spawn(function()
        local ok, success, message = pcall(function()
            return remote:InvokeServer(id)
        end)
        if ok and success ~= true and typeof(message) == "string" then
            local gui = player:FindFirstChild("PlayerGui")
            local screen = if gui then gui:FindFirstChild("BarreArmes") else nil
            if screen then
                Theme.toast(screen, message, Theme.RED)
            end
        end
    end)
end

function WeaponBarController:Init(): () end

function WeaponBarController:Start(): ()
    disableCoreBackpack()

    local gui = Instance.new("ScreenGui")
    gui.Name = "BarreArmes"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 6
    gui.Parent = player:WaitForChild("PlayerGui")

    local bar = Instance.new("Frame")
    bar.Name = "Armes"
    bar.BackgroundTransparency = 1
    bar.Size = UDim2.fromOffset(MAX_KEYS * (SLOT_EQUIPPED + GAP), SLOT_EQUIPPED + 8)
    bar.AnchorPoint = Vector2.new(0.5, 1)
    bar.Parent = gui
    local barScale = Theme.fit(bar, Theme.HUD_FACTOR)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    layout.Padding = UDim.new(0, GAP)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = bar

    local function place(): ()
        local top = player:GetAttribute("BarrePouvoirsHaut")
        local bottom = (if typeof(top) == "number" then top else 10) + 8
        bar.Position = UDim2.new(0.5, 0, 1, -math.floor(bottom))
    end
    player:GetAttributeChangedSignal("BarrePouvoirsHaut"):Connect(place)
    barScale:GetPropertyChangedSignal("Scale"):Connect(place)
    place()

    local function refreshVisible(): ()
        local open = player:GetAttribute("MenusOuverts")
        gui.Enabled = not (typeof(open) == "number" and open > 0) and player:GetAttribute("VueCoffre") ~= true
    end
    player:GetAttributeChangedSignal("MenusOuverts"):Connect(refreshVisible)
    player:GetAttributeChangedSignal("VueCoffre"):Connect(refreshVisible)
    refreshVisible()

    local slots: { Slot } = {}
    local boundKeys = 0

    local function highlight(): ()
        local equipped = player:GetAttribute("Equipped_weapon")
        for _, slot in slots do
            local on = slot.id == equipped
            local goal = if on then SLOT_EQUIPPED / SLOT else 1
            TweenService:Create(slot.scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = goal }):Play()
            slot.stroke.Color = if on then Theme.YELLOW else Theme.WHITE
            slot.stroke.Thickness = if on then 4 else 2
            slot.frame.BackgroundTransparency = if on then 0 else 0.25
        end
    end

    local function onKey(name: string, state: Enum.UserInputState): Enum.ContextActionResult
        if state ~= Enum.UserInputState.Begin then
            return Enum.ContextActionResult.Pass
        end
        local index = tonumber(string.match(name, "%d+$"))
        local slot = if index then slots[index] else nil
        if slot then
            equip(slot.id)
            return Enum.ContextActionResult.Sink
        end
        return Enum.ContextActionResult.Pass
    end

    local function rebuild(): ()
        for _, slot in slots do
            slot.frame:Destroy()
        end
        table.clear(slots)
        for i = 1, boundKeys do
            ContextActionService:UnbindAction("ChoisirArme" .. i)
        end
        boundKeys = 0

        for index, item in ownedWeapons() do
            local frame = Instance.new("Frame")
            frame.Name = item.id
            frame.LayoutOrder = index
            frame.Size = UDim2.fromOffset(SLOT, SLOT)
            frame.BackgroundColor3 = Theme.NAVY
            frame.Parent = bar
            Theme.corner(frame, SLOT // 2)
            local stroke = Theme.stroke(frame, 2, Theme.WHITE)
            local scale = Instance.new("UIScale")
            scale.Parent = frame

            local iconId = Assets[item.icon]
            if iconId and iconId ~= "rbxassetid://0" then
                local image = Instance.new("ImageLabel")
                image.Name = "Icone"
                image.BackgroundTransparency = 1
                image.Image = iconId
                image.ScaleType = Enum.ScaleType.Fit
                image.Size = UDim2.fromScale(0.78, 0.78)
                image.Position = UDim2.fromScale(0.5, 0.5)
                image.AnchorPoint = Vector2.new(0.5, 0.5)
                image.Parent = frame
            elseif not preview(frame, item.id) then
                frame.BackgroundColor3 = PALETTE[(index - 1) % #PALETTE + 1]
                Theme.text(
                    frame,
                    "Initiale",
                    string.sub(item.name, 1, 1),
                    UDim2.fromScale(0.6, 0.6),
                    UDim2.fromScale(0.5, 0.5),
                    Theme.WHITE,
                    Vector2.new(0.5, 0.5)
                )
            end

            if index <= MAX_KEYS then
                local badge = Instance.new("Frame")
                badge.Name = "Touche"
                badge.BackgroundColor3 = Theme.NAVY_DARK
                badge.Size = UDim2.fromOffset(24, 24)
                badge.Position = UDim2.fromOffset(-2, -2)
                badge.ZIndex = 4
                badge.Parent = frame
                Theme.corner(badge, 12)
                Theme.stroke(badge, 2, Theme.WHITE)
                local keyText = Theme.text(
                    badge,
                    "Texte",
                    tostring(index),
                    UDim2.fromScale(0.72, 0.72),
                    UDim2.fromScale(0.5, 0.5),
                    Theme.WHITE,
                    Vector2.new(0.5, 0.5)
                )
                keyText.ZIndex = 5
                ContextActionService:BindAction("ChoisirArme" .. index, onKey, false, KEY_CODES[index])
                boundKeys = index
            end

            local button = Instance.new("TextButton")
            button.Name = "Clic"
            button.BackgroundTransparency = 1
            button.Text = ""
            button.Size = UDim2.fromScale(1, 1)
            button.ZIndex = 6
            button.Parent = frame
            local id = item.id
            button.Activated:Connect(function()
                equip(id)
            end)

            table.insert(slots, { frame = frame, stroke = stroke, scale = scale, id = item.id })
        end
        highlight()
    end

    player.AttributeChanged:Connect(function(name: string)
        if string.sub(name, 1, 6) == "Owned_" then
            local item = Catalog.Get(string.sub(name, 7))
            if item and (item.kind :: string) == "weapon" then
                rebuild()
            end
        elseif name == "Equipped_weapon" then
            highlight()
        end
    end)
    rebuild()

    -- Apercus prepares par le serveur apres le demarrage : on reconstruit quand ils arrivent.
    task.spawn(function()
        local folder = ReplicatedStorage:WaitForChild("ApercusBoutique", 60)
        if folder then
            rebuild()
            folder.ChildAdded:Connect(function()
                task.defer(rebuild)
            end)
        end
    end)

    -- Q : mains vides (l'outil retourne dans le sac, l'arme reste equipee).
    ContextActionService:BindAction(
        EMPTY_HANDS_ACTION,
        function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
            if state ~= Enum.UserInputState.Begin then
                return Enum.ContextActionResult.Pass
            end
            local character = player.Character
            local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
            if humanoid and character and character:FindFirstChildOfClass("Tool") then
                humanoid:UnequipTools()
                return Enum.ContextActionResult.Sink
            end
            return Enum.ContextActionResult.Pass
        end,
        false,
        Enum.KeyCode.Q
    )

    -- Outil d'arme neuf (donne par WeaponService) : mis en main tout de suite, une seule fois par outil pour ne pas
    -- le reprendre quand le joueur le range lui-meme.
    local seen: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
    local function watchBackpack(backpack: Instance): ()
        backpack.ChildAdded:Connect(function(child: Instance)
            if not child:IsA("Tool") or seen[child] then
                return
            end
            seen[child] = true
            task.defer(function()
                local character = player.Character
                local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
                if humanoid and child.Parent == backpack and player:GetAttribute("CarriedToyId") == nil then
                    humanoid:EquipTool(child)
                end
            end)
        end)
    end
    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then
        watchBackpack(backpack)
    end
    player.ChildAdded:Connect(function(child: Instance)
        if child:IsA("Backpack") then
            watchBackpack(child)
        end
    end)
end

return WeaponBarController
