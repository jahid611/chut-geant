--!strict

--[[
    Menu « Nuits » (renaissance, NightsService)
    Nuit actuelle et bonus, prix de la nuit suivante avec une barre, ce qu'on perd et ce qu'on garde (en icones),
    encart de la cuisine a venir, bouton en deux temps (« Passer à la nuit N » puis « Confirmer ? »).
    Lit les attributs du joueur Nights, NightCost et Cash ; remote Rebirth.

    Mise en page : liste defilante qui coupe au bord du panneau, lignes en proportion de la largeur.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Modal = require(script.Parent.Parent:WaitForChild("Modal"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local NIGHT_COLOR = Color3.fromRGB(170, 140, 255)

local LOST = {
    { icon = "tetine", label = "Tétines" },
    { icon = "boutonMesJouets", label = "Jouets" },
    { icon = "articleCoffre", label = "Coffres" },
}
local KEPT = {
    { icon = "pouvoirFurie", label = "Pouvoirs" },
    { icon = "articleChaussons", label = "Bonus" },
    { icon = "cosmetiqueTrainee", label = "Style" },
    { icon = "menuCollection", label = "Collection" },
    { icon = "menuPass", label = "Pass" },
}

local Menu = {}

local function number(value: any): number
    return if typeof(value) == "number" then value else 0
end

-- Ligne « titre + petites icones legendees » (ce qu'on perd / ce qu'on garde).
local function iconStrip(
    parent: Instance,
    order: number,
    title: string,
    color: Color3,
    entries: { { icon: string, label: string } }
): ()
    local frame = Theme.row(parent, title, 128, order, color)
    Theme.label(
        frame,
        "Titre",
        title,
        UDim2.new(0.5, 0, 0, 30),
        UDim2.fromOffset(16, 6),
        color,
        Vector2.zero,
        26,
        Enum.TextXAlignment.Left
    )
    local width = 1 / math.max(#entries, 1)
    for i, entry in entries do
        local slot = Instance.new("Frame")
        slot.Name = "Element" .. i
        slot.BackgroundTransparency = 1
        slot.Size = UDim2.new(width, -8, 0, 86)
        slot.Position = UDim2.new((i - 1) * width, 4, 0, 38)
        slot.Parent = frame
        Theme.icon(
            slot,
            "Icone",
            entry.icon,
            UDim2.new(1, 0, 0, 56),
            UDim2.fromScale(0.5, 0),
            Vector2.new(0.5, 0),
            color
        )
        Theme.label(
            slot,
            "Legende",
            entry.label,
            UDim2.new(1, 0, 0, 24),
            UDim2.fromScale(0.5, 1),
            Theme.WHITE,
            Vector2.new(0.5, 1),
            20
        )
    end
end

function Menu.open(gui: Instance): ()
    if Modal.isOpen(gui) then
        return
    end
    local player = Players.LocalPlayer
    local modal = Modal.open(gui, "NUITS", Color3.fromRGB(200, 180, 255), UDim2.fromOffset(820, 640))
    local list = Theme.scrollList(
        modal.panel,
        "Liste",
        UDim2.new(1, -40, 1, -112),
        UDim2.new(0.5, 0, 0, 92),
        Vector2.new(0.5, 0),
        10
    )

    -- Nuit actuelle : grande lune, nuit, bonus
    local top = Instance.new("Frame")
    top.Name = "NuitActuelle"
    top.LayoutOrder = 1
    top.BackgroundTransparency = 1
    top.Size = UDim2.new(1, 0, 0, 118)
    top.Parent = list
    Theme.icon(
        top,
        "Icone",
        "menuNuits",
        UDim2.fromOffset(110, 110),
        UDim2.new(0, 4, 0.5, 0),
        Vector2.new(0, 0.5),
        NIGHT_COLOR
    )
    local nightLabel = Theme.label(
        top,
        "Nuit",
        "",
        UDim2.new(1, -136, 0, 46),
        UDim2.fromOffset(126, 8),
        Theme.WHITE,
        Vector2.zero,
        36,
        Enum.TextXAlignment.Left
    )
    local _, bonusLabel = Theme.pill(
        top,
        "Bonus",
        "etoile",
        "",
        UDim2.new(0.5, 0, 0, 44),
        UDim2.fromOffset(126, 64),
        Vector2.zero,
        Theme.YELLOW,
        24
    )

    -- Progression vers la nuit suivante
    local progressRow = Theme.row(list, "Prix", 72, 2)
    Theme.icon(
        progressRow,
        "Icone",
        "tetine",
        UDim2.fromOffset(52, 52),
        UDim2.new(0, 12, 0.5, 0),
        Vector2.new(0, 0.5),
        Theme.YELLOW
    )
    local bar = Theme.progress(
        progressRow,
        "Barre",
        0,
        UDim2.new(0.6, -76, 0, 28),
        UDim2.new(0, 76, 0.5, 0),
        Vector2.new(0, 0.5),
        NIGHT_COLOR
    )
    local fill = bar:FindFirstChild("Remplissage") :: Frame
    local costLabel = Theme.label(
        progressRow,
        "Montant",
        "",
        UDim2.new(0.4, -24, 0, 36),
        UDim2.new(1, -12, 0.5, 0),
        Theme.YELLOW,
        Vector2.new(1, 0.5),
        26,
        Enum.TextXAlignment.Right
    )

    iconStrip(list, 3, "Tu perds", Theme.RED, LOST)
    iconStrip(list, 4, "Tu gardes", Theme.MINT, KEPT)

    -- Cuisine : a venir, ou debloquee a partir de la Nuit Progression.NIGHT_KITCHEN_UNLOCK (KitchenService)
    local kitchenOpen = number(player:GetAttribute("Nights")) >= Progression.NIGHT_KITCHEN_UNLOCK
    local kitchen = Theme.row(list, "Cuisine", 66, 5)
    kitchen.BackgroundColor3 = Theme.NAVY_DARK
    Theme.icon(kitchen, "Icone", "lune", UDim2.fromOffset(46, 46), UDim2.new(0, 12, 0.5, 0), Vector2.new(0, 0.5))
    Theme.label(
        kitchen,
        "Texte",
        if kitchenOpen
            then "Cuisine débloquée"
            else string.format("Cuisine : dès la nuit %d. Bientôt !", Progression.NIGHT_KITCHEN_UNLOCK),
        UDim2.new(1, -84, 0, 36),
        UDim2.new(0, 70, 0.5, 0),
        Theme.SOFT_TEXT,
        Vector2.new(0, 0.5),
        24,
        Enum.TextXAlignment.Left
    )

    -- Bouton
    local buttonRow = Instance.new("Frame")
    buttonRow.Name = "Action"
    buttonRow.LayoutOrder = 6
    buttonRow.BackgroundTransparency = 1
    buttonRow.Size = UDim2.new(1, 0, 0, 84)
    buttonRow.Parent = list
    local button = Theme.button(
        buttonRow,
        "Passer",
        "",
        Theme.GREY,
        UDim2.new(0.7, 0, 0, 70),
        UDim2.fromScale(0.5, 0.5),
        Vector2.new(0.5, 0.5)
    )
    Theme.limitText(button, 30)

    local confirming = false
    local busy = false
    local function refresh(): ()
        local nights = number(player:GetAttribute("Nights"))
        local cost = number(player:GetAttribute("NightCost"))
        local cash = number(player:GetAttribute("Cash"))
        nightLabel.Text = if nights > 0 then string.format("Nuit %d", nights) else "Première nuit"
        bonusLabel.Text = string.format(
            "+%d %% (+%d %% par nuit)",
            math.floor(nights * Progression.NIGHT_INCOME_BONUS * 100 + 0.5),
            math.floor(Progression.NIGHT_INCOME_BONUS * 100)
        )
        costLabel.Text = string.format("%s / %s", Theme.formatNumber(cash), Theme.formatNumber(cost))
        if fill then
            fill.Size = UDim2.fromScale(if cost > 0 then math.clamp(cash / cost, 0, 1) else 0, 1)
        end
        local ready = cost > 0 and cash >= cost
        button.BackgroundColor3 = if ready then (if confirming then Theme.RED else Theme.GREEN) else Theme.GREY
        button.Text = if not ready
            then "Pas assez de tétines"
            elseif confirming then "Confirmer ?"
            else string.format("Nuit %d", nights + 1)
    end
    refresh()

    local connections = {
        player:GetAttributeChangedSignal("Cash"):Connect(refresh),
        player:GetAttributeChangedSignal("Nights"):Connect(refresh),
        player:GetAttributeChangedSignal("NightCost"):Connect(refresh),
    }
    modal.root.Destroying:Connect(function()
        for _, connection in connections do
            connection:Disconnect()
        end
    end)

    button.Activated:Connect(function()
        if busy then
            return
        end
        local cost = number(player:GetAttribute("NightCost"))
        if cost <= 0 or number(player:GetAttribute("Cash")) < cost then
            return
        end
        if not confirming then
            confirming = true
            refresh()
            return
        end
        busy = true
        local ok, success, message = pcall(function()
            return (Remotes.Get("Rebirth") :: RemoteFunction):InvokeServer()
        end)
        busy = false
        confirming = false
        if not ok then
            Theme.toast(gui, "Les nuits ne répondent pas, réessaie.", Theme.RED)
        else
            local text = if typeof(message) == "string" then message else "C'est fait."
            Theme.toast(gui, text, if success == true then NIGHT_COLOR else Theme.RED)
            if success == true then
                modal.close()
                return
            end
        end
        refresh()
    end)
end

return Menu
