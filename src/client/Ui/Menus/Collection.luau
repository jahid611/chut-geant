--!strict

--[[
    Menu « Collection » (colonne de gauche, MenuController)
    Grille de tous les jouets par rarete, puis les trois mutations. Chaque rarete complete donne +5 % de revenu, les
    mutations +10 % (ToyCollectionService). Lit les attributs du joueur CollectionToys, CollectionMutations et
    CollectionBonus.

    Mise en page : liste defilante qui coupe au bord du panneau ; en-tetes de sets en pastilles (compte, bonus) ;
    grille de cartes en proportion de la largeur. Image du jouet (cle Assets « jouet<ToyId> », rendu 3D) : nette s'il
    est trouve, silhouette sombre sinon ; tant que l'image n'est pas televersee, pastille de la couleur de sa rarete
    avec son initiale (ou « ? »), remplacee des qu'il arrive par l'apercu 3D du modele (ToyPreviewService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))

local Assets = require(script.Parent.Parent:WaitForChild("Assets"))
local Modal = require(script.Parent.Parent:WaitForChild("Modal"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local COLUMNS = 5
local CARD_HEIGHT = 156

local MUTATION_COLORS: { [string]: Color3 } = {
    Gold = Color3.fromRGB(255, 200, 40),
    Rainbow = Color3.fromRGB(255, 80, 220),
    Cosmic = Color3.fromRGB(120, 70, 255),
}

local Menu = {}

local function split(value: any): { [string]: boolean }
    local set: { [string]: boolean } = {}
    if typeof(value) == "string" then
        for id in string.gmatch(value, "[^,]+") do
            set[id] = true
        end
    end
    return set
end

local function hasImage(key: string?): boolean
    if key == nil then
        return false
    end
    local id = Assets[key]
    return id ~= nil and id ~= "rbxassetid://0"
end

-- Jouet sans image televersee : sa pastille est remplacee par un apercu 3D des qu'il arrive (ToyPreviewService),
-- vu de trois quarts face avant ; en couleur s'il est trouve, silhouette sombre sinon (comme les vraies images).
-- Si l'apercu n'arrive pas, la carte garde sa pastille.
local function toyPreview(frame: Frame, token: Frame, toyId: string, found: boolean): ()
    task.spawn(function()
        local remote = Remotes.Get("ToyPreview") :: RemoteFunction
        local ok, ready = pcall(function()
            return remote:InvokeServer(toyId)
        end)
        -- la carte a pu disparaitre (menu ferme) pendant l'attente
        if not ok or ready ~= true or not frame:IsDescendantOf(game) then
            return
        end
        local previews = ReplicatedStorage:WaitForChild("ApercusJouets", 5)
        local source: Instance? = if previews then previews:WaitForChild(toyId, 5) else nil
        if source == nil or not source:IsA("Model") or not frame:IsDescendantOf(game) then
            return
        end
        local viewport = Instance.new("ViewportFrame")
        viewport.Name = "Image"
        viewport.BackgroundTransparency = 1
        viewport.Size = UDim2.fromScale(0.8, 0.46)
        viewport.Position = UDim2.fromScale(0.5, 0.04)
        viewport.AnchorPoint = Vector2.new(0.5, 0)
        viewport.Ambient = Color3.fromRGB(190, 190, 210)
        viewport.LightColor = Color3.fromRGB(255, 245, 235)
        viewport.LightDirection = Vector3.new(-1, -1, -1)
        viewport.ImageColor3 = if found then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
        viewport.ImageTransparency = if found then 0 else 0.35
        local model = source:Clone()
        model.Parent = viewport
        local camera = Instance.new("Camera")
        camera.FieldOfView = 35
        camera.Parent = viewport
        viewport.CurrentCamera = camera
        local center, size = model:GetBoundingBox()
        local radius = math.max(size.Magnitude / 2, 0.5)
        local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
        -- cote -Z : la face avant des modeles Roblox regarde vers -Z
        local direction = Vector3.new(0.6, 0.45, -0.75).Unit
        camera.CFrame = CFrame.lookAt(center.Position + direction * distance, center.Position)
        viewport.Parent = frame
        token:Destroy()
    end)
end

local function card(
    parent: Instance,
    order: number,
    title: string,
    valueIcon: string,
    valueText: string,
    color: Color3,
    found: boolean,
    imageKey: string?
): ()
    local frame = Instance.new("Frame")
    frame.Name = "Carte" .. order
    frame.LayoutOrder = order
    frame.BackgroundColor3 = if found then Theme.NAVY_LIGHT else Theme.NAVY_DARK
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = true
    frame.Parent = parent
    Theme.corner(frame, 16)
    Theme.stroke(frame, 3, if found then color else Theme.GREY)

    if imageKey and hasImage(imageKey) then
        -- vraie image du jouet (rendu 3D) : nette si trouve, silhouette sombre sinon
        local picture = Instance.new("ImageLabel")
        picture.Name = "Image"
        picture.BackgroundTransparency = 1
        picture.Image = Assets[imageKey]
        picture.ScaleType = Enum.ScaleType.Fit
        picture.Size = UDim2.fromScale(0.8, 0.46)
        picture.Position = UDim2.fromScale(0.5, 0.04)
        picture.AnchorPoint = Vector2.new(0.5, 0)
        picture.ImageColor3 = if found then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
        picture.ImageTransparency = if found then 0 else 0.35
        picture.Parent = frame
    else
        local token = Instance.new("Frame")
        token.Name = "Pastille"
        token.BackgroundColor3 = if found then color else Theme.NAVY
        token.BorderSizePixel = 0
        token.Size = UDim2.fromScale(0.7, 0.44)
        token.Position = UDim2.fromScale(0.5, 0.05)
        token.AnchorPoint = Vector2.new(0.5, 0)
        token.Parent = frame
        local aspect = Instance.new("UIAspectRatioConstraint")
        aspect.AspectRatio = 1
        aspect.Parent = token
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0.5, 0)
        corner.Parent = token
        Theme.stroke(token, 2, if found then Theme.WHITE else Theme.GREY)
        Theme.label(
            token,
            "Initiale",
            if found then string.upper(string.sub(title, 1, 1)) else "?",
            UDim2.fromScale(0.6, 0.6),
            UDim2.fromScale(0.5, 0.5),
            if found then Theme.WHITE else Theme.GREY,
            Vector2.new(0.5, 0.5),
            40
        )
        local toyId = if imageKey and string.sub(imageKey, 1, 5) == "jouet" then string.sub(imageKey, 6) else nil
        if toyId and toyId ~= "" then
            toyPreview(frame, token, toyId, found)
        end
    end

    Theme.label(
        frame,
        "Nom",
        if found then title else "???",
        UDim2.new(1, -12, 0.18, 0),
        UDim2.fromScale(0.5, 0.52),
        if found then Theme.WHITE else Theme.GREY,
        Vector2.new(0.5, 0),
        18
    )
    if found then
        Theme.pill(
            frame,
            "Valeur",
            valueIcon,
            valueText,
            UDim2.fromScale(0.9, 0.2),
            UDim2.fromScale(0.5, 0.96),
            Vector2.new(0.5, 1),
            color,
            18
        )
    else
        Theme.icon(
            frame,
            "Verrou",
            "boutonMesJouets",
            UDim2.fromScale(0.5, 0.2),
            UDim2.fromScale(0.5, 0.96),
            Vector2.new(0.5, 1)
        )
    end
end

function Menu.open(gui: Instance): ()
    if Modal.isOpen(gui) then
        return
    end
    local player = Players.LocalPlayer
    -- la pastille disparait une fois la collection consultee
    player:SetAttribute("Notif_Collection", false)
    local found = split(player:GetAttribute("CollectionToys"))
    local mutations = split(player:GetAttribute("CollectionMutations"))
    local bonusValue = player:GetAttribute("CollectionBonus")
    local bonus = if typeof(bonusValue) == "number" then bonusValue else 0

    local modal = Modal.open(gui, "COLLECTION", Theme.WHITE, UDim2.fromOffset(960, 640))
    local panel = modal.panel
    Theme.icon(
        panel,
        "IconeTitre",
        "menuCollection",
        UDim2.fromOffset(62, 62),
        UDim2.new(0.2, -6, 0, 16),
        Vector2.new(1, 0),
        Theme.PINK
    )

    local list =
        Theme.scrollList(panel, "Liste", UDim2.new(1, -40, 1, -112), UDim2.new(0.5, 0, 0, 92), Vector2.new(0.5, 0), 10)
    local order = 0
    local function nextOrder(): number
        order += 1
        return order
    end

    local total, discovered = 0, 0
    for _, toy in Toys.All() do
        total += 1
        if found[toy.id] then
            discovered += 1
        end
    end

    -- resume : jouets trouves et bonus total
    local summary = Instance.new("Frame")
    summary.Name = "Resume"
    summary.LayoutOrder = nextOrder()
    summary.BackgroundTransparency = 1
    summary.Size = UDim2.new(1, 0, 0, 56)
    summary.Parent = list
    Theme.pill(
        summary,
        "Trouves",
        "boutonMesJouets",
        string.format("%d / %d", discovered, total),
        UDim2.new(0.3, 0, 0, 46),
        UDim2.new(0, 4, 0.5, 0),
        Vector2.new(0, 0.5),
        Theme.WHITE,
        28
    )
    Theme.pill(
        summary,
        "Bonus",
        "etoile",
        string.format("+%d %%", math.floor(bonus * 100 + 0.5)),
        UDim2.new(0.25, 0, 0, 46),
        UDim2.new(1, -4, 0.5, 0),
        Vector2.new(1, 0.5),
        Theme.YELLOW,
        28
    )

    local function section(title: string, color: Color3, have: number, count: number, setBonus: number): Frame
        local complete = have == count
        local header = Instance.new("Frame")
        header.Name = "Entete"
        header.LayoutOrder = nextOrder()
        header.BackgroundTransparency = 1
        header.Size = UDim2.new(1, 0, 0, 46)
        header.Parent = list
        local dot = Instance.new("Frame")
        dot.Name = "Couleur"
        dot.BackgroundColor3 = color
        dot.BorderSizePixel = 0
        dot.Size = UDim2.fromOffset(24, 24)
        dot.Position = UDim2.new(0, 6, 0.5, 0)
        dot.AnchorPoint = Vector2.new(0, 0.5)
        dot.Parent = header
        Theme.corner(dot, 12)
        Theme.stroke(dot, 2, Theme.WHITE)
        Theme.label(
            header,
            "Titre",
            title,
            UDim2.new(0.4, -40, 0, 34),
            UDim2.new(0, 40, 0.5, 0),
            color,
            Vector2.new(0, 0.5),
            28,
            Enum.TextXAlignment.Left
        )
        Theme.pill(
            header,
            "Compte",
            "boutonMesJouets",
            string.format("%d / %d", have, count),
            UDim2.new(0.22, 0, 0, 38),
            UDim2.fromScale(0.44, 0.5),
            Vector2.new(0, 0.5),
            Theme.WHITE,
            22
        )
        Theme.pill(
            header,
            "BonusSet",
            "etoile",
            string.format("+%d %%", math.floor(setBonus * 100)),
            UDim2.new(0.22, 0, 0, 38),
            UDim2.new(1, -4, 0.5, 0),
            Vector2.new(1, 0.5),
            if complete then Theme.MINT else Theme.SOFT_TEXT,
            22
        )

        local grid = Instance.new("Frame")
        grid.Name = "Grille"
        grid.LayoutOrder = nextOrder()
        grid.BackgroundTransparency = 1
        grid.Size = UDim2.fromScale(1, 0)
        grid.AutomaticSize = Enum.AutomaticSize.Y
        grid.Parent = list
        local layout = Instance.new("UIGridLayout")
        layout.CellSize = UDim2.new(1 / COLUMNS, -10, 0, CARD_HEIGHT)
        layout.CellPadding = UDim2.fromOffset(10, 10)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = grid
        return grid
    end

    for _, rarity in Progression.RARITY_ORDER do
        local info = Theme.RARITY[rarity]
        local count, have = 0, 0
        for _, toy in Toys.All() do
            if toy.rarity == rarity then
                count += 1
                if found[toy.id] then
                    have += 1
                end
            end
        end
        if count == 0 then
            continue
        end
        local color = if info then info.color else Theme.WHITE
        local grid = section(if info then info.label else rarity, color, have, count, Progression.COLLECTION_SET_BONUS)
        local index = 0
        for _, toy in Toys.All() do
            if toy.rarity == rarity then
                index += 1
                card(
                    grid,
                    index,
                    toy.displayName,
                    "tetine",
                    string.format("+%s/s", Theme.formatNumber(toy.incomePerSecond)),
                    color,
                    found[toy.id] == true,
                    "jouet" .. toy.id
                )
            end
        end
    end

    local mutationCount = 0
    for _, id in Progression.MUTATION_IDS do
        if mutations[id] then
            mutationCount += 1
        end
    end
    local grid = section(
        "MUTATIONS",
        Theme.PINK,
        mutationCount,
        #Progression.MUTATION_IDS,
        Progression.COLLECTION_MUTATION_SET_BONUS
    )
    for i, id in Progression.MUTATION_IDS do
        local mutation = Toys.GetMutation(id)
        if mutation then
            card(
                grid,
                i,
                mutation.displayName,
                "etoile",
                string.format("x%d", mutation.multiplier),
                MUTATION_COLORS[id] or Theme.PINK,
                mutations[id] == true
            )
        end
    end
end

return Menu
