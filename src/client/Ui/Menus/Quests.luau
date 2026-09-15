--!strict

--[[
    Menu « Quêtes » (colonne de gauche, MenuController) : 3 quetes du jour et 3 de la semaine. Etat lu dans
    l'attribut joueur Quests_State (JSON pose par QuestService), redessine a chaque changement.

    Mise en page (retour utilisateur : les lignes depassaient du panneau, et tout etait en texte) : liste
    defilante qui coupe au bord du panneau ; chaque quete = icone de son type | libelle + barre | recompenses en
    pastilles (tetine, etoile = XP) | bouton court. Largeurs en proportion de la ligne.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Retention = require(Shared:WaitForChild("Retention"))

local Modal = require(script.Parent.Parent:WaitForChild("Modal"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local ROW_HEIGHT = 96

-- Icone de chaque type de quete (stat du modele Retention.QUESTS).
local STAT_ICON: { [string]: string } = {
    stolen = "boutonMesJouets",
    stolenRare = "etoile",
    stolenHeavy = "lourd",
    playSeconds = "lune",
    cashEarned = "tetine",
    thrown = "pouvoirHochet",
    momSurvived = "bebeDort",
    pacifierStolen = "pouvoirTetine",
}

local Menu = {}

local function readState(): any
    local raw = Players.LocalPlayer:GetAttribute("Quests_State")
    if typeof(raw) ~= "string" then
        return nil
    end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    return if ok then decoded else nil
end

-- Le serveur n'envoie que le libelle : on retrouve le type de quete en le comparant aux modeles (« %d » = nombre).
local function iconFor(label: string): string
    for _, template in Retention.QUESTS do
        local pattern = "^" .. (string.gsub(template.label, "%%d", "%%d+")) .. "$"
        if string.match(label, pattern) then
            return STAT_ICON[template.stat] or "menuQuetes"
        end
    end
    return "menuQuetes"
end

function Menu.open(gui: Instance): ()
    if Modal.isOpen(gui) then
        return
    end
    local player = Players.LocalPlayer
    local modal = Modal.open(gui, "QUÊTES", Theme.WHITE, UDim2.fromOffset(900, 640))
    Theme.icon(
        modal.panel,
        "IconeTitre",
        "menuQuetes",
        UDim2.fromOffset(62, 62),
        UDim2.new(0.2, -6, 0, 16),
        Vector2.new(1, 0),
        Theme.PINK
    )
    local list = Theme.scrollList(
        modal.panel,
        "Liste",
        UDim2.new(1, -40, 1, -112),
        UDim2.new(0.5, 0, 0, 92),
        Vector2.new(0.5, 0),
        10
    )

    local render: () -> ()
    local order = 0
    local function nextOrder(): number
        order += 1
        return order
    end

    local function claim(key: string, button: TextButton): ()
        button.Text = "..."
        local ok, success, message = pcall(function()
            return (Remotes.Get("ClaimQuest") :: RemoteFunction):InvokeServer(key)
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

    local function header(title: string, iconKey: string, color: Color3, resetAt: number): ()
        local frame = Instance.new("Frame")
        frame.Name = "Entete"
        frame.LayoutOrder = nextOrder()
        frame.BackgroundTransparency = 1
        frame.Size = UDim2.new(1, 0, 0, 50)
        frame.Parent = list
        Theme.icon(
            frame,
            "Icone",
            iconKey,
            UDim2.fromOffset(44, 44),
            UDim2.new(0, 2, 0.5, 0),
            Vector2.new(0, 0.5),
            color
        )
        Theme.label(
            frame,
            "Titre",
            title,
            UDim2.new(0.5, -60, 0, 36),
            UDim2.new(0, 56, 0.5, 0),
            color,
            Vector2.new(0, 0.5),
            30,
            Enum.TextXAlignment.Left
        )
        -- minuteur : lune + temps avant les nouvelles quetes
        Theme.pill(
            frame,
            "Minuteur",
            "lune",
            Retention.FormatDuration(resetAt - Workspace:GetServerTimeNow()),
            UDim2.new(0.3, 0, 0, 38),
            UDim2.new(1, -4, 0.5, 0),
            Vector2.new(1, 0.5),
            Theme.SOFT_TEXT,
            22
        )
    end

    local function row(quest: any, cash: number, xp: number): ()
        local done = quest.done == true
        local claimed = quest.claimed == true
        local ready = done and not claimed
        local label = tostring(quest.label)
        local progress = tonumber(quest.progress) or 0
        local target = math.max(tonumber(quest.target) or 1, 1)
        local fraction = math.clamp(progress / target, 0, 1)

        local frame = Theme.row(list, "Quete", ROW_HEIGHT, nextOrder(), if ready then Theme.YELLOW else nil)

        -- type de quete
        local badge = Instance.new("Frame")
        badge.Name = "Type"
        badge.BackgroundColor3 = Theme.NAVY_DARK
        badge.BorderSizePixel = 0
        badge.Size = UDim2.fromOffset(72, 72)
        badge.Position = UDim2.new(0, 12, 0.5, 0)
        badge.AnchorPoint = Vector2.new(0, 0.5)
        badge.Parent = frame
        Theme.corner(badge, 36)
        Theme.icon(
            badge,
            "Icone",
            iconFor(label),
            UDim2.fromScale(0.78, 0.78),
            UDim2.fromScale(0.5, 0.5),
            Vector2.new(0.5, 0.5),
            Theme.MINT
        )

        -- libelle + barre + avancee : de 96 px a 55 % de la ligne
        Theme.label(
            frame,
            "Libelle",
            label,
            UDim2.new(0.55, -104, 0, 34),
            UDim2.fromOffset(96, 12),
            Theme.WHITE,
            Vector2.zero,
            26,
            Enum.TextXAlignment.Left
        )
        Theme.progress(
            frame,
            "Barre",
            fraction,
            UDim2.new(0.42, -104, 0, 18),
            UDim2.fromOffset(96, 62),
            Vector2.zero,
            if done then Theme.GREEN else Theme.MINT
        )
        Theme.label(
            frame,
            "Avancee",
            string.format("%d / %d", progress, target),
            UDim2.new(0.13, -8, 0, 26),
            UDim2.new(0.42, 0, 0, 58),
            Theme.SOFT_TEXT,
            Vector2.zero,
            20,
            Enum.TextXAlignment.Left
        )

        -- recompenses : tetines et XP (etoile)
        Theme.pill(
            frame,
            "Tetines",
            "tetine",
            "+" .. Theme.formatNumber(cash),
            UDim2.new(0.21, 0, 0, 36),
            UDim2.new(0.565, 0, 0, 10),
            Vector2.zero,
            Theme.YELLOW,
            22
        )
        Theme.pill(
            frame,
            "XP",
            "etoile",
            string.format("+%d XP", xp),
            UDim2.new(0.21, 0, 0, 36),
            UDim2.new(0.565, 0, 0, 50),
            Vector2.zero,
            Theme.PINK,
            22
        )

        -- bouton court : Prendre / Pris / pourcentage en cours
        local text = if claimed
            then "Pris"
            elseif done then "Prendre"
            else string.format("%d %%", math.floor(fraction * 100))
        local button = Theme.button(
            frame,
            "Recuperer",
            text,
            if ready then Theme.GREEN elseif claimed then Theme.MINT else Theme.GREY,
            UDim2.new(0.19, 0, 0, 60),
            UDim2.new(1, -12, 0.5, 0),
            Vector2.new(1, 0.5)
        )
        Theme.limitText(button, 28)
        if ready then
            button.Activated:Connect(function()
                claim(tostring(quest.key), button)
            end)
        end
    end

    render = function(): ()
        for _, child in list:GetChildren() do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
        order = 0
        local state = readState()
        if state == nil then
            local loading = Theme.label(
                list,
                "Chargement",
                "Chargement des quêtes...",
                UDim2.new(1, 0, 0, 50),
                UDim2.fromScale(0, 0),
                Theme.SOFT_TEXT,
                Vector2.zero,
                28
            )
            loading.LayoutOrder = 1
            return
        end
        local daily = Retention.QUEST_REWARD.daily
        local weekly = Retention.QUEST_REWARD.weekly
        header("Du jour", "menuQuetes", Theme.PINK, tonumber(state.dailyResetAt) or 0)
        if typeof(state.daily) == "table" then
            for _, quest in state.daily do
                row(quest, daily.cash, daily.xp)
            end
        end
        header("De la semaine", "etoile", Theme.YELLOW, tonumber(state.weeklyResetAt) or 0)
        if typeof(state.weekly) == "table" then
            for _, quest in state.weekly do
                row(quest, weekly.cash, weekly.xp)
            end
        end
    end

    render()
    local connection = player:GetAttributeChangedSignal("Quests_State"):Connect(render)
    modal.root.Destroying:Connect(function()
        connection:Disconnect()
    end)
end

return Menu
