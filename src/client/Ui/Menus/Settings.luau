--!strict

--[[
    Menu « Paramètres » (bouton engrenage du HUD)
    - Son : volume de la musique et des effets (curseurs 0 a 100 %, groupes de sons « Musique » et « Effets ») ;
    - Affichage : noms et niveaux au-dessus des tetes des autres joueurs, effets reduits (attribut EffetsReduits) ;
    - Aide : rejouer le tutoriel (remote TutorialAction « restart ») ;
    - Codes cadeaux : champ, bouton Valider et resultat avec icone (RemoteFunction RedeemCode).
    Les choix partent au serveur (remote Settings, SettingsService) qui les sauvegarde dans le profil et les publie
    en attributs du joueur ; SettingsController les applique des la connexion.

    Mise en page : liste defilante qui coupe au bord du panneau, largeurs en proportion.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Modal = require(script.Parent.Parent:WaitForChild("Modal"))
local Sfx = require(script.Parent.Parent:WaitForChild("Sfx"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local SETTINGS_COLOR = Theme.BLUE

local Menu = {}

local function number(value: any, default: number): number
    return if typeof(value) == "number" then value else default
end

local function sendSetting(key: string, value: number | boolean): ()
    (Remotes.Get("Settings") :: RemoteEvent):FireServer(key, value)
end

-- Titre de rubrique (texte a gauche, pas de fond).
local function section(list: Instance, order: number, text: string): ()
    local holder = Instance.new("Frame")
    holder.Name = "Rubrique" .. order
    holder.LayoutOrder = order
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.new(1, 0, 0, 36)
    holder.Parent = list
    Theme.label(
        holder,
        "Titre",
        text,
        UDim2.new(1, -16, 1, -4),
        UDim2.new(0, 8, 0.5, 0),
        Theme.SOFT_TEXT,
        Vector2.new(0, 0.5),
        26,
        Enum.TextXAlignment.Left
    )
end

-- Ligne avec une icone a gauche et un titre ; rend la ligne pour y poser les controles.
local function iconRow(list: Instance, order: number, name: string, icon: string, height: number): Frame
    local row = Theme.row(list, name, height, order)
    Theme.icon(
        row,
        "Icone",
        icon,
        UDim2.fromOffset(58, 58),
        UDim2.new(0, 12, 0.5, 0),
        Vector2.new(0, 0.5),
        SETTINGS_COLOR
    )
    return row
end

type Connections = { RBXScriptConnection }

-- Curseur 0..1 : applique en direct pendant le glissement (apply), envoie la valeur au lacher (commit).
local function slider(
    list: ScrollingFrame,
    order: number,
    name: string,
    icon: string,
    title: string,
    initial: number,
    color: Color3,
    apply: (number) -> (),
    commit: (number) -> (),
    connections: Connections
): ()
    local row = iconRow(list, order, name, icon, 104)
    Theme.label(
        row,
        "Titre",
        title,
        UDim2.new(1, -210, 0, 34),
        UDim2.fromOffset(86, 10),
        Theme.WHITE,
        Vector2.zero,
        26,
        Enum.TextXAlignment.Left
    )
    local percent = Theme.label(
        row,
        "Pourcentage",
        "",
        UDim2.fromOffset(100, 34),
        UDim2.new(1, -16, 0, 10),
        color,
        Vector2.new(1, 0),
        26,
        Enum.TextXAlignment.Right
    )
    local track = Theme.progress(
        row,
        "Piste",
        initial,
        UDim2.new(1, -130, 0, 18),
        UDim2.fromOffset(92, 66),
        Vector2.new(0, 0.5),
        color
    )
    -- la piste coupe son remplissage : la poignee vit sur un rail invisible de meme taille, qui ne coupe pas
    local rail = Instance.new("Frame")
    rail.Name = "Rail"
    rail.BackgroundTransparency = 1
    rail.Size = track.Size
    rail.Position = track.Position
    rail.AnchorPoint = track.AnchorPoint
    rail.Parent = row
    local knob = Instance.new("Frame")
    knob.Name = "Poignee"
    knob.Size = UDim2.fromOffset(34, 34)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.BackgroundColor3 = Theme.WHITE
    knob.BorderSizePixel = 0
    knob.ZIndex = 3
    knob.Parent = rail
    Theme.corner(knob, 17)
    Theme.stroke(knob, 3, color)
    local hitbox = Instance.new("TextButton")
    hitbox.Name = "Zone"
    hitbox.Text = ""
    hitbox.BackgroundTransparency = 1
    hitbox.Size = UDim2.new(1, -110, 0, 56)
    hitbox.Position = UDim2.fromOffset(82, 66)
    hitbox.AnchorPoint = Vector2.new(0, 0.5)
    hitbox.ZIndex = 4
    hitbox.Parent = row

    local fill = track:FindFirstChild("Remplissage") :: Frame
    local value = math.clamp(initial, 0, 1)
    local function show(): ()
        fill.Size = UDim2.fromScale(value, 1)
        percent.Text = string.format("%d %%", math.floor(value * 100 + 0.5))
        knob.Position = UDim2.fromScale(value, 0.5)
    end

    local dragging = false
    local function setFromX(x: number): ()
        local width = track.AbsoluteSize.X
        if width <= 0 then
            return
        end
        value = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
        show()
        apply(value)
    end
    hitbox.InputBegan:Connect(function(input: InputObject)
        local kind = input.UserInputType
        if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
            dragging = true
            list.ScrollingEnabled = false
            setFromX(input.Position.X)
        end
    end)
    table.insert(
        connections,
        UserInputService.InputChanged:Connect(function(input: InputObject)
            local kind = input.UserInputType
            if dragging and (kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch) then
                setFromX(input.Position.X)
            end
        end)
    )
    table.insert(
        connections,
        UserInputService.InputEnded:Connect(function(input: InputObject)
            local kind = input.UserInputType
            if dragging and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
                dragging = false
                list.ScrollingEnabled = true
                commit(value)
            end
        end)
    )
    show()
end

-- Bascule Oui / Non a droite de la ligne.
local function toggle(
    list: Instance,
    order: number,
    name: string,
    icon: string,
    title: string,
    hint: string,
    get: () -> boolean,
    set: (boolean) -> ()
): () -> ()
    local row = iconRow(list, order, name, icon, 92)
    Theme.label(
        row,
        "Titre",
        title,
        UDim2.new(0.72, -92, 0, 34),
        UDim2.fromOffset(86, 12),
        Theme.WHITE,
        Vector2.zero,
        26,
        Enum.TextXAlignment.Left
    )
    Theme.label(
        row,
        "Aide",
        hint,
        UDim2.new(0.72, -92, 0, 26),
        UDim2.fromOffset(86, 52),
        Theme.SOFT_TEXT,
        Vector2.zero,
        20,
        Enum.TextXAlignment.Left
    )
    local button = Theme.button(
        row,
        "Bascule",
        "",
        Theme.GREY,
        UDim2.new(0.24, 0, 0, 58),
        UDim2.new(1, -16, 0.5, 0),
        Vector2.new(1, 0.5)
    )
    Theme.limitText(button, 26)
    local function refresh(): ()
        local on = get()
        button.Text = if on then "Oui" else "Non"
        button.BackgroundColor3 = if on then Theme.GREEN else Theme.GREY
    end
    button.Activated:Connect(function()
        set(not get())
        refresh()
    end)
    refresh()
    return refresh
end

function Menu.open(gui: Instance): ()
    if Modal.isOpen(gui) then
        return
    end
    local player = Players.LocalPlayer
    local modal = Modal.open(gui, "PARAMÈTRES", SETTINGS_COLOR, UDim2.fromOffset(820, 700))
    local list = Theme.scrollList(
        modal.panel,
        "Liste",
        UDim2.new(1, -40, 1, -112),
        UDim2.new(0.5, 0, 0, 92),
        Vector2.new(0.5, 0),
        10
    )
    local connections: Connections = {}

    -- Son
    section(list, 1, "Son")
    slider(
        list,
        2,
        "Musique",
        "lune",
        "Volume de la musique",
        number(player:GetAttribute("ReglageMusique"), 1),
        Theme.PINK,
        function(value: number)
            Sfx.group("Musique").Volume = value
        end,
        function(value: number)
            sendSetting("musicVolume", value)
        end,
        connections
    )
    slider(
        list,
        3,
        "Effets",
        "etoile",
        "Volume des effets",
        number(player:GetAttribute("ReglageEffets"), 1),
        Theme.YELLOW,
        function(value: number)
            Sfx.group("Effets").Volume = value
        end,
        function(value: number)
            sendSetting("sfxVolume", value)
            Sfx.play("click")
        end,
        connections
    )

    -- Affichage
    section(list, 4, "Affichage")
    local refreshNames = toggle(
        list,
        5,
        "Noms",
        "menuAmis",
        "Noms des joueurs",
        "Noms et niveaux au-dessus des têtes.",
        function()
            return player:GetAttribute("ReglageNoms") ~= false
        end,
        function(on: boolean)
            player:SetAttribute("ReglageNoms", on)
            sendSetting("showNames", on)
        end
    )
    local refreshEffects = toggle(
        list,
        6,
        "Qualite",
        "cosmetiqueTrainee",
        "Effets réduits",
        "Moins de particules, jeu plus fluide.",
        function()
            return player:GetAttribute("EffetsReduits") == true
        end,
        function(on: boolean)
            sendSetting("reducedEffects", on)
        end
    )
    table.insert(connections, player:GetAttributeChangedSignal("ReglageNoms"):Connect(refreshNames))
    table.insert(connections, player:GetAttributeChangedSignal("EffetsReduits"):Connect(refreshEffects))

    -- Aide
    section(list, 7, "Aide")
    local tutorialRow = iconRow(list, 8, "Tutoriel", "retour", 88)
    Theme.label(
        tutorialRow,
        "Titre",
        "Rejouer le tutoriel",
        UDim2.new(0.68, -92, 0, 40),
        UDim2.new(0, 86, 0.5, 0),
        Theme.WHITE,
        Vector2.new(0, 0.5),
        26,
        Enum.TextXAlignment.Left
    )
    local replay = Theme.button(
        tutorialRow,
        "Rejouer",
        "Rejouer",
        Theme.MINT,
        UDim2.new(0.28, 0, 0, 58),
        UDim2.new(1, -16, 0.5, 0),
        Vector2.new(1, 0.5)
    )
    Theme.limitText(replay, 26)
    replay.Activated:Connect(function()
        if player:GetAttribute("TutorialDone") ~= true then
            Theme.toast(gui, "Le tutoriel est déjà en cours.", Theme.YELLOW)
            return
        end
        (Remotes.Get("TutorialAction") :: RemoteEvent):FireServer("restart")
        Theme.toast(gui, "C'est reparti pour le tutoriel !", Theme.MINT)
        modal.close()
    end)

    -- Codes cadeaux
    section(list, 9, "Codes cadeaux")
    local codeRow = iconRow(list, 10, "Code", "menuCadeaux", 150)
    local box = Instance.new("TextBox")
    box.Name = "Saisie"
    box.Text = ""
    box.PlaceholderText = "Entre un code"
    box.PlaceholderColor3 = Theme.GREY
    box.ClearTextOnFocus = false
    box.Font = Theme.FONT
    box.TextScaled = true
    box.TextColor3 = Theme.WHITE
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.BackgroundColor3 = Theme.NAVY_DARK
    box.BorderSizePixel = 0
    box.ClipsDescendants = true
    box.Size = UDim2.new(0.66, -92, 0, 58)
    box.Position = UDim2.fromOffset(86, 14)
    box.Parent = codeRow
    Theme.corner(box, 14)
    Theme.stroke(box, 2, SETTINGS_COLOR)
    Theme.limitText(box, 28)
    local boxPadding = Instance.new("UIPadding")
    boxPadding.PaddingLeft = UDim.new(0, 14)
    boxPadding.PaddingRight = UDim.new(0, 14)
    boxPadding.PaddingTop = UDim.new(0, 12)
    boxPadding.PaddingBottom = UDim.new(0, 12)
    boxPadding.Parent = box
    local validate = Theme.button(
        codeRow,
        "Valider",
        "Valider",
        Theme.GREEN,
        UDim2.new(0.3, 0, 0, 58),
        UDim2.new(1, -16, 0, 14),
        Vector2.new(1, 0)
    )
    Theme.limitText(validate, 26)

    -- Resultat : icone + message, sous le champ
    local result = Instance.new("Frame")
    result.Name = "Resultat"
    result.BackgroundTransparency = 1
    result.Size = UDim2.new(1, -102, 0, 50)
    result.Position = UDim2.fromOffset(86, 86)
    result.Parent = codeRow
    local resultIcon: GuiObject? = nil
    local resultLabel = Theme.label(
        result,
        "Message",
        "Des codes sont donnés sur nos réseaux.",
        UDim2.new(1, -60, 1, -8),
        UDim2.new(0, 58, 0.5, 0),
        Theme.SOFT_TEXT,
        Vector2.new(0, 0.5),
        24,
        Enum.TextXAlignment.Left
    )
    local function showResult(icon: string, message: string, color: Color3): ()
        if resultIcon then
            resultIcon:Destroy()
        end
        resultIcon = Theme.icon(
            result,
            "Icone",
            icon,
            UDim2.fromOffset(46, 46),
            UDim2.fromScale(0, 0.5),
            Vector2.new(0, 0.5),
            color
        )
        resultLabel.Text = message
        resultLabel.TextColor3 = color
    end
    showResult("menuCadeaux", "Des codes sont donnés sur nos réseaux.", Theme.SOFT_TEXT)

    local busy = false
    local function redeem(): ()
        if busy then
            return
        end
        local code = (string.gsub(box.Text, "%s", ""))
        if code == "" then
            showResult("bebeDort", "Écris un code d'abord.", Theme.YELLOW)
            return
        end
        busy = true
        validate.BackgroundColor3 = Theme.GREY
        local ok, success, message, icon = pcall(function()
            return (Remotes.Get("RedeemCode") :: RemoteFunction):InvokeServer(code)
        end)
        busy = false
        if validate.Parent == nil then
            return
        end
        validate.BackgroundColor3 = Theme.GREEN
        if not ok then
            showResult("bebeDort", "Les codes ne répondent pas, réessaie.", Theme.RED)
            return
        end
        local text = if typeof(message) == "string" then message else "Code invalide"
        local key = if typeof(icon) == "string" then icon else "bebeDort"
        if success == true then
            showResult(key, text, Theme.GREEN)
            Theme.toast(gui, text, Theme.GREEN)
            Sfx.play("purchase")
            box.Text = ""
        else
            showResult(key, text, Theme.RED)
            Sfx.play("refuse")
        end
    end
    validate.Activated:Connect(redeem)
    box.FocusLost:Connect(function(enterPressed: boolean)
        if enterPressed then
            redeem()
        end
    end)

    modal.root.Destroying:Connect(function()
        for _, connection in connections do
            connection:Disconnect()
        end
    end)
end

return Menu
