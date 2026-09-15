--!strict

--[[
    HudController
    Le HUD en jeu, d'apres la maquette validee (docs/mockups/higgsfield/hud.png) :
    - en haut a gauche, les tetines et le revenu par seconde ;
    - en haut au centre, la jauge « CHUT ! » (bruit de la chambre) et le bebe ;
    - en haut a droite, l'etat du bebe (dort, reveil, chasse) ;
    - en bas au centre, la carte du jouet porte (apercu 3D, rarete, poids) ;
    - en bas a droite, les boutons Mes jouets, Boutique et Reglages.
    Ouvre aussi « Coffre plein ! » quand le serveur refuse un depot, et affiche « ATTRAPÉ ! ».
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))

-- Chemins ecrits en entier : luau-lsp ne resout pas un require passe par une variable.
local ChestFull = require(script.Parent.Parent.Ui.ChestFull)
local ChestView = require(script.Parent.Parent.Ui.ChestView)
local Shop = require(script.Parent.Parent.Ui.Shop)
local Theme = require(script.Parent.Parent.Ui.Theme)

local SEGMENTS = 34

type BabyState = { text: string, color: Color3 }

local BABY_STATES: { [string]: BabyState } = {
    Sleeping = { text = "DORT", color = Theme.WHITE },
    Waking = { text = "RÉVEIL !", color = Theme.YELLOW },
    Hunting = { text = "CHASSE !", color = Theme.RED },
}

local HudController = {}

local function block(gui: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.BackgroundTransparency = 1
    frame.Size = size
    frame.Position = position
    frame.AnchorPoint = anchor
    frame.Parent = gui
    Theme.fit(frame, Theme.HUD_FACTOR)
    return frame
end

local function numberAttribute(player: Player, name: string): number
    local value = player:GetAttribute(name)
    return if typeof(value) == "number" then value else 0
end

function HudController:Init(): () end

function HudController:Start(): ()
    local player = Players.LocalPlayer
    local gui = Instance.new("ScreenGui")
    gui.Name = "HUD"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 5
    gui.Parent = player:WaitForChild("PlayerGui")

    -- Tetines
    -- Sous la barre de Roblox (logo et menu en haut a gauche, ~58 px) : a y = 14 ils recouvraient le debut du
    -- compteur (teste en jeu, l'interface ignore la marge de cette barre).
    local money = block(gui, "Tetines", UDim2.fromOffset(350, 108), UDim2.fromOffset(14, 62), Vector2.zero)
    Theme.panel(money, "Pilule", UDim2.fromOffset(288, 84), UDim2.fromOffset(54, 12), Vector2.zero)
    -- La tetine detouree remplit tout son cadre (l'ancienne decoupe avait des marges) : icone reduite et textes
    -- decales, sinon elle masquait le premier chiffre (« 12 450 » lu « 2 450 », teste en jeu).
    Theme.image(money, "Icone", "tetine", UDim2.fromOffset(92, 92), UDim2.fromOffset(4, 8), Vector2.zero).ZIndex = 2
    local cashLabel = Theme.text(
        money,
        "Montant",
        "0",
        UDim2.fromOffset(200, 48),
        UDim2.fromOffset(132, 18),
        Theme.WHITE,
        Vector2.zero
    )
    cashLabel.TextXAlignment = Enum.TextXAlignment.Left
    local incomeLabel = Theme.text(
        money,
        "Revenu",
        "+0 /s",
        UDim2.fromOffset(190, 26),
        UDim2.fromOffset(134, 64),
        Theme.MINT,
        Vector2.zero
    )
    incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
    local function updateMoney(): ()
        cashLabel.Text = Theme.formatNumber(numberAttribute(player, "Cash"))
        incomeLabel.Text = "+" .. Theme.formatNumber(numberAttribute(player, "Income")) .. " /s"
    end
    player:GetAttributeChangedSignal("Cash"):Connect(updateMoney)
    player:GetAttributeChangedSignal("Income"):Connect(updateMoney)
    updateMoney()

    -- Jauge CHUT !
    local noise = block(gui, "Bruit", UDim2.fromOffset(600, 146), UDim2.new(0.5, 0, 0, 4), Vector2.new(0.5, 0))
    local chut = Theme.text(
        noise,
        "Chut",
        "CHUT !",
        UDim2.fromOffset(240, 56),
        UDim2.new(0.5, -44, 0, 0),
        Theme.WHITE,
        Vector2.new(0.5, 0)
    )
    local bar = Theme.panel(noise, "Jauge", UDim2.fromOffset(500, 72), UDim2.fromOffset(18, 58), Vector2.zero)
    local segments: { Frame } = {}
    local innerLeft, innerWidth = 30, 386
    for i = 1, SEGMENTS do
        local t = (i - 1) / (SEGMENTS - 1)
        local segment = Instance.new("Frame")
        segment.Name = "Segment" .. i
        segment.BorderSizePixel = 0
        local height = 0.28 + 0.5 * math.abs(math.sin(i * 0.62)) * (0.55 + 0.45 * t)
        segment.Size = UDim2.new(0, innerWidth / SEGMENTS - 3, height, 0)
        segment.AnchorPoint = Vector2.new(0, 0.5)
        segment.Position = UDim2.new(0, innerLeft + (i - 1) * innerWidth / SEGMENTS, 0.5, 0)
        segment.BackgroundColor3 = if t < 0.5
            then Theme.GREEN:Lerp(Theme.YELLOW, t * 2)
            else Theme.YELLOW:Lerp(Theme.RED, (t - 0.5) * 2)
        segment.Parent = bar
        Theme.corner(segment, 3)
        table.insert(segments, segment)
    end
    Theme.image(noise, "Bebe", "bebeDort", UDim2.fromOffset(108, 108), UDim2.fromOffset(468, 40), Vector2.zero).ZIndex =
        2
    local zzz =
        Theme.text(noise, "Zzz", "Zzz", UDim2.fromOffset(66, 34), UDim2.fromOffset(540, 24), Theme.BLUE, Vector2.zero)
    zzz.ZIndex = 3
    local function setNoise(value: number, max: number): ()
        local fraction = math.clamp(value / math.max(max, 1), 0, 1)
        for i, segment in segments do
            segment.BackgroundTransparency = if i / SEGMENTS <= fraction + 0.001 then 0 else 0.82
        end
    end
    setNoise(0, 100)

    -- Etat du bebe
    local state = block(gui, "EtatBebe", UDim2.fromOffset(250, 86), UDim2.new(1, -14, 0, 14), Vector2.new(1, 0))
    local statePanel = Theme.panel(state, "Pilule", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero)
    Theme.image(state, "Lune", "lune", UDim2.fromOffset(72, 72), UDim2.fromOffset(12, 7), Vector2.zero).ZIndex = 2
    local stateLabel = Theme.text(
        state,
        "Texte",
        "DORT",
        UDim2.fromOffset(148, 48),
        UDim2.fromOffset(90, 19),
        Theme.WHITE,
        Vector2.zero
    )
    local function setBabyState(name: string): ()
        local def = BABY_STATES[name] or BABY_STATES.Sleeping
        stateLabel.Text = def.text
        stateLabel.TextColor3 = def.color
        zzz.Visible = name == "Sleeping"
        chut.TextColor3 = if name == "Hunting" then Theme.RED else Theme.WHITE
        local stroke = statePanel:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = def.color
        end
    end
    setBabyState("Sleeping")

    -- Carte du jouet porte
    local card = block(gui, "JouetPorte", UDim2.fromOffset(440, 142), UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1))
    Theme.panel(card, "Carte", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero)
    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "Apercu"
    viewport.BackgroundTransparency = 1
    viewport.Size = UDim2.fromOffset(122, 122)
    viewport.Position = UDim2.fromOffset(12, 10)
    viewport.Ambient = Color3.fromRGB(210, 210, 220)
    viewport.LightColor = Color3.new(1, 1, 1)
    viewport.ZIndex = 2
    viewport.Parent = card
    local viewportCamera = Instance.new("Camera")
    viewportCamera.FieldOfView = 40
    viewportCamera.Parent = viewport
    viewport.CurrentCamera = viewportCamera
    local rarityTag = Theme.panel(card, "Rarete", UDim2.fromOffset(170, 36), UDim2.fromOffset(148, 14), Vector2.zero)
    local rarityLabel = Theme.text(
        rarityTag,
        "Texte",
        "",
        UDim2.new(1, -16, 1, -8),
        UDim2.fromScale(0.5, 0.5),
        Theme.WHITE,
        Vector2.new(0.5, 0.5)
    )
    local nameLabel =
        Theme.text(card, "Nom", "", UDim2.fromOffset(276, 42), UDim2.fromOffset(148, 54), Theme.WHITE, Vector2.zero)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    local weightLabel = Theme.text(
        card,
        "Poids",
        "",
        UDim2.fromOffset(276, 30),
        UDim2.fromOffset(148, 100),
        Theme.SOFT_TEXT,
        Vector2.zero
    )
    weightLabel.TextXAlignment = Enum.TextXAlignment.Left
    -- Sac a dos : 2e jouet leger porte dans le dos (attribut CarriedToyId2), rappele au-dessus de la carte.
    local backLabel =
        Theme.text(card, "Sac", "", UDim2.new(1, 0, 0, 28), UDim2.new(0.5, 0, 0, -4), Theme.MINT, Vector2.new(0.5, 1))
    backLabel.Visible = false
    card.Visible = false

    local spinning: Model? = nil
    RunService.RenderStepped:Connect(function(dt: number)
        local model = spinning
        if model and model.Parent then
            model:PivotTo(model:GetPivot() * CFrame.Angles(0, dt * 1.2, 0))
        end
    end)

    local function updatePreview(): ()
        for _, child in viewport:GetChildren() do
            if child:IsA("Model") then
                child:Destroy()
            end
        end
        spinning = nil
        local live = Workspace:FindFirstChild("ToysLive")
        if live == nil then
            return
        end
        for _, toy in live:GetChildren() do
            if toy:IsA("Model") and toy:GetAttribute("CarrierUserId") == player.UserId then
                toy.Archivable = true
                local copy = toy:Clone()
                for _, descendant in copy:GetDescendants() do
                    if descendant:IsA("ProximityPrompt") or descendant:IsA("WeldConstraint") then
                        descendant:Destroy()
                    end
                end
                copy:PivotTo(CFrame.new())
                copy.Parent = viewport
                local center, size = copy:GetBoundingBox()
                viewportCamera.CFrame = CFrame.lookAt(
                    center.Position + Vector3.new(0, size.Y * 0.25, size.Magnitude * 1.25),
                    center.Position
                )
                spinning = copy
                return
            end
        end
    end

    local function updateCarried(): ()
        local toyId = player:GetAttribute("CarriedToyId")
        local def = if typeof(toyId) == "string" then Toys.Get(toyId) else nil
        if def == nil then
            card.Visible = false
            spinning = nil
            return
        end
        local rarity = Theme.RARITY[def.rarity]
        rarityTag.BackgroundColor3 = if rarity then rarity.color else Theme.GREY
        rarityLabel.Text = if rarity then rarity.label else def.rarity
        local mutationId = player:GetAttribute("CarriedMutation")
        local mutation = if typeof(mutationId) == "string" then Toys.GetMutation(mutationId) else nil
        nameLabel.Text = def.displayName .. (if mutation then " " .. mutation.displayName else "")
        weightLabel.Text = if def.carriers > 1 then string.format("Lourd · %d porteurs", def.carriers) else "Léger"
        card.Visible = true
        updatePreview()
        -- le jouet soude au personnage peut arriver un instant apres l'attribut
        task.delay(0.4, function()
            if card.Visible and spinning == nil then
                updatePreview()
            end
        end)
    end
    player:GetAttributeChangedSignal("CarriedToyId"):Connect(updateCarried)
    updateCarried()

    local function updateBack(): ()
        local backId = player:GetAttribute("CarriedToyId2")
        local backDef = if typeof(backId) == "string" then Toys.Get(backId) else nil
        backLabel.Visible = backDef ~= nil
        if backDef then
            local mutationId = player:GetAttribute("CarriedMutation2")
            local mutation = if typeof(mutationId) == "string" then Toys.GetMutation(mutationId) else nil
            backLabel.Text = "+ sac : " .. backDef.displayName .. (if mutation then " " .. mutation.displayName else "")
        end
    end
    player:GetAttributeChangedSignal("CarriedToyId2"):Connect(updateBack)
    player:GetAttributeChangedSignal("CarriedMutation2"):Connect(updateBack)
    updateBack()

    -- Boutons
    local hudBlocks: { GuiObject } = { money, noise, state }
    local buttons = block(gui, "Boutons", UDim2.fromOffset(410, 158), UDim2.new(1, -10, 1, -10), Vector2.new(1, 1))
    table.insert(hudBlocks, buttons)

    local function setHudVisible(visible: boolean): ()
        for _, object in hudBlocks do
            object.Visible = visible
        end
        card.Visible = visible and player:GetAttribute("CarriedToyId") ~= nil
    end

    local function roundButton(name: string, key: string, label: string?, x: number, onClick: () -> ()): ()
        local button = Theme.roundImageButton(buttons, name, key, UDim2.fromOffset(118, 118), UDim2.fromOffset(x, 20))
        button.Activated:Connect(onClick)
        -- icones seules, sans texte dessous (retour utilisateur : on aurait dit un texte coupe)
        if label and false then
            Theme.text(
                buttons,
                name .. "Texte",
                label,
                -- 124 de large : a 150 « Mes jouets » et « Boutique » se touchaient (teste en jeu)
                UDim2.fromOffset(124, 30),
                UDim2.fromOffset(x + 59, 120),
                Theme.WHITE,
                Vector2.new(0.5, 0)
            )
        end
    end
    roundButton("MesJouets", "boutonMesJouets", "Mes jouets", 20, function()
        setHudVisible(false)
        task.spawn(ChestView.open, gui, function()
            setHudVisible(true)
        end)
    end)
    roundButton("Boutique", "boutonBoutique", "Boutique", 156, function()
        Shop.open(gui)
    end)
    roundButton("Reglages", "boutonReglages", nil, 292, function()
        require(script.Parent.Parent.Ui.Menus.Settings).open(gui)
    end)

    -- Evenements du serveur. Remotes ranges dans des variables : une ligne qui commence par « ( » juste apres un
    -- appel serait lue comme la suite de cet appel (les ecouteurs ne seraient jamais branches).
    local noiseState = Remotes.Get("NoiseState") :: RemoteEvent
    local giantState = Remotes.Get("GiantState") :: RemoteEvent
    local caught = Remotes.Get("Caught") :: RemoteEvent
    local chestFull = Remotes.Get("ChestFull") :: RemoteEvent
    local baseTransition = Remotes.Get("BaseTransition") :: RemoteEvent
    -- Passage d'une porte de base : l'ecran fond au noir, le serveur deplace le joueur, puis l'image revient.
    local fade = Instance.new("Frame")
    fade.Name = "FonduPorte"
    fade.BackgroundColor3 = Color3.new(0, 0, 0)
    fade.BackgroundTransparency = 1
    fade.Size = UDim2.fromScale(1, 1)
    fade.ZIndex = 50
    fade.Active = false
    fade.Parent = gui
    baseTransition.OnClientEvent:Connect(function(seconds: number)
        local TweenService = game:GetService("TweenService")
        TweenService:Create(fade, TweenInfo.new(seconds), { BackgroundTransparency = 0 }):Play()
        task.delay(seconds + 0.25, function()
            TweenService:Create(fade, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
        end)
    end)
    noiseState.OnClientEvent:Connect(function(value: number, max: number)
        setNoise(value, max)
    end)
    giantState.OnClientEvent:Connect(function(name: string)
        setBabyState(name)
    end)
    caught.OnClientEvent:Connect(function()
        local flash = Theme.text(
            gui,
            "Attrape",
            "ATTRAPÉ !",
            UDim2.fromOffset(640, 130),
            UDim2.fromScale(0.5, 0.4),
            Theme.RED,
            Vector2.new(0.5, 0.5)
        )
        task.delay(1.6, function()
            flash:Destroy()
        end)
    end)
    chestFull.OnClientEvent:Connect(function(chests: number, capacity: number, price: number, canBuy: boolean)
        ChestFull.show(gui, chests, capacity, price, canBuy)
    end)
end

return HudController
