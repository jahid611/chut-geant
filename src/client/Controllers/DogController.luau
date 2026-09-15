--!strict

--[[
    DogController
    Cote client de la cuisine (KitchenService, DogService) :
    - dans la cuisine (attribut joueur Piece = "Cuisine"), la jauge du chien prend exactement la place de la jauge
      « CHUT ! » du HUD (bloc « Bruit » de PlayerGui.HUD, masque par son nom) et l'etat du chien (dort, grogne, chasse,
      avec le compte a rebours) celle de l'etat du bebe (bloc « EtatBebe ») ; tout revient en sortant ;
    - tete de chien dessinee dans l'interface (aucune image a televerser, aucun emoji) ;
    - « OUAF ! » quand le chien attrape le joueur, cadenas quand la cuisine n'est pas encore ouverte ;
    - sons du chien : ronflement 3D pres du panier, grognement au reveil, aboiement a la chasse et a l'attrape ;
    - eclairage de nuit de la cuisine : etalonnage local « CuisineNuit » (froid, rougit pendant la chasse) et lumiere du
      frigo entrouvert qui vacille. AmbianceController n'est pas touche.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kitchen = require(Shared:WaitForChild("Kitchen"))
local Remotes = require(Shared:WaitForChild("Remotes"))

-- Chemins ecrits en entier : luau-lsp ne resout pas un require passe par une variable.
local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

local SEGMENTS = 34
local UPDATE_SECONDS = 0.1
local NOTICE_SECONDS = 2.6

-- Sons publics de la bibliotheque Roblox (createurs verifies).
local GROWL_ID = "rbxassetid://80685210912488" -- « Cartoon Dog Growling »
local BARK_ID = "rbxassetid://99723552215501" -- « Dog bark »
local SNORE_ID = "rbxassetid://7067277738" -- « snoring »

type DogStateDef = { text: string, color: Color3 }

local DOG_STATES: { [string]: DogStateDef } = {
    Sleeping = { text = "DORT", color = Theme.WHITE },
    Growling = { text = "GROGNE", color = Theme.YELLOW },
    Hunting = { text = "CHASSE", color = Theme.RED },
}

local FUR = Color3.fromRGB(204, 146, 94)
local FUR_DARK = Color3.fromRGB(126, 82, 50)
local MUZZLE = Color3.fromRGB(246, 228, 198)
local NIGHT_TINT = Color3.fromRGB(214, 222, 255)
local GROWL_TINT = Color3.fromRGB(255, 232, 200)
local HUNT_TINT = Color3.fromRGB(255, 176, 170)

local DogController = {}

local function block(gui: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.BackgroundTransparency = 1
    frame.Size = size
    frame.Position = position
    frame.AnchorPoint = anchor
    frame.Visible = false
    frame.Parent = gui
    Theme.fit(frame, Theme.HUD_FACTOR)
    return frame
end

local function roundFrame(
    parent: Instance,
    name: string,
    color: Color3,
    size: UDim2,
    position: UDim2,
    zIndex: number,
    rotation: number?
): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.BackgroundColor3 = color
    frame.BorderSizePixel = 0
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Size = size
    frame.Position = position
    frame.Rotation = rotation or 0
    frame.ZIndex = zIndex
    frame.Parent = parent
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)
    corner.Parent = frame
    return frame
end

-- Tete de chien dessinee en cadres arrondis ; rend une fonction qui ouvre (true) ou ferme les yeux.
local function drawDogHead(parent: Instance, name: string, size: UDim2, position: UDim2): (boolean) -> ()
    local root = Instance.new("Frame")
    root.Name = name
    root.BackgroundTransparency = 1
    root.Size = size
    root.Position = position
    root.ZIndex = 2
    root.Parent = parent
    local aspect = Instance.new("UIAspectRatioConstraint")
    aspect.AspectRatio = 1
    aspect.Parent = root
    roundFrame(root, "OreilleGauche", FUR_DARK, UDim2.fromScale(0.28, 0.52), UDim2.fromScale(0.19, 0.45), 2, 22)
    roundFrame(root, "OreilleDroite", FUR_DARK, UDim2.fromScale(0.28, 0.52), UDim2.fromScale(0.81, 0.45), 2, -22)
    local head = roundFrame(root, "Tete", FUR, UDim2.fromScale(0.66, 0.62), UDim2.fromScale(0.5, 0.5), 3)
    Theme.stroke(head, 3, Theme.WHITE)
    roundFrame(root, "Museau", MUZZLE, UDim2.fromScale(0.4, 0.28), UDim2.fromScale(0.5, 0.67), 4)
    roundFrame(root, "Truffe", Theme.NAVY_DARK, UDim2.fromScale(0.17, 0.11), UDim2.fromScale(0.5, 0.6), 5)
    local eyes = {
        roundFrame(root, "OeilGauche", Theme.NAVY_DARK, UDim2.fromScale(0.1, 0.1), UDim2.fromScale(0.37, 0.43), 5),
        roundFrame(root, "OeilDroit", Theme.NAVY_DARK, UDim2.fromScale(0.1, 0.1), UDim2.fromScale(0.63, 0.43), 5),
    }
    return function(open: boolean)
        for _, eye in eyes do
            eye.Size = if open then UDim2.fromScale(0.11, 0.11) else UDim2.fromScale(0.14, 0.035)
        end
    end
end

-- Cadenas dessine (anse et corps).
local function drawPadlock(parent: Instance, size: UDim2, position: UDim2): ()
    local root = Instance.new("Frame")
    root.Name = "Cadenas"
    root.BackgroundTransparency = 1
    root.Size = size
    root.Position = position
    root.AnchorPoint = Vector2.new(0, 0.5)
    root.ZIndex = 2
    root.Parent = parent
    local aspect = Instance.new("UIAspectRatioConstraint")
    aspect.AspectRatio = 1
    aspect.Parent = root
    local shackle = roundFrame(root, "Anse", Theme.YELLOW, UDim2.fromScale(0.5, 0.56), UDim2.fromScale(0.5, 0.36), 3)
    shackle.BackgroundTransparency = 1
    Theme.stroke(shackle, 6, Theme.YELLOW)
    local body = Instance.new("Frame")
    body.Name = "Corps"
    body.BackgroundColor3 = Theme.YELLOW
    body.BorderSizePixel = 0
    body.AnchorPoint = Vector2.new(0.5, 1)
    body.Size = UDim2.fromScale(0.82, 0.56)
    body.Position = UDim2.fromScale(0.5, 1)
    body.ZIndex = 4
    body.Parent = root
    Theme.corner(body, 8)
    Theme.stroke(body, 2, Theme.WHITE)
    roundFrame(body, "Serrure", Theme.NAVY_DARK, UDim2.fromScale(0.18, 0.32), UDim2.fromScale(0.5, 0.5), 5)
end

local function makeSound(name: string, id: string, volume: number, parent: Instance): Sound
    local sound = Instance.new("Sound")
    sound.Name = name
    sound.SoundId = id
    sound.Volume = volume
    sound.SoundGroup = Sfx.group("Effets")
    sound.Parent = parent
    return sound
end

local function dogModel(): Model?
    local kitchen = Workspace:FindFirstChild("Cuisine")
    local dog = if kitchen then kitchen:FindFirstChild(Kitchen.DOG_NAME) else nil
    return if dog and dog:IsA("Model") then dog else nil
end

-- Dernier etat recu du serveur, et fonction branchee par Start une fois l'interface construite.
type DogSnapshot = { noise: number, max: number, state: string, endsAt: number }
local latest: DogSnapshot = { noise = 0, max = Kitchen.NOISE_MAX, state = "Sleeping", endsAt = 0 }
local onDogState: ((DogSnapshot) -> ())? = nil

-- L'ecouteur de DogState est branche des Init (avant tout le reste) : aucun message ne s'entasse dans la file.
function DogController:Init(): ()
    local stateRemote = Remotes.Get("DogState") :: RemoteEvent
    stateRemote.OnClientEvent:Connect(function(newNoise: any, newMax: any, newState: any, newEndsAt: any)
        if
            typeof(newNoise) ~= "number"
            or typeof(newMax) ~= "number"
            or typeof(newState) ~= "string"
            or typeof(newEndsAt) ~= "number"
        then
            return
        end
        latest = { noise = newNoise, max = newMax, state = newState, endsAt = newEndsAt }
        local listener = onDogState
        if listener then
            listener(latest)
        end
    end)
end

function DogController:Start(): ()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "Cuisine"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 5
    gui.Parent = playerGui

    -- Jauge du chien : memes taille, place et segments que la jauge CHUT ! du HUD
    local noiseBlock =
        block(gui, "BruitChien", UDim2.fromOffset(600, 146), UDim2.new(0.5, 0, 0, 4), Vector2.new(0.5, 0))
    local title = Theme.text(
        noiseBlock,
        "Titre",
        "LE CHIEN",
        UDim2.fromOffset(240, 56),
        UDim2.new(0.5, -44, 0, 0),
        Theme.WHITE,
        Vector2.new(0.5, 0)
    )
    local bar = Theme.panel(noiseBlock, "Jauge", UDim2.fromOffset(500, 72), UDim2.fromOffset(18, 58), Vector2.zero)
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
        segment.BackgroundTransparency = 0.82
        segment.Parent = bar
        Theme.corner(segment, 3)
        table.insert(segments, segment)
    end
    local setGaugeEyes = drawDogHead(noiseBlock, "Chien", UDim2.fromOffset(108, 108), UDim2.fromOffset(468, 40))
    local zzz = Theme.text(
        noiseBlock,
        "Zzz",
        "Zzz",
        UDim2.fromOffset(66, 34),
        UDim2.fromOffset(540, 24),
        Theme.BLUE,
        Vector2.zero
    )
    zzz.ZIndex = 6

    -- Etat du chien : a la place de l'etat du bebe
    local stateBlock = block(gui, "EtatChien", UDim2.fromOffset(250, 86), UDim2.new(1, -14, 0, 14), Vector2.new(1, 0))
    local statePanel = Theme.panel(stateBlock, "Pilule", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero)
    local setStateEyes = drawDogHead(stateBlock, "Chien", UDim2.fromOffset(72, 72), UDim2.fromOffset(12, 7))
    local stateLabel = Theme.text(
        stateBlock,
        "Texte",
        "DORT",
        UDim2.fromOffset(148, 48),
        UDim2.fromOffset(90, 19),
        Theme.WHITE,
        Vector2.zero
    )

    -- Avis : cuisine fermee (cadenas)
    local noticeBlock =
        block(gui, "AvisCuisine", UDim2.fromOffset(560, 92), UDim2.new(0.5, 0, 0, 118), Vector2.new(0.5, 0))
    Theme.panel(noticeBlock, "Pilule", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero)
    drawPadlock(noticeBlock, UDim2.fromOffset(64, 64), UDim2.new(0, 18, 0.5, 0))
    local noticeLabel = Theme.label(
        noticeBlock,
        "Texte",
        "",
        UDim2.new(1, -112, 0, 52),
        UDim2.new(0, 96, 0.5, 0),
        Theme.WHITE,
        Vector2.new(0, 0.5),
        34,
        Enum.TextXAlignment.Left
    )

    -- « OUAF ! » a l'attrape
    -- sous « ATTRAPÉ ! » du HUD (40 % de la hauteur) et sous le personnage : plus haut, il s'empilait avec « ATTRAPÉ ! »
    -- ou passait derriere le message « Il chasse ! Reste immobile. »
    local ouafBlock = block(gui, "Ouaf", UDim2.fromOffset(560, 150), UDim2.fromScale(0.5, 0.64), Vector2.new(0.5, 0.5))
    local ouafLabel = Theme.text(
        ouafBlock,
        "Texte",
        "OUAF !",
        UDim2.fromScale(1, 1),
        UDim2.fromScale(0.5, 0.5),
        Theme.YELLOW,
        Vector2.new(0.5, 0.5)
    )
    local ouafScale = Instance.new("UIScale")
    ouafScale.Parent = ouafLabel

    local growl = makeSound("ChienGrogne", GROWL_ID, 0.6, SoundService)
    local bark = makeSound("ChienAboie", BARK_ID, 0.6, SoundService)
    local snore: Sound? = nil

    local grade = Instance.new("ColorCorrectionEffect")
    grade.Name = "CuisineNuit"
    grade.TintColor = NIGHT_TINT
    grade.Contrast = 0.08
    grade.Saturation = -0.08
    grade.Enabled = false
    grade.Parent = Lighting

    local noise, maxNoise = latest.noise, latest.max
    local dogState = latest.state
    local endsAt = latest.endsAt
    local inKitchen = false
    local noticeToken = 0
    local ouafToken = 0

    local function setHudBlocks(visible: boolean): ()
        local hud = playerGui:FindFirstChild("HUD")
        if hud == nil then
            return
        end
        for _, name in { "Bruit", "EtatBebe" } do
            local object = hud:FindFirstChild(name)
            if object and object:IsA("GuiObject") and object.Visible ~= visible then
                object.Visible = visible
            end
        end
    end

    local function render(): ()
        local fraction = math.clamp(noise / math.max(maxNoise, 1), 0, 1)
        for i, segment in segments do
            segment.BackgroundTransparency = if i / SEGMENTS <= fraction + 0.001 then 0 else 0.82
        end
        local def = DOG_STATES[dogState] or DOG_STATES.Sleeping
        local remaining = if endsAt > 0 then math.max(math.ceil(endsAt - Workspace:GetServerTimeNow()), 0) else 0
        stateLabel.Text = if remaining > 0 then string.format("%s %d", def.text, remaining) else def.text
        stateLabel.TextColor3 = def.color
        local stroke = statePanel:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = def.color
        end
        title.TextColor3 = if dogState == "Hunting" then Theme.RED else Theme.WHITE
        local awake = dogState ~= "Sleeping"
        setGaugeEyes(awake)
        setStateEyes(awake)
        zzz.Visible = not awake
    end
    render()

    local function showNotice(text: string): ()
        noticeToken += 1
        local token = noticeToken
        noticeLabel.Text = text
        noticeBlock.Visible = true
        task.delay(NOTICE_SECONDS, function()
            if token == noticeToken then
                noticeBlock.Visible = false
            end
        end)
    end

    local function popOuaf(text: string): ()
        ouafToken += 1
        local token = ouafToken
        ouafLabel.Text = text
        ouafLabel.TextTransparency = 0
        ouafScale.Scale = 0.3
        ouafBlock.Visible = true
        TweenService:Create(ouafScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Scale = 1,
        }):Play()
        task.delay(0.9, function()
            if token ~= ouafToken then
                return
            end
            local fade = TweenService:Create(ouafLabel, TweenInfo.new(0.35), { TextTransparency = 1 })
            fade:Play()
            fade.Completed:Wait()
            if token == ouafToken then
                ouafBlock.Visible = false
            end
        end)
    end

    local function onStateChanged(previous: string, current: string): ()
        if not inKitchen then
            return
        end
        if current == "Growling" then
            growl.TimePosition = 0
            growl:Play()
            Theme.toast(gui, "Le chien se réveille : ne bouge plus !", Theme.YELLOW)
        elseif current == "Hunting" then
            bark.TimePosition = 0
            bark:Play()
            Theme.toast(gui, "Il chasse ! Reste immobile.", Theme.RED)
        elseif current == "Sleeping" and previous == "Hunting" then
            Theme.toast(gui, "Ouf, le chien se rendort.", Theme.MINT)
        end
    end

    onDogState = function(snapshot: DogSnapshot)
        noise, maxNoise, endsAt = snapshot.noise, snapshot.max, snapshot.endsAt
        if snapshot.state ~= dogState then
            local previous = dogState
            dogState = snapshot.state
            onStateChanged(previous, snapshot.state)
        end
        render()
    end

    local noticeRemote = Remotes.Get("KitchenNotice") :: RemoteEvent
    noticeRemote.OnClientEvent:Connect(function(kind: any, text: any)
        if typeof(kind) ~= "string" or typeof(text) ~= "string" then
            return
        end
        if kind == "locked" then
            Sfx.play("refuse")
            showNotice(text)
        elseif kind == "caught" then
            bark.TimePosition = 0
            bark:Play()
            popOuaf(text)
        end
    end)

    local random = Random.new()
    local fridgeBase: { [Light]: number } = {}
    local elapsed = 0
    RunService.Heartbeat:Connect(function(dt: number)
        elapsed += dt
        if elapsed < UPDATE_SECONDS then
            return
        end
        elapsed = 0

        local nowInKitchen = player:GetAttribute("Piece") == "Cuisine"
        if nowInKitchen ~= inKitchen then
            inKitchen = nowInKitchen
            grade.Enabled = inKitchen
            if not inKitchen then
                setHudBlocks(true)
            end
        end
        local hud = playerGui:FindFirstChild("HUD")
        local hudShown = hud == nil or not hud:IsA("ScreenGui") or hud.Enabled
        noiseBlock.Visible = inKitchen and hudShown
        stateBlock.Visible = inKitchen and hudShown
        if inKitchen then
            -- a chaque tour : le HUD peut etre recree (reapparition) et remontrer ses blocs
            setHudBlocks(false)
            render()
        end

        -- Ronflement 3D colle au chien, seulement quand il dort et qu'on est dans la cuisine
        local dog = dogModel()
        if snore == nil or snore.Parent == nil then
            local body = if dog then dog:FindFirstChildWhichIsA("BasePart", true) else nil
            if body then
                local sound = makeSound("ChienRonfle", SNORE_ID, 0.45, body)
                sound.Looped = true
                sound.RollOffMinDistance = 40
                sound.RollOffMaxDistance = 380
                snore = sound
            end
        end
        if snore then
            local shouldPlay = inKitchen and dogState == "Sleeping"
            if shouldPlay and not snore.IsPlaying then
                snore:Play()
            elseif not shouldPlay and snore.IsPlaying then
                snore:Stop()
            end
        end

        if not inKitchen then
            return
        end
        -- Etalonnage : froid la nuit, chaud au grognement, rouge qui pulse pendant la chasse
        local now = os.clock()
        if dogState == "Hunting" then
            grade.TintColor = NIGHT_TINT:Lerp(HUNT_TINT, 0.55 + 0.45 * math.sin(now * 6))
        elseif dogState == "Growling" then
            grade.TintColor = NIGHT_TINT:Lerp(GROWL_TINT, 0.7)
        else
            grade.TintColor = NIGHT_TINT
        end
        -- Lumiere du frigo entrouvert qui vacille un peu (rendu local)
        local kitchen = Workspace:FindFirstChild("Cuisine")
        local fridgeLight = if kitchen then kitchen:FindFirstChild("LumiereFrigo") else nil
        if fridgeLight then
            for _, light in fridgeLight:GetChildren() do
                if light:IsA("Light") then
                    local base = fridgeBase[light]
                    if base == nil then
                        base = light.Brightness
                        fridgeBase[light] = base
                    end
                    light.Brightness = base * (0.88 + 0.12 * random:NextNumber())
                end
            end
        end
    end)
end

return DogController
