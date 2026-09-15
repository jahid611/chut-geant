--!strict

--[[
    RecordsController
    Tableau « Records de la nuit » accroche au mur du fond de la chambre, a gauche de la fenetre (RecordsService,
    attributs Record* de workspace). Piece locale invisible portant un SurfaceGui : une icone par record, le nom du
    detenteur et la valeur ; tiret tant que personne ne l'a battu.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

-- Records dont le joueur peut etre fier (idee 25 du carnet) : quand il en prend un, message et cadre dore qui pulse
-- sur le tableau, le temps d'une capture a partager. « Plus attrape » et la nuit calme (tout le serveur) sont exclus.
local PROUD_RECORDS: { { attribute: string, label: string } } = {
    { attribute = "RecordVolNom", label = "Plus gros vol" },
    { attribute = "RecordVolsNom", label = "Plus de jouets" },
}
local CELEBRATE_SECONDS = 6

-- Mur du fond : face interieure a z = -320 ; la fenetre occupe x = -85..85, y = 165..295. A droite de la fenetre,
-- au-dessus du coffre a jouets (haut a y = 89) : a gauche, la bibliotheque (jusqu'a y = 199) cachait le tableau.
local BOARD_POSITION = Vector3.new(262, 160, -319.4)
local BOARD_SIZE = Vector2.new(170, 104)
local PIXELS_PER_STUD = 5

type Row = { value: TextLabel, holder: TextLabel }

local RecordsController = {}

local function formatDuration(seconds: number): string
    local s = math.max(math.floor(seconds), 0)
    return string.format("%d:%02d", s // 60, s % 60)
end

local function textOf(value: any): string?
    return if typeof(value) == "string" and value ~= "" then value else nil
end

function RecordsController:Init(): () end

function RecordsController:Start(): ()
    task.spawn(function()
        local chambre = Workspace:WaitForChild("Chambre", 60)
        if chambre == nil then
            return
        end

        local board = Instance.new("Part")
        board.Name = "TableauRecords"
        board.Anchored = true
        board.CanCollide = false
        board.CanQuery = false
        board.CanTouch = false
        board.CastShadow = false
        board.Transparency = 1
        board.Size = Vector3.new(BOARD_SIZE.X, BOARD_SIZE.Y, 0.2)
        -- face avant tournee vers l'interieur de la chambre (+Z)
        board.CFrame = CFrame.lookAt(BOARD_POSITION, BOARD_POSITION + Vector3.new(0, 0, 1))
        board.Parent = Workspace

        local surface = Instance.new("SurfaceGui")
        surface.Name = "Records"
        surface.Face = Enum.NormalId.Front
        surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
        surface.PixelsPerStud = PIXELS_PER_STUD
        surface.LightInfluence = 0.25
        surface.MaxDistance = 900
        surface.Adornee = board
        surface.Parent = board

        local card = Theme.panel(surface, "Carte", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero)
        Theme.corner(card, 40)
        local cardStroke = card:FindFirstChildOfClass("UIStroke")
        if cardStroke then
            cardStroke.Thickness = 10
            cardStroke.Color = Theme.YELLOW
        end

        Theme.image(card, "Trophee", "menuClassement", UDim2.fromOffset(84, 84), UDim2.fromOffset(40, 16), Vector2.zero)
        local title = Theme.text(
            card,
            "Titre",
            "RECORDS DE LA NUIT",
            UDim2.new(1, -180, 0, 72),
            UDim2.fromOffset(140, 22),
            Theme.YELLOW,
            Vector2.zero
        )
        title.TextXAlignment = Enum.TextXAlignment.Left

        local ROW_TOP = 118
        local ROW_HEIGHT = 94
        local rows: { [string]: Row } = {}
        local function addRow(id: string, order: number, icon: string, caption: string): ()
            local top = ROW_TOP + (order - 1) * ROW_HEIGHT
            local row = Theme.row(card, "Ligne" .. id, ROW_HEIGHT - 12, order, Theme.WHITE)
            row.Size = UDim2.new(1, -56, 0, ROW_HEIGHT - 12)
            row.Position = UDim2.fromOffset(28, top)
            row.AnchorPoint = Vector2.zero
            Theme.image(row, "Icone", icon, UDim2.fromOffset(64, 64), UDim2.new(0, 14, 0.5, 0), Vector2.new(0, 0.5))
            local label = Theme.text(
                row,
                "Legende",
                caption,
                UDim2.new(0.42, -90, 0, 34),
                UDim2.fromOffset(92, 8),
                Theme.SOFT_TEXT,
                Vector2.zero
            )
            label.TextXAlignment = Enum.TextXAlignment.Left
            local holder = Theme.text(
                row,
                "Detenteur",
                "—",
                UDim2.new(0.42, -90, 0, 34),
                UDim2.fromOffset(92, 42),
                Theme.WHITE,
                Vector2.zero
            )
            holder.TextXAlignment = Enum.TextXAlignment.Left
            local value = Theme.text(
                row,
                "Valeur",
                "—",
                UDim2.new(0.58, -24, 0, 60),
                UDim2.new(1, -18, 0.5, 0),
                Theme.YELLOW,
                Vector2.new(1, 0.5)
            )
            value.TextXAlignment = Enum.TextXAlignment.Right
            rows[id] = { value = value, holder = holder }
        end
        addRow("Vol", 1, "boutonMesJouets", "Plus gros vol")
        addRow("Calme", 2, "bebeDort", "Nuit la plus calme")
        addRow("Vols", 3, "tetine", "Plus de jouets")
        addRow("Propulsions", 4, "pouvoirDoudou", "Plus attrapé")

        local function refresh(): ()
            local vol = rows.Vol
            local volName = textOf(Workspace:GetAttribute("RecordVolNom"))
            local toyName = textOf(Workspace:GetAttribute("RecordVolJouet"))
            local income = Workspace:GetAttribute("RecordVolRevenu")
            vol.holder.Text = volName or "—"
            vol.value.Text = if toyName and typeof(income) == "number"
                then string.format("%s  %s/s", toyName, Theme.formatNumber(income))
                else "—"

            local calm = Workspace:GetAttribute("RecordCalme")
            rows.Calme.holder.Text = "Tout le serveur"
            rows.Calme.value.Text = if typeof(calm) == "number" then formatDuration(calm) else "—"

            for _, id in { "Vols", "Propulsions" } do
                local count = Workspace:GetAttribute("Record" .. id)
                rows[id].holder.Text = textOf(Workspace:GetAttribute("Record" .. id .. "Nom")) or "—"
                rows[id].value.Text = if typeof(count) == "number" then Theme.formatNumber(count) else "—"
            end
        end

        for _, name in
            {
                "RecordVolNom",
                "RecordVolJouet",
                "RecordVolRevenu",
                "RecordCalme",
                "RecordVols",
                "RecordVolsNom",
                "RecordPropulsions",
                "RecordPropulsionsNom",
            }
        do
            Workspace:GetAttributeChangedSignal(name):Connect(refresh)
        end
        refresh()

        -- Nouveau record du joueur : message, son et cadre dore qui pulse CELEBRATE_SECONDS secondes.
        local screen = Instance.new("ScreenGui")
        screen.Name = "NouveauRecord"
        screen.ResetOnSpawn = false
        screen.IgnoreGuiInset = true
        screen.DisplayOrder = 7
        screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
        local celebrateToken = 0
        local function celebrate(label: string): ()
            celebrateToken += 1
            local token = celebrateToken
            Sfx.play("fanfare")
            Theme.toast(screen, "Nouveau record : " .. label .. " ! Va poser devant le tableau", Theme.YELLOW)
            if cardStroke == nil then
                return
            end
            local stroke = cardStroke
            task.spawn(function()
                local started = os.clock()
                while token == celebrateToken and os.clock() - started < CELEBRATE_SECONDS do
                    TweenService:Create(stroke, TweenInfo.new(0.45), { Thickness = 22, Color = Theme.WHITE }):Play()
                    task.wait(0.45)
                    TweenService:Create(stroke, TweenInfo.new(0.45), { Thickness = 10, Color = Theme.YELLOW }):Play()
                    task.wait(0.45)
                end
            end)
        end
        local myName = Players.LocalPlayer.DisplayName
        for _, record in PROUD_RECORDS do
            local previous = textOf(Workspace:GetAttribute(record.attribute))
            Workspace:GetAttributeChangedSignal(record.attribute):Connect(function()
                local holder = textOf(Workspace:GetAttribute(record.attribute))
                -- seulement quand le record passe au joueur (pas a chaque nouveau depot s'il le detient deja)
                if holder == myName and previous ~= myName then
                    celebrate(record.label)
                end
                previous = holder
            end)
        end
    end)
end

return RecordsController
