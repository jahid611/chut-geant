--!strict

--[[
    Shop
    La boutique complete (maquette docs/mockups/higgsfield/boutique.png, catalogue Shared/Catalog) :
    solde en tetines au-dessus du panneau, onglets Pouvoirs / Améliorations / Coffres / Cosmétiques, grille de
    cartes defilante (titre, niveau en pastilles, image, description, prix, bouton).

    Etat lu dans les attributs du joueur publies par ShopService : Owned_<id> = niveau, Equipped_<slot> = id,
    Chests, Cash. La grille se redessine quand l'un d'eux change (la position de defilement est gardee).
    Boutons : « Acheter » (BuyItem), « Niv. max », « Acheté », « Équiper » / « Retirer » (EquipCosmetic) pour les
    cosmetiques a emplacement, « Choisir » / « Choisie » pour les danses (choix local, attribut ChosenDance lu par
    DanceController), « Bientôt » seulement pour un article dont le modele 3D n'est pas encore sur le serveur
    (attribut Dispo_<id> de ReplicatedStorage, publie par ShopService).
    Chaque article a sa propre icone ; tant qu'elle n'est pas televersee (« rbxassetid://0 »), la carte montre
    l'icone de sa categorie (traînée, danse, contour, decor, tenue, coffre), sinon une tuile avec l'initiale.
    Decors, tenues et armes dont le modele est sur le serveur : apercu 3D en direct (ViewportFrame avec la copie
    ReplicatedStorage.ApercusBoutique.<id> publiee par ShopService), qui tourne lentement (une seule boucle pour
    toutes les cartes, coupee a la fermeture).

    Mise en page sans debordement (retour utilisateur) : onglets en proportion de la largeur, grille qui partage la
    largeur en 4 colonnes, contenu des cartes borne a la carte, textes a taille bornee.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Tuning"))

local Assets = require(script.Parent:WaitForChild("Assets"))
local Modal = require(script.Parent:WaitForChild("Modal"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))
local Theme = require(script.Parent:WaitForChild("Theme"))

-- Couleur et icone de chaque onglet.
local TAB_STYLE: { [string]: { color: Color3, icon: string } } = {
    ["Pouvoirs"] = { color = Theme.PINK, icon = "pouvoirFurie" },
    ["Améliorations"] = { color = Theme.BLUE, icon = "ongletVitesse" },
    ["Coffres"] = { color = Theme.MINT, icon = "ongletCoffres" },
    ["Armes"] = { color = Theme.RED, icon = "iconeArmeBatte" },
    ["Cosmétiques"] = { color = Theme.YELLOW, icon = "ongletSkins" },
}

local EQUIPPABLE: { [string]: boolean } = { trail = true, outline = true, skin = true, weapon = true, lamp = true }

local CARD_HEIGHT = 330
local MAX_PIPS = 5

local Shop = {}

local player = Players.LocalPlayer

local function levelOf(id: string): number
    local value = player:GetAttribute("Owned_" .. id)
    return if typeof(value) == "number" then value else 0
end

local function chests(): number
    local value = player:GetAttribute("Chests")
    return if typeof(value) == "number" then value else 1
end

local function cash(): number
    local value = player:GetAttribute("Cash")
    return if typeof(value) == "number" then value else 0
end

local function hasImage(key: string): boolean
    local id = Assets[key]
    return id ~= nil and id ~= "rbxassetid://0"
end

-- Icone de categorie, montree tant que l'icone propre a l'article n'est pas televersee.
local CATEGORY_ICON: { [string]: string } = {
    trail = "cosmetiqueTrainee",
    dance = "cosmetiqueDanse",
    outline = "cosmetiqueContour",
    decor = "cosmetiqueDecor",
    skin = "ongletSkins",
    lamp = "iconeDecorLampe",
}

local function fallbackIcon(item: Catalog.Item): string?
    if item.kind == "weapon" then
        return "lourd"
    elseif item.slot then
        return CATEGORY_ICON[item.slot]
    elseif item.kind == "chest" then
        return "articleCoffre"
    end
    return nil
end

type Spinner = { camera: Camera, center: Vector3, distance: number }

-- Copie legere du modele de l'article (ReplicatedStorage.ApercusBoutique), pour les articles a modele 3D.
local function previewOf(item: Catalog.Item): Model?
    if item.slot == "trail" or (item.kind ~= "cosmetic" and item.kind ~= "weapon") then
        return nil
    end
    local folder = ReplicatedStorage:FindFirstChild("ApercusBoutique")
    local preview = if folder then folder:FindFirstChild(item.id) else nil
    return if preview and preview:IsA("Model") then preview else nil
end

-- Position de la camera d'un apercu a l'angle donne : 3/4 legerement au-dessus.
local function spinnerCFrame(spinner: Spinner, angle: number): CFrame
    local direction = Vector3.new(math.cos(angle), 0.45, math.sin(angle)).Unit
    return CFrame.lookAt(spinner.center + direction * spinner.distance, spinner.center)
end

-- Apercu 3D cadre sur la boite englobante du modele ; la camera est ajoutee aux spinners (rotation lente).
local function preview3D(parent: Instance, preview: Model, spinners: { Spinner }): ()
    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "Image"
    viewport.BackgroundTransparency = 1
    viewport.Size = UDim2.new(0.8, 0, 0, 112)
    viewport.Position = UDim2.new(0.5, 0, 0, 68)
    viewport.AnchorPoint = Vector2.new(0.5, 0)
    viewport.Ambient = Color3.fromRGB(190, 190, 210)
    viewport.LightColor = Color3.fromRGB(255, 245, 235)
    viewport.LightDirection = Vector3.new(-1, -1, -1)
    viewport.Parent = parent
    local model = preview:Clone()
    model.Parent = viewport
    local camera = Instance.new("Camera")
    camera.FieldOfView = 35
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    local center, size = model:GetBoundingBox()
    local radius = math.max(size.Magnitude / 2, 0.5)
    local spinner: Spinner = {
        camera = camera,
        center = center.Position,
        distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05,
    }
    camera.CFrame = spinnerCFrame(spinner, os.clock() * 0.6)
    table.insert(spinners, spinner)
end

-- Image de l'article ; sinon son apercu 3D ; sinon l'icone de sa categorie ; sinon une tuile avec l'initiale.
local function artwork(parent: Instance, item: Catalog.Item, color: Color3, spinners: { Spinner }): ()
    if not hasImage(item.icon) then
        local preview = previewOf(item)
        if preview then
            preview3D(parent, preview, spinners)
            return
        end
    end
    local key = if hasImage(item.icon) then item.icon else fallbackIcon(item)
    if key and hasImage(key) then
        Theme.icon(parent, "Image", key, UDim2.new(0.7, 0, 0, 108), UDim2.new(0.5, 0, 0, 70), Vector2.new(0.5, 0))
        return
    end
    local tile = Instance.new("Frame")
    tile.Name = "Image"
    tile.BackgroundColor3 = color
    tile.BorderSizePixel = 0
    tile.Size = UDim2.fromOffset(100, 100)
    tile.Position = UDim2.new(0.5, 0, 0, 74)
    tile.AnchorPoint = Vector2.new(0.5, 0)
    tile.Parent = parent
    Theme.corner(tile, 26)
    Theme.stroke(tile, 3, Theme.WHITE)
    Theme.label(
        tile,
        "Initiale",
        string.upper(string.sub(item.name, 1, 1)),
        UDim2.fromScale(0.6, 0.6),
        UDim2.fromScale(0.5, 0.5),
        Theme.WHITE,
        Vector2.new(0.5, 0.5),
        60
    )
end

type ButtonState = { text: string, color: Color3, action: string? }

-- Etat du bouton d'une carte : texte, couleur et action ("buy", "equip", "dance" ou nil = inactif).
local function buttonState(item: Catalog.Item): (ButtonState, number?)
    local level = levelOf(item.id)
    -- cosmetiques et armes : achat unique puis Équiper / Retirer
    if item.kind == "cosmetic" or item.kind == "weapon" then
        if level > 0 then
            local slot = item.slot
            if slot == "dance" then
                local chosen = player:GetAttribute("ChosenDance") == item.id
                return {
                    text = if chosen then "Choisie" else "Choisir",
                    color = if chosen then Theme.GREY else Theme.BLUE,
                    action = if chosen then nil else "dance",
                },
                    nil
            elseif slot and EQUIPPABLE[slot] then
                local equipped = player:GetAttribute("Equipped_" .. slot) == item.id
                return {
                    text = if equipped then "Retirer" else "Équiper",
                    color = if equipped then Theme.PINK else Theme.BLUE,
                    action = "equip",
                },
                    nil
            end
            return { text = "Acheté", color = Theme.GREY }, nil
        end
        -- recompense de mission : pas de prix, seulement gagnee en jeu
        if item.exclusive then
            return { text = "Mission", color = Theme.GREY }, nil
        end
        -- disponibilite publiee par ShopService (modele 3D present sur le serveur)
        if item.needs3D and ReplicatedStorage:GetAttribute("Dispo_" .. item.id) ~= true then
            return { text = "Bientôt", color = Theme.GREY }, nil
        end
    end
    if item.id == "Chest" and chests() >= Tuning.MAX_CHESTS then
        return { text = "Maximum", color = Theme.GREY }, nil
    end
    local price = Catalog.NextPrice(item, level)
    if price == nil then
        local maxed = item.kind == "upgrade" or item.kind == "chest"
        return { text = if maxed then "Niv. max" else "Acheté", color = Theme.GREY }, nil
    end
    if item.id == "GoldChest" and level >= chests() then
        return { text = "Coffre requis", color = Theme.GREY }, price
    end
    return { text = "Acheter", color = Theme.GREEN, action = "buy" }, price
end

-- Progression en pastilles (niveau, coffres...) : (rempli, total), ou nil pour un achat unique.
local function pips(item: Catalog.Item): (number?, number?)
    local level = levelOf(item.id)
    if item.id == "Chest" then
        return chests(), Tuning.MAX_CHESTS
    elseif item.id == "GoldChest" then
        return level, chests()
    elseif item.kind == "upgrade" and Catalog.MaxLevel(item) > 1 then
        return level, Catalog.MaxLevel(item)
    end
    return nil, nil
end

-- Petite ligne sous le titre pour les achats uniques.
local function subtitle(item: Catalog.Item): string
    if item.kind == "ability" then
        return "Pouvoir"
    elseif item.slot == "trail" then
        return "Traînée"
    elseif item.slot == "dance" then
        return "Danse"
    elseif item.slot == "outline" then
        return "Contour"
    elseif item.slot == "decor" then
        return "Décor de base"
    elseif item.slot == "skin" then
        return "Tenue"
    elseif item.slot == "lamp" then
        return "Accessoire"
    elseif item.kind == "weapon" then
        return "Arme"
    end
    return ""
end

function Shop.open(gui: Instance): ()
    if Modal.isOpen(gui) then
        return
    end
    local modal = Modal.open(gui, "BOUTIQUE", Theme.WHITE, UDim2.fromOffset(1000, 660))
    local panel = modal.panel
    Theme.icon(panel, "IconeTitre", "tetine", UDim2.fromOffset(62, 62), UDim2.new(0.2, -6, 0, 16), Vector2.new(1, 0))

    -- Solde, pose au-dessus du panneau
    local _, balanceLabel = Theme.pill(
        panel,
        "Solde",
        "tetine",
        "",
        UDim2.fromOffset(250, 58),
        UDim2.new(0.5, 0, 0, -14),
        Vector2.new(0.5, 1),
        Theme.WHITE,
        34
    )

    -- Onglets : quatre parts egales de la largeur
    local tabs = Instance.new("Frame")
    tabs.Name = "Onglets"
    tabs.BackgroundTransparency = 1
    tabs.Size = UDim2.new(1, -40, 0, 58)
    tabs.Position = UDim2.new(0.5, 0, 0, 96)
    tabs.AnchorPoint = Vector2.new(0.5, 0)
    tabs.Parent = panel

    local scroller = Theme.scrollGrid(
        panel,
        "Articles",
        UDim2.new(1, -40, 1, -190),
        UDim2.new(0.5, 0, 0, 170),
        Vector2.new(0.5, 0),
        4,
        CARD_HEIGHT,
        14
    )

    local currentTab = Catalog.TABS[1]
    local render: () -> ()
    local busy = false
    -- cameras des apercus 3D des cartes affichees : une seule boucle les fait tourner
    local spinners: { Spinner } = {}
    local spinConnection = RunService.Heartbeat:Connect(function()
        if #spinners == 0 then
            return
        end
        local angle = os.clock() * 0.6
        for _, spinner in spinners do
            spinner.camera.CFrame = spinnerCFrame(spinner, angle)
        end
    end)

    local function invoke(remoteName: string, item: Catalog.Item, button: TextButton): ()
        if busy then
            return
        end
        busy = true
        button.Text = "..."
        local ok, success, message = pcall(function()
            return (Remotes.Get(remoteName) :: RemoteFunction):InvokeServer(item.id)
        end)
        busy = false
        if not ok then
            Sfx.play("refuse")
            Theme.toast(gui, "La boutique ne répond pas, réessaie.", Theme.RED)
        else
            local text = if typeof(message) == "string" then message else "C'est fait."
            if success == true then
                Sfx.play(if remoteName == "BuyItem" then "purchase" else "click")
            else
                Sfx.play("refuse")
            end
            Theme.toast(gui, text, if success == true then Theme.GREEN else Theme.RED)
        end
        render()
    end

    local function card(item: Catalog.Item, order: number): ()
        local style = TAB_STYLE[item.tab] or TAB_STYLE["Pouvoirs"]
        local frame = Instance.new("Frame")
        frame.Name = item.id
        frame.LayoutOrder = order
        frame.BackgroundColor3 = Theme.NAVY_LIGHT
        frame.BorderSizePixel = 0
        frame.ClipsDescendants = true
        frame.Parent = scroller
        Theme.corner(frame, 22)
        Theme.stroke(frame, 2, Color3.fromRGB(120, 140, 210))

        local title = if item.id == "Chest"
            then string.format("Coffre n°%d", math.min(chests() + 1, Tuning.MAX_CHESTS))
            else item.name
        Theme.label(
            frame,
            "Titre",
            title,
            UDim2.new(1, -20, 0, 30),
            UDim2.new(0.5, 0, 0, 10),
            Theme.WHITE,
            Vector2.new(0.5, 0),
            24
        )

        -- niveau en pastilles, sinon le type d'article
        local filled, total = pips(item)
        if filled and total and total > 0 then
            local row = Instance.new("Frame")
            row.Name = "Niveau"
            row.BackgroundTransparency = 1
            row.Size = UDim2.new(1, -24, 0, 20)
            row.Position = UDim2.new(0.5, 0, 0, 44)
            row.AnchorPoint = Vector2.new(0.5, 0)
            row.Parent = frame
            local layout = Instance.new("UIListLayout")
            layout.FillDirection = Enum.FillDirection.Horizontal
            layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            layout.VerticalAlignment = Enum.VerticalAlignment.Center
            layout.Padding = UDim.new(0, 6)
            layout.Parent = row
            local shown = math.min(total, MAX_PIPS)
            for i = 1, shown do
                local pip = Instance.new("Frame")
                pip.Name = "Pastille" .. i
                pip.LayoutOrder = i
                pip.BackgroundColor3 = if i <= filled then style.color else Theme.NAVY_DARK
                pip.BorderSizePixel = 0
                pip.Size = UDim2.fromOffset(16, 16)
                pip.Parent = row
                Theme.corner(pip, 8)
                Theme.stroke(pip, 2, Theme.WHITE)
            end
        else
            Theme.label(
                frame,
                "Type",
                subtitle(item),
                UDim2.new(1, -40, 0, 22),
                UDim2.new(0.5, 0, 0, 43),
                style.color,
                Vector2.new(0.5, 0),
                18
            )
        end

        artwork(frame, item, style.color, spinners)
        Theme.label(
            frame,
            "Description",
            item.description,
            UDim2.new(1, -24, 0, 36),
            UDim2.new(0.5, 0, 0, 182),
            Theme.SOFT_TEXT,
            Vector2.new(0.5, 0),
            18
        )

        local state, price = buttonState(item)
        if price then
            Theme.pill(
                frame,
                "Prix",
                "tetine",
                Theme.formatNumber(price),
                UDim2.new(0.8, 0, 0, 36),
                UDim2.new(0.5, 0, 0, 224),
                Vector2.new(0.5, 0),
                if cash() >= price then Theme.WHITE else Theme.RED,
                22
            )
        end

        local button = Theme.button(
            frame,
            "Bouton",
            state.text,
            state.color,
            UDim2.new(0.84, 0, 0, 48),
            UDim2.new(0.5, 0, 1, -12),
            Vector2.new(0.5, 1)
        )
        Theme.limitText(button, 24)
        local action = state.action
        if action == "buy" then
            button.Activated:Connect(function()
                invoke("BuyItem", item, button)
            end)
        elseif action == "equip" then
            button.Activated:Connect(function()
                invoke("EquipCosmetic", item, button)
            end)
        elseif action == "dance" then
            button.Activated:Connect(function()
                -- choix local : DanceController lance cette danse avec la touche B
                player:SetAttribute("ChosenDance", item.id)
                Theme.toast(gui, item.name .. " : touche B pour danser !", Theme.GREEN)
                render()
            end)
        end
    end

    local tabButtons: { [string]: TextButton } = {}

    render = function(): ()
        local keep = scroller.CanvasPosition
        table.clear(spinners)
        for _, child in scroller:GetChildren() do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
        local order = 0
        for _, item in Catalog.All() do
            if item.tab == currentTab then
                order += 1
                card(item, order)
            end
        end
        for name, button in tabButtons do
            local style = TAB_STYLE[name]
            local tabStroke = button:FindFirstChildOfClass("UIStroke")
            if tabStroke then
                tabStroke.Thickness = if name == currentTab then 5 else 3
                tabStroke.Color = if name == currentTab then Theme.YELLOW else Theme.WHITE
            end
            button.BackgroundColor3 = if name == currentTab then style.color else style.color:Lerp(Theme.NAVY, 0.45)
        end
        scroller.CanvasPosition = keep
        balanceLabel.Text = Theme.formatNumber(cash())
    end

    local tabCount = #Catalog.TABS
    for i, name in Catalog.TABS do
        local style = TAB_STYLE[name] or TAB_STYLE["Pouvoirs"]
        local button = Theme.button(
            tabs,
            "Onglet" .. i,
            name,
            style.color,
            UDim2.new(1 / tabCount, -12, 1, 0),
            UDim2.new((i - 1) / tabCount, 6, 0, 0),
            Vector2.zero
        )
        Theme.limitText(button, 24)
        -- icone a gauche, texte a droite : le texte commence apres l'icone (32 % de l'onglet)
        local buttonPadding = button:FindFirstChildOfClass("UIPadding")
        if buttonPadding then
            buttonPadding.PaddingLeft = UDim.new(0.3, 0)
            buttonPadding.PaddingRight = UDim.new(0, 8)
        end
        -- jamais de rond vide : une icone d'onglet pas encore televersee retombe sur une icone existante
        local tabIcon = if hasImage(style.icon) then style.icon elseif hasImage("lourd") then "lourd" else "tetine"
        Theme.icon(
            button,
            "Icone",
            tabIcon,
            UDim2.new(0, 46, 1.5, 0),
            UDim2.fromScale(-0.28, 0.5),
            Vector2.new(0, 0.5),
            Theme.WHITE
        )
        tabButtons[name] = button
        button.Activated:Connect(function()
            if currentTab ~= name then
                currentTab = name
                scroller.CanvasPosition = Vector2.zero
                render()
            end
        end)
    end

    -- Redessin groupe : plusieurs attributs changent souvent ensemble apres un achat.
    local pending = false
    local function schedule(): ()
        if pending then
            return
        end
        pending = true
        task.defer(function()
            pending = false
            if modal.root.Parent then
                render()
            end
        end)
    end
    local attributeConnection = player.AttributeChanged:Connect(function(attribute: string)
        if attribute == "Cash" then
            balanceLabel.Text = Theme.formatNumber(cash())
        elseif
            string.sub(attribute, 1, 6) == "Owned_"
            or string.sub(attribute, 1, 9) == "Equipped_"
            or attribute == "Chests"
            or attribute == "ChosenDance"
        then
            schedule()
        end
    end)
    -- un modele 3D qui arrive rend son article achetable tout de suite
    local availabilityConnection = ReplicatedStorage.AttributeChanged:Connect(function(attribute: string)
        if string.sub(attribute, 1, 6) == "Dispo_" then
            schedule()
        end
    end)
    modal.root.Destroying:Connect(function()
        attributeConnection:Disconnect()
        availabilityConnection:Disconnect()
        spinConnection:Disconnect()
        table.clear(spinners)
    end)

    render()
end

return Shop
