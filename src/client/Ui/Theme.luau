--!strict

--[[
    Theme
    Couleurs, police et constructeurs de l'interface, d'apres les maquettes validees
    (docs/mockups/higgsfield/) : panneaux bleu nuit translucides, epais contour blanc,
    touches pastel (rose, bleu ciel, menthe, jaune), police arrondie.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Assets = require(script.Parent:WaitForChild("Assets"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local REFERENCE_VIEWPORT = Vector2.new(1344, 752)

local Theme = {}

Theme.FONT = Enum.Font.FredokaOne
Theme.NAVY = Color3.fromRGB(22, 30, 66)
Theme.NAVY_LIGHT = Color3.fromRGB(36, 48, 100)
Theme.NAVY_DARK = Color3.fromRGB(12, 16, 40)
Theme.WHITE = Color3.fromRGB(255, 255, 255)
Theme.SOFT_TEXT = Color3.fromRGB(176, 190, 245)
Theme.PINK = Color3.fromRGB(255, 132, 188)
Theme.BLUE = Color3.fromRGB(96, 170, 255)
Theme.MINT = Color3.fromRGB(88, 222, 168)
Theme.YELLOW = Color3.fromRGB(255, 212, 96)
Theme.GREEN = Color3.fromRGB(72, 204, 96)
Theme.RED = Color3.fromRGB(245, 88, 96)
Theme.GREY = Color3.fromRGB(128, 136, 172)

local RARITY: { [string]: { label: string, color: Color3 } } = {
    Common = { label = "COMMUN", color = Color3.fromRGB(150, 160, 190) },
    Uncommon = { label = "PEU COMMUN", color = Color3.fromRGB(64, 196, 140) },
    Rare = { label = "RARE", color = Color3.fromRGB(74, 150, 255) },
    Epic = { label = "ÉPIQUE", color = Color3.fromRGB(168, 104, 255) },
    Legendary = { label = "LÉGENDAIRE", color = Color3.fromRGB(245, 180, 40) },
}
Theme.RARITY = RARITY

-- Aucun emoji dans l'interface (demande utilisateur) : tant qu'une icone n'est pas televersee, sa place reste vide.
local FALLBACK: { [string]: string } = {}

-- Facteur d'echelle de l'interface selon la taille de l'ecran (maquettes dessinees en 1344 x 752).
function Theme.viewportFactor(): number
    local viewport = Workspace.CurrentCamera.ViewportSize
    return math.clamp(math.min(viewport.X / REFERENCE_VIEWPORT.X, viewport.Y / REFERENCE_VIEWPORT.Y), 0.5, 1.3)
end

-- Ajoute a un bloc d'interface une echelle qui suit la taille de l'ecran ; factor reduit encore le bloc
-- (le HUD en jeu est a Theme.HUD_FACTOR : il prenait trop de place, retour utilisateur).
Theme.HUD_FACTOR = 0.68
function Theme.fit(object: GuiObject, factor: number?): UIScale
    local scale = Instance.new("UIScale")
    local k = factor or 1
    scale.Scale = Theme.viewportFactor() * k
    scale.Parent = object
    Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        scale.Scale = Theme.viewportFactor() * k
    end)
    return scale
end

function Theme.corner(parent: Instance, radius: number): UICorner
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
    return corner
end

function Theme.stroke(parent: Instance, thickness: number, color: Color3): UIStroke
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = thickness
    stroke.Color = color
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = parent
    return stroke
end

function Theme.formatNumber(value: number): string
    local digits = tostring(math.floor(math.abs(value)))
    -- string.gsub rend (texte, nombre) : les parentheses ne gardent que le texte
    local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1 ")))
    grouped = (string.gsub(grouped, "^ ", ""))
    return (if value < 0 then "-" else "") .. grouped
end

function Theme.panel(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.Size = size
    frame.Position = position
    frame.AnchorPoint = anchor
    frame.BackgroundColor3 = Theme.NAVY
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Theme.corner(frame, 26)
    Theme.stroke(frame, 3, Theme.WHITE)
    return frame
end

function Theme.text(
    parent: Instance,
    name: string,
    text: string,
    size: UDim2,
    position: UDim2,
    color: Color3,
    anchor: Vector2
): TextLabel
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Text = text
    label.Size = size
    label.Position = position
    label.AnchorPoint = anchor
    label.BackgroundTransparency = 1
    label.Font = Theme.FONT
    label.TextScaled = true
    label.TextColor3 = color
    label.Parent = parent
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Theme.NAVY_DARK
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
    stroke.Parent = label
    return label
end

-- Image d'Assets ; tant qu'elle n'est pas televersee, un emoji la remplace.
function Theme.image(
    parent: Instance,
    name: string,
    key: string,
    size: UDim2,
    position: UDim2,
    anchor: Vector2
): GuiObject
    local id = Assets[key]
    if id == nil or id == "rbxassetid://0" then
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Text = FALLBACK[key] or "?"
        label.Size = size
        label.Position = position
        label.AnchorPoint = anchor
        label.BackgroundTransparency = 1
        label.TextScaled = true
        label.Parent = parent
        return label
    end
    local image = Instance.new("ImageLabel")
    image.Name = name
    image.Image = id
    image.Size = size
    image.Position = position
    image.AnchorPoint = anchor
    image.BackgroundTransparency = 1
    image.ScaleType = Enum.ScaleType.Fit
    image.Parent = parent
    -- Le bebe et la lune sont decoupes dans la maquette avec le fond de leur pastille : on arrondit pour ne garder
    -- que le cercle (le carre de fond se voyait en jeu).
    if key == "bebeDort" or key == "lune" then
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0.5, 0)
        corner.Parent = image
    end
    return image
end

local function pressEffect(button: GuiButton): ()
    local scale = Instance.new("UIScale")
    scale.Parent = button
    button.MouseButton1Down:Connect(function()
        TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 0.93 }):Play()
    end)
    local function up()
        TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
    end
    button.MouseButton1Up:Connect(up)
    button.MouseLeave:Connect(up)
end

function Theme.button(
    parent: Instance,
    name: string,
    text: string,
    color: Color3,
    size: UDim2,
    position: UDim2,
    anchor: Vector2
): TextButton
    local button = Instance.new("TextButton")
    button.Name = name
    button.Text = text
    button.Size = size
    button.Position = position
    button.AnchorPoint = anchor
    button.BackgroundColor3 = color
    button.AutoButtonColor = false
    button.Font = Theme.FONT
    button.TextScaled = true
    button.TextColor3 = Theme.WHITE
    button.BorderSizePixel = 0
    button.Parent = parent
    Theme.corner(button, 22)
    Theme.stroke(button, 3, Theme.WHITE)
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0.18, 0)
    padding.PaddingBottom = UDim.new(0.18, 0)
    padding.PaddingLeft = UDim.new(0, 14)
    padding.PaddingRight = UDim.new(0, 14)
    padding.Parent = button
    local textStroke = Instance.new("UIStroke")
    textStroke.Thickness = 2
    textStroke.Color = Theme.NAVY_DARK
    textStroke.Transparency = 0.4
    textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
    textStroke.Parent = button
    pressEffect(button)
    -- petit clic doux sur tous les boutons (demande utilisateur : « des bruits pour tout »)
    button.Activated:Connect(function()
        Sfx.play("click")
    end)
    return button
end

-- Bouton rond a image (maquette : Mes jouets, Boutique, Reglages).
function Theme.roundImageButton(parent: Instance, name: string, key: string, size: UDim2, position: UDim2): GuiButton
    local id = Assets[key]
    local button: GuiButton
    if id == nil or id == "rbxassetid://0" then
        local fallback = Instance.new("TextButton")
        fallback.Text = FALLBACK[key] or "?"
        fallback.TextScaled = true
        fallback.BackgroundColor3 = Theme.NAVY
        Theme.stroke(fallback, 3, Theme.WHITE)
        button = fallback
    else
        -- icone PNG sans fond affichee telle quelle : ni pastille ronde ni recadrage (retour utilisateur)
        local image = Instance.new("ImageButton")
        image.Image = id
        image.BackgroundTransparency = 1
        image.ScaleType = Enum.ScaleType.Fit
        button = image
    end
    button.Name = name
    button.Size = size
    button.Position = position
    button.AutoButtonColor = false
    button.Parent = parent
    pressEffect(button)
    button.Activated:Connect(function()
        Sfx.play("click")
    end)
    return button
end

--[[
    Mise en page des menus sans debordement (retour utilisateur : « fais gaffe de jamais faire dépasser les infos
    d'un menu ») et avec des icones partout (« rien de mieux que le visuel »). Regles :
    - le contenu d'un menu vit dans une zone qui coupe au bord (Theme.scrollList / scrollGrid, Modal.body) ;
    - les largeurs sont en proportion du parent, les textes a taille automatique bornee (Theme.label) ;
    - les icones gardent leur carre dans la boite donnee (Theme.icon).
]]

-- Echelle comme Theme.fit, mais bornee pour que l'objet (taille de base `base`, en pixels) tienne dans
-- `maxFraction` de l'ecran : un menu ne sort jamais de la fenetre, meme sur un petit ecran.
function Theme.fitInside(object: GuiObject, base: Vector2, maxFraction: number): UIScale
    local scale = Instance.new("UIScale")
    local function compute(): number
        local viewport = Workspace.CurrentCamera.ViewportSize
        local k = Theme.viewportFactor()
        if base.X > 0 and base.Y > 0 then
            k = math.min(k, viewport.X * maxFraction / base.X, viewport.Y * maxFraction / base.Y)
        end
        return k
    end
    scale.Scale = compute()
    scale.Parent = object
    Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        scale.Scale = compute()
    end)
    return scale
end

-- Borne la taille d'un texte a taille automatique (TextScaled) : jamais plus grand que maxTextSize.
function Theme.limitText(object: GuiObject, maxTextSize: number): ()
    local constraint = Instance.new("UITextSizeConstraint")
    constraint.MaxTextSize = maxTextSize
    constraint.MinTextSize = 8
    constraint.Parent = object
end

-- Texte qui tient toujours dans sa boite : taille automatique bornee, alignement au choix.
function Theme.label(
    parent: Instance,
    name: string,
    text: string,
    size: UDim2,
    position: UDim2,
    color: Color3,
    anchor: Vector2,
    maxTextSize: number?,
    align: Enum.TextXAlignment?
): TextLabel
    local label = Theme.text(parent, name, text, size, position, color, anchor)
    Theme.limitText(label, maxTextSize or 30)
    if align then
        label.TextXAlignment = align
    end
    return label
end

-- Icone carree qui tient dans la boite donnee (proportions gardees). Tant que l'image n'est pas televersee, une
-- pastille ronde coloree prend sa place (aucun « ? » ni emoji).
function Theme.icon(
    parent: Instance,
    name: string,
    key: string,
    size: UDim2,
    position: UDim2,
    anchor: Vector2,
    fallbackColor: Color3?
): GuiObject
    local id = Assets[key]
    local object: GuiObject
    if id == nil or id == "rbxassetid://0" then
        local tile = Instance.new("Frame")
        tile.BackgroundColor3 = fallbackColor or Theme.NAVY_LIGHT
        tile.BorderSizePixel = 0
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0.5, 0)
        corner.Parent = tile
        Theme.stroke(tile, 2, Theme.WHITE)
        object = tile
    else
        local image = Instance.new("ImageLabel")
        image.Image = id
        image.BackgroundTransparency = 1
        image.ScaleType = Enum.ScaleType.Fit
        object = image
    end
    object.Name = name
    object.Size = size
    object.Position = position
    object.AnchorPoint = anchor
    local aspect = Instance.new("UIAspectRatioConstraint")
    aspect.AspectRatio = 1
    aspect.Parent = object
    object.Parent = parent
    return object
end

-- Liste verticale defilante qui coupe tout ce qui depasse ; les enfants se rangent par LayoutOrder et prennent
-- la largeur de la liste (barre de defilement fine, hors du contenu).
function Theme.scrollList(
    parent: Instance,
    name: string,
    size: UDim2,
    position: UDim2,
    anchor: Vector2,
    padding: number?
): ScrollingFrame
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = name
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.Size = size
    scroll.Position = position
    scroll.AnchorPoint = anchor
    scroll.ClipsDescendants = true
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new()
    scroll.ScrollBarThickness = 6
    scroll.ScrollBarImageColor3 = Theme.SOFT_TEXT
    scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
    scroll.Parent = parent
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0, padding or 10)
    layout.Parent = scroll
    local inner = Instance.new("UIPadding")
    inner.PaddingTop = UDim.new(0, 6)
    inner.PaddingBottom = UDim.new(0, 12)
    inner.PaddingLeft = UDim.new(0, 6)
    inner.PaddingRight = UDim.new(0, 6)
    inner.Parent = scroll
    return scroll
end

-- Grille defilante : `columns` colonnes qui se partagent la largeur, cellules de `cellHeight` pixels.
function Theme.scrollGrid(
    parent: Instance,
    name: string,
    size: UDim2,
    position: UDim2,
    anchor: Vector2,
    columns: number,
    cellHeight: number,
    gap: number
): ScrollingFrame
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = name
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.Size = size
    scroll.Position = position
    scroll.AnchorPoint = anchor
    scroll.ClipsDescendants = true
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new()
    scroll.ScrollBarThickness = 6
    scroll.ScrollBarImageColor3 = Theme.SOFT_TEXT
    scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
    scroll.Parent = parent
    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(1 / columns, -gap * (columns - 1) / columns, 0, cellHeight)
    grid.CellPadding = UDim2.fromOffset(gap, gap)
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = scroll
    local inner = Instance.new("UIPadding")
    inner.PaddingTop = UDim.new(0, 6)
    inner.PaddingBottom = UDim.new(0, 12)
    inner.PaddingLeft = UDim.new(0, 6)
    inner.PaddingRight = UDim.new(0, 6)
    inner.Parent = scroll
    return scroll
end

-- Ligne de liste : toute la largeur de la liste, hauteur fixe, fond bleu clair et fin contour.
function Theme.row(parent: Instance, name: string, height: number, order: number, strokeColor: Color3?): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.LayoutOrder = order
    frame.Size = UDim2.new(1, 0, 0, height)
    frame.BackgroundColor3 = Theme.NAVY_LIGHT
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Theme.corner(frame, 16)
    Theme.stroke(frame, 2, strokeColor or Color3.fromRGB(120, 140, 210))
    return frame
end

-- Barre de progression (fraction entre 0 et 1).
function Theme.progress(
    parent: Instance,
    name: string,
    fraction: number,
    size: UDim2,
    position: UDim2,
    anchor: Vector2,
    color: Color3
): Frame
    local bar = Instance.new("Frame")
    bar.Name = name
    bar.BackgroundColor3 = Theme.NAVY_DARK
    bar.BorderSizePixel = 0
    bar.Size = size
    bar.Position = position
    bar.AnchorPoint = anchor
    bar.ClipsDescendants = true
    bar.Parent = parent
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)
    corner.Parent = bar
    local fill = Instance.new("Frame")
    fill.Name = "Remplissage"
    fill.BackgroundColor3 = color
    fill.BorderSizePixel = 0
    fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
    fill.Parent = bar
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0.5, 0)
    fillCorner.Parent = fill
    return bar
end

-- Pastille « icone + valeur » (prix, recompense, bonus). Prevue au moins 3 fois plus large que haute.
function Theme.pill(
    parent: Instance,
    name: string,
    key: string,
    text: string,
    size: UDim2,
    position: UDim2,
    anchor: Vector2,
    textColor: Color3,
    maxTextSize: number?
): (Frame, TextLabel)
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.BackgroundColor3 = Theme.NAVY_DARK
    frame.BorderSizePixel = 0
    frame.Size = size
    frame.Position = position
    frame.AnchorPoint = anchor
    frame.Parent = parent
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)
    corner.Parent = frame
    Theme.icon(frame, "Icone", key, UDim2.fromScale(0.3, 0.86), UDim2.fromScale(0.03, 0.5), Vector2.new(0, 0.5))
    local label = Theme.label(
        frame,
        "Texte",
        text,
        UDim2.fromScale(0.64, 0.72),
        UDim2.fromScale(0.97, 0.5),
        textColor,
        Vector2.new(1, 0.5),
        maxTextSize or 24,
        Enum.TextXAlignment.Center
    )
    return frame, label
end

-- Icone d'un message court d'apres ses mots, dans l'ordre (retour utilisateur du 15/09 : « des icones, c'est toujours
-- mieux que des mots »). « Nouveau dans ta collection : ... (+150 tétines) » prend la collection, pas la tetine.
local TOAST_ICONS: { { string } } = {
    { "record", "iconeDecorTrophee" },
    { "collection", "menuCollection" },
    { "défi", "menuQuetes" },
    { "danse", "cosmetiqueDanse" },
    { "cadeau", "menuCadeaux" },
    { "tipi", "iconeDecorTipi" },
    { "coffre", "articleCoffre" },
    { "veilleuse", "iconeDecorLampe" },
    { "éclair", "iconeDecorLampe" },
    { "lune", "lune" },
    { "nuit", "menuNuits" },
    { "vol", "pouvoirCape" },
    { "tétine", "tetine" },
    { "bébé", "bebeDort" },
    { "xp", "etoile" },
    { "niveau", "etoile" },
    { "tutoriel", "etoile" },
}

local function toastIcon(message: string): string?
    local lower = string.lower(message)
    for _, pair in TOAST_ICONS do
        if string.find(lower, pair[1], 1, true) then
            return pair[2]
        end
    end
    return nil
end

-- Petit message en bas a gauche, taille moyenne, avec une icone ; il disparait tout seul. Il etait gros et au milieu de
-- l'ecran, par-dessus le jeu (capture utilisateur du 15/09). Sur ecran tactile, il passe au-dessus du joystick.
local TOAST_WIDTH = 400
local TOAST_HEIGHT = 56
local TOAST_MARGIN = 16
local TOAST_TOUCH_LIFT = 0.38

local function buildToast(gui: Instance, message: string, color: Color3, icon: string?): ()
    local holder = Instance.new("Frame")
    holder.Name = "Toast"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(TOAST_WIDTH, TOAST_HEIGHT)
    holder.AnchorPoint = Vector2.new(0, 1)
    holder.Parent = gui
    local scale = Theme.fit(holder)
    -- les messages rapproches (et ceux des autres ecrans : chien, cuisine...) s'empilent vers le haut
    local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local stacked = 0
    local toastRoot: Instance = playerGui or gui
    for _, other in toastRoot:GetDescendants() do
        if other ~= holder and other.Name == "Toast" and other:IsA("GuiObject") then
            stacked += 1
        end
    end
    local lift = if UserInputService.TouchEnabled then TOAST_TOUCH_LIFT else 0
    local bottom = TOAST_MARGIN + stacked * (TOAST_HEIGHT + 8) * scale.Scale
    holder.Position = UDim2.new(0, TOAST_MARGIN, 1 - lift, -bottom)
    local pill = Theme.panel(holder, "Pilule", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero)
    local stroke = pill:FindFirstChildOfClass("UIStroke")
    if stroke then
        stroke.Color = color
    end
    local key = icon or toastIcon(message)
    local textLeft = 18
    if key then
        Theme.icon(pill, "Icone", key, UDim2.fromOffset(44, 44), UDim2.new(0, 8, 0.5, 0), Vector2.new(0, 0.5))
        textLeft = 60
    end
    local label = Theme.text(
        pill,
        "Texte",
        message,
        UDim2.new(1, -(textLeft + 14), 1, -12),
        UDim2.new(0, textLeft, 0.5, 0),
        Theme.WHITE,
        Vector2.new(0, 0.5)
    )
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    -- meme taille de texte d'un message a l'autre (un message court etait ecrit beaucoup plus gros)
    local sizeLimit = Instance.new("UITextSizeConstraint")
    sizeLimit.MaxTextSize = 19
    sizeLimit.Parent = label
    task.delay(3, function()
        if holder.Parent then
            holder:Destroy()
        end
    end)
end

-- Message court. Pendant la celebration « NIVEAU N ! » (LevelController, cadre MonteeNiveau), il attend qu'elle
-- se termine (6 s au plus) : apres un depot, collection, niveau et recompenses se superposaient au centre.
local CELEBRATION_NAME = "MonteeNiveau"
local CELEBRATION_MAX_WAIT = 6

-- icon : cle d'Ui/Assets ; sans elle, l'icone est choisie d'apres les mots du message.
function Theme.toast(gui: Instance, message: string, color: Color3, icon: string?): ()
    local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local function celebrating(): boolean
        return playerGui ~= nil and playerGui:FindFirstChild(CELEBRATION_NAME, true) ~= nil
    end
    if not celebrating() then
        buildToast(gui, message, color, icon)
        return
    end
    task.spawn(function()
        local started = os.clock()
        while celebrating() and os.clock() - started < CELEBRATION_MAX_WAIT do
            task.wait(0.2)
        end
        if gui.Parent then
            buildToast(gui, message, color, icon)
        end
    end)
end

return Theme
