--!strict

--[[
    Menu « Pass de saison » (colonne de gauche, MenuController) : palier actuel et barre d'XP, puis les 30 paliers
    cote a cote (defilement horizontal). Piste gratuite : tetines ou cosmetique (paliers 10, 20, 30), bouton Prendre.
    Piste premium : verrouillee, « Bientôt ». Etat lu dans l'attribut joueur Pass_State (JSON de PassService).

    Mise en page : tout vit dans des zones qui coupent au bord du panneau ; chaque palier est une colonne en
    proportion de la hauteur disponible, avec l'icone de la recompense (tetine ou icone du cosmetique).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Retention = require(Shared:WaitForChild("Retention"))

local Modal = require(script.Parent.Parent:WaitForChild("Modal"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local COLUMN_WIDTH = 150
local COLUMN_GAP = 12

local Menu = {}

local function readState(): any
    local raw = Players.LocalPlayer:GetAttribute("Pass_State")
    if typeof(raw) ~= "string" then
        return nil
    end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    return if ok then decoded else nil
end

local function card(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.BackgroundColor3 = Theme.NAVY_LIGHT
    frame.BorderSizePixel = 0
    frame.Position = position
    frame.Size = size
    frame.ClipsDescendants = true
    frame.Parent = parent
    Theme.corner(frame, 16)
    Theme.stroke(frame, 2, color)
    return frame
end

function Menu.open(gui: Instance): ()
    if Modal.isOpen(gui) then
        return
    end
    local player = Players.LocalPlayer
    local modal = Modal.open(gui, "PASS DE SAISON", Theme.WHITE, UDim2.fromOffset(1000, 640))
    local panel = modal.panel
    Theme.icon(
        panel,
        "IconeTitre",
        "menuPass",
        UDim2.fromOffset(62, 62),
        UDim2.new(0.2, -6, 0, 16),
        Vector2.new(1, 0),
        Theme.YELLOW
    )

    local header = Instance.new("Frame")
    header.Name = "Entete"
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, -40, 0, 84)
    header.Position = UDim2.new(0.5, 0, 0, 90)
    header.AnchorPoint = Vector2.new(0.5, 0)
    header.ClipsDescendants = true
    header.Parent = panel

    local scroller = Instance.new("ScrollingFrame")
    scroller.Name = "Paliers"
    scroller.BackgroundTransparency = 1
    scroller.BorderSizePixel = 0
    scroller.Size = UDim2.new(1, -40, 1, -204)
    scroller.Position = UDim2.new(0.5, 0, 0, 184)
    scroller.AnchorPoint = Vector2.new(0.5, 0)
    scroller.ClipsDescendants = true
    scroller.ScrollingDirection = Enum.ScrollingDirection.X
    scroller.AutomaticCanvasSize = Enum.AutomaticSize.X
    scroller.CanvasSize = UDim2.new()
    scroller.ScrollBarThickness = 8
    scroller.ScrollBarImageColor3 = Theme.SOFT_TEXT
    scroller.HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar
    scroller.Parent = panel
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, COLUMN_GAP)
    layout.Parent = scroller
    local inner = Instance.new("UIPadding")
    inner.PaddingLeft = UDim.new(0, 4)
    inner.PaddingRight = UDim.new(0, 4)
    inner.PaddingTop = UDim.new(0, 2)
    inner.Parent = scroller

    local render: () -> ()
    local firstRender = true

    local function claim(tier: number, button: TextButton): ()
        button.Text = "..."
        local ok, success, message = pcall(function()
            return (Remotes.Get("ClaimPass") :: RemoteFunction):InvokeServer(tier, false)
        end)
        if not ok then
            Theme.toast(gui, "Le serveur ne répond pas, réessaie.", Theme.RED)
        else
            Theme.toast(
                gui,
                if typeof(message) == "string" then message else "C'est fait !",
                if success == true then Theme.GREEN else Theme.RED
            )
        end
        render()
    end

    render = function(): ()
        for _, child in header:GetChildren() do
            child:Destroy()
        end
        for _, child in scroller:GetChildren() do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
        local state = readState()
        local xp = if state then tonumber(state.xp) or 0 else 0
        local claimed: { [number]: boolean } = {}
        if state and typeof(state.claimed) == "table" then
            for _, tier in state.claimed do
                local n = tonumber(tier)
                if n then
                    claimed[n] = true
                end
            end
        end
        local tier = math.min(math.floor(xp / Retention.PASS_XP_PER_TIER), Retention.PASS_TIERS)
        local maxed = tier >= Retention.PASS_TIERS
        local inTier = if maxed then Retention.PASS_XP_PER_TIER else xp % Retention.PASS_XP_PER_TIER

        -- en-tete : etoile + palier, barre d'XP, legende des deux pistes
        Theme.icon(header, "Etoile", "etoile", UDim2.fromOffset(66, 66), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5))
        Theme.label(
            header,
            "Palier",
            string.format("Palier %d / %d", tier, Retention.PASS_TIERS),
            UDim2.new(0.3, -80, 0, 40),
            UDim2.fromOffset(76, 4),
            Theme.WHITE,
            Vector2.zero,
            32,
            Enum.TextXAlignment.Left
        )
        Theme.label(
            header,
            "Saison",
            string.format("Saison %d", Retention.PASS_SEASON),
            UDim2.new(0.3, -80, 0, 28),
            UDim2.fromOffset(76, 48),
            Theme.SOFT_TEXT,
            Vector2.zero,
            22,
            Enum.TextXAlignment.Left
        )
        Theme.progress(
            header,
            "BarreXP",
            inTier / Retention.PASS_XP_PER_TIER,
            UDim2.new(0.42, 0, 0, 24),
            UDim2.new(0.31, 0, 0, 12),
            Vector2.zero,
            Theme.PINK
        )
        Theme.pill(
            header,
            "XP",
            "etoile",
            if maxed then "Terminé !" else string.format("%d / %d XP", inTier, Retention.PASS_XP_PER_TIER),
            UDim2.new(0.24, 0, 0, 34),
            UDim2.new(0.31, 0, 0, 46),
            Vector2.zero,
            Theme.PINK,
            22
        )
        Theme.pill(
            header,
            "Gratuit",
            "tetine",
            "Gratuit",
            UDim2.new(0.2, 0, 0, 34),
            UDim2.new(1, 0, 0, 4),
            Vector2.new(1, 0),
            Theme.MINT,
            22
        )
        Theme.pill(
            header,
            "Premium",
            "etoile",
            "Premium",
            UDim2.new(0.2, 0, 0, 34),
            UDim2.new(1, 0, 0, 46),
            Vector2.new(1, 0),
            Theme.YELLOW,
            22
        )

        for t = 1, Retention.PASS_TIERS do
            local column = Instance.new("Frame")
            column.Name = "Palier" .. t
            column.LayoutOrder = t
            column.BackgroundTransparency = 1
            column.Size = UDim2.new(0, COLUMN_WIDTH, 1, -12)
            column.Parent = scroller

            local reached = t <= tier
            local bubble = Instance.new("Frame")
            bubble.Name = "Numero"
            bubble.BackgroundColor3 = if claimed[t] then Theme.MINT elseif reached then Theme.PINK else Theme.GREY
            bubble.BorderSizePixel = 0
            bubble.Size = UDim2.fromOffset(52, 52)
            bubble.Position = UDim2.new(0.5, 0, 0, 2)
            bubble.AnchorPoint = Vector2.new(0.5, 0)
            bubble.Parent = column
            Theme.corner(bubble, 26)
            Theme.stroke(bubble, 3, Theme.WHITE)
            Theme.label(
                bubble,
                "Texte",
                tostring(t),
                UDim2.new(1, -14, 1, -14),
                UDim2.fromScale(0.5, 0.5),
                Theme.WHITE,
                Vector2.new(0.5, 0.5),
                26
            )

            -- piste gratuite : icone de la recompense, montant ou nom, bouton
            local cosmeticId = Retention.PASS_COSMETICS[t]
            local item = if cosmeticId then Catalog.Get(cosmeticId) else nil
            local free = card(
                column,
                "Gratuit",
                UDim2.fromOffset(0, 62),
                UDim2.new(1, 0, 0.55, -62),
                if item then Theme.YELLOW else Theme.MINT
            )
            Theme.icon(
                free,
                "Icone",
                if item then item.icon else "tetine",
                UDim2.fromScale(0.6, 0.38),
                UDim2.fromScale(0.5, 0.05),
                Vector2.new(0.5, 0),
                Theme.YELLOW
            )
            Theme.label(
                free,
                "Recompense",
                if item then item.name else "+" .. Theme.formatNumber(Retention.PassFreeCash(t)),
                UDim2.new(1, -14, 0.17, 0),
                UDim2.fromScale(0.5, 0.45),
                if item then Theme.YELLOW else Theme.WHITE,
                Vector2.new(0.5, 0),
                22
            )
            local button = Theme.button(
                free,
                "Prendre",
                if claimed[t] then "Pris" elseif reached then "Prendre" else "Bloqué",
                if claimed[t] then Theme.MINT elseif reached then Theme.GREEN else Theme.GREY,
                UDim2.new(1, -18, 0.28, 0),
                UDim2.fromScale(0.5, 0.96),
                Vector2.new(0.5, 1)
            )
            Theme.limitText(button, 24)
            if reached and not claimed[t] then
                button.Activated:Connect(function()
                    claim(t, button)
                end)
            end

            -- piste premium : verrouillee
            local premium = card(
                column,
                "Premium",
                UDim2.new(0, 0, 0.55, 8),
                UDim2.new(1, 0, 0.45, -8),
                Color3.fromRGB(120, 140, 210)
            )
            premium.BackgroundTransparency = 0.35
            local star = Theme.icon(
                premium,
                "Icone",
                "etoile",
                UDim2.fromScale(0.5, 0.4),
                UDim2.fromScale(0.5, 0.08),
                Vector2.new(0.5, 0)
            )
            if star:IsA("ImageLabel") then
                star.ImageTransparency = 0.5
            end
            Theme.label(
                premium,
                "Bientot",
                "Bientôt",
                UDim2.new(1, -20, 0.22, 0),
                UDim2.fromScale(0.5, 0.92),
                Theme.GREY,
                Vector2.new(0.5, 1),
                22
            )
        end

        if firstRender then
            firstRender = false
            scroller.CanvasPosition = Vector2.new(math.max(tier - 2, 0) * (COLUMN_WIDTH + COLUMN_GAP), 0)
        end
    end

    render()
    local connection = player:GetAttributeChangedSignal("Pass_State"):Connect(render)
    modal.root.Destroying:Connect(function()
        connection:Disconnect()
    end)
end

return Menu
