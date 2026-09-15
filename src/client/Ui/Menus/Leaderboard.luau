--!strict

--[[
    Menu « Classement » (LeaderboardService, SocialService)
    Deux colonnes : les joueurs du serveur (jouets voles cette session, total) et les plus gros voleurs du monde
    (OrderedDataStore). En bas, le bonus de revenu pour jouer avec ses amis. Lit ReplicatedStorage.Classement (JSON)
    et se met a jour tant que le menu est ouvert.

    Mise en page : colonnes en proportion du panneau, listes defilantes qui coupent au bord ; rang en medaille
    (or, argent, bronze), valeur en pastille avec icone.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))

local Modal = require(script.Parent.Parent:WaitForChild("Modal"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local ROW_HEIGHT = 50
local MAX_ROWS = 10
local MEDALS = {
    Color3.fromRGB(255, 200, 40),
    Color3.fromRGB(200, 210, 225),
    Color3.fromRGB(215, 140, 80),
}

local Menu = {}

local function number(value: any): number
    return if typeof(value) == "number" then value else 0
end

local function column(parent: Instance, name: string, title: string, iconKey: string, left: boolean): ScrollingFrame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.BackgroundColor3 = Theme.NAVY_LIGHT
    frame.BorderSizePixel = 0
    frame.Size = UDim2.new(0.5, -8, 1, -74)
    frame.Position = if left then UDim2.fromScale(0, 0) else UDim2.new(0.5, 8, 0, 0)
    frame.ClipsDescendants = true
    frame.Parent = parent
    Theme.corner(frame, 20)
    Theme.stroke(frame, 2, Color3.fromRGB(120, 140, 210))
    Theme.icon(frame, "Icone", iconKey, UDim2.fromOffset(44, 44), UDim2.fromOffset(12, 8), Vector2.zero, Theme.YELLOW)
    Theme.label(
        frame,
        "Titre",
        title,
        UDim2.new(1, -80, 0, 38),
        UDim2.fromOffset(64, 11),
        Theme.YELLOW,
        Vector2.zero,
        28,
        Enum.TextXAlignment.Left
    )
    return Theme.scrollList(
        frame,
        "Lignes",
        UDim2.new(1, -16, 1, -66),
        UDim2.new(0.5, 0, 0, 60),
        Vector2.new(0.5, 0),
        6
    )
end

local function row(parent: Instance, index: number, name: string, value: string, highlight: boolean): ()
    local frame = Theme.row(parent, "Ligne" .. index, ROW_HEIGHT, index, if highlight then Theme.MINT else nil)
    frame.BackgroundColor3 = Theme.NAVY
    local medal = Instance.new("Frame")
    medal.Name = "Rang"
    medal.BackgroundColor3 = MEDALS[index] or Theme.NAVY_DARK
    medal.BorderSizePixel = 0
    medal.Size = UDim2.fromOffset(38, 38)
    medal.Position = UDim2.new(0, 6, 0.5, 0)
    medal.AnchorPoint = Vector2.new(0, 0.5)
    medal.Parent = frame
    Theme.corner(medal, 19)
    Theme.stroke(medal, 2, Theme.WHITE)
    Theme.label(
        medal,
        "Numero",
        tostring(index),
        UDim2.new(1, -10, 1, -10),
        UDim2.fromScale(0.5, 0.5),
        Theme.WHITE,
        Vector2.new(0.5, 0.5),
        22
    )
    Theme.label(
        frame,
        "Nom",
        name,
        UDim2.new(0.56, -56, 0, 30),
        UDim2.new(0, 52, 0.5, 0),
        if highlight then Theme.MINT else Theme.WHITE,
        Vector2.new(0, 0.5),
        22,
        Enum.TextXAlignment.Left
    )
    Theme.pill(
        frame,
        "Valeur",
        "boutonMesJouets",
        value,
        UDim2.new(0.42, -8, 0, 36),
        UDim2.new(1, -6, 0.5, 0),
        Vector2.new(1, 0.5),
        Theme.YELLOW,
        20
    )
end

function Menu.open(gui: Instance): ()
    if Modal.isOpen(gui) then
        return
    end
    local player = Players.LocalPlayer
    player:SetAttribute("Notif_Classement", false)
    local modal = Modal.open(gui, "CLASSEMENT", Theme.WHITE, UDim2.fromOffset(960, 660))
    Theme.icon(
        modal.panel,
        "IconeTitre",
        "menuClassement",
        UDim2.fromOffset(62, 62),
        UDim2.new(0.2, -6, 0, 16),
        Vector2.new(1, 0),
        Theme.YELLOW
    )
    local body = Modal.body(modal, 92, 20)

    local serverRows = column(body, "Serveur", "Ce serveur", "boutonMesJouets", true)
    local globalRows = column(body, "Monde", "Plus gros voleurs", "menuClassement", false)

    local socialRow = Instance.new("Frame")
    socialRow.Name = "Social"
    socialRow.BackgroundColor3 = Theme.NAVY_DARK
    socialRow.BorderSizePixel = 0
    socialRow.Size = UDim2.new(1, 0, 0, 62)
    socialRow.Position = UDim2.fromScale(0, 1)
    socialRow.AnchorPoint = Vector2.new(0, 1)
    socialRow.ClipsDescendants = true
    socialRow.Parent = body
    Theme.corner(socialRow, 18)
    Theme.icon(
        socialRow,
        "Icone",
        "menuAmis",
        UDim2.fromOffset(48, 48),
        UDim2.new(0, 10, 0.5, 0),
        Vector2.new(0, 0.5),
        Theme.MINT
    )
    local social = Theme.label(
        socialRow,
        "Texte",
        "",
        UDim2.new(1, -84, 0, 36),
        UDim2.new(0, 70, 0.5, 0),
        Theme.MINT,
        Vector2.new(0, 0.5),
        24,
        Enum.TextXAlignment.Left
    )

    local function clear(container: Instance): ()
        for _, child in container:GetChildren() do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
    end

    local function render(): ()
        local value = ReplicatedStorage:FindFirstChild("Classement")
        local state: any = nil
        if value and value:IsA("StringValue") then
            local ok, decoded = pcall(function()
                return HttpService:JSONDecode(value.Value)
            end)
            if ok then
                state = decoded
            end
        end
        clear(serverRows)
        clear(globalRows)
        local servers = if typeof(state) == "table" and typeof(state.server) == "table" then state.server else {}
        for i, entry in servers do
            if i > MAX_ROWS then
                break
            end
            row(
                serverRows,
                i,
                tostring(entry.name)
                    .. (if number(entry.nights) > 0 then string.format(" (nuit %d)", number(entry.nights)) else ""),
                string.format("%d (%s)", number(entry.session), Theme.formatNumber(number(entry.total))),
                number(entry.userId) == player.UserId
            )
        end
        local globals = if typeof(state) == "table" and typeof(state.global) == "table" then state.global else {}
        if #globals == 0 then
            local empty = Theme.label(
                globalRows,
                "Vide",
                "Bientôt disponible",
                UDim2.new(1, 0, 0, 40),
                UDim2.fromScale(0, 0),
                Theme.SOFT_TEXT,
                Vector2.zero,
                24
            )
            empty.LayoutOrder = 1
        end
        for i, entry in globals do
            if i > MAX_ROWS then
                break
            end
            row(
                globalRows,
                i,
                tostring(entry.name),
                Theme.formatNumber(number(entry.total)),
                number(entry.userId) == player.UserId
            )
        end

        local friends = number(player:GetAttribute("FriendsHere"))
        local bonus = number(player:GetAttribute("SocialBonus"))
        social.Text = if bonus > 0
            then string.format(
                "+%d %% de tétines (%d ami%s ici)",
                math.floor(bonus * 100 + 0.5),
                friends,
                if friends > 1 then "s" else ""
            )
            else string.format(
                "Invite tes amis : +%d %% par ami (%d au plus)",
                math.floor(Progression.FRIEND_BONUS * 100),
                Progression.FRIEND_MAX
            )
    end
    render()

    local connections: { RBXScriptConnection } = {}
    local value = ReplicatedStorage:FindFirstChild("Classement")
    if value and value:IsA("StringValue") then
        table.insert(connections, value.Changed:Connect(render))
    end
    table.insert(connections, player:GetAttributeChangedSignal("SocialBonus"):Connect(render))
    modal.root.Destroying:Connect(function()
        for _, connection in connections do
            connection:Disconnect()
        end
    end)
end

return Menu
