--!strict

-- Lecture d'attributs uniquement : classement et fermeture du bilan sont des actions locales.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modal = require(script.Parent.Parent.Ui.Modal)
local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tuning"))

type Row = { userId: number, name: string, count: number, rank: number }
type Snapshot = {
    id: number,
    revision: number,
    phase: string,
    endsAt: number,
    goal: number,
    total: number,
    won: boolean,
    resultReady: boolean,
    finale: boolean,
    rows: { Row },
}
type Personal = { id: number, revision: number, count: number, rank: number, cash: number, xp: number }

local RoundController = {}
local player = Players.LocalPlayer

local function decode(raw: any): any
    if typeof(raw) ~= "string" then
        return nil
    end
    local ok, value = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    return if ok and typeof(value) == "table" then value else nil
end

function RoundController:Init(): () end

function RoundController:Start(): ()
    local playerGui = player:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "Manches"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 7
    gui.Parent = playerGui
    local modalGui = Instance.new("ScreenGui")
    modalGui.Name = "BilanManche"
    modalGui.ResetOnSpawn = false
    modalGui.IgnoreGuiInset = true
    modalGui.DisplayOrder = 15
    modalGui.Parent = playerGui

    local bar = Theme.panel(gui, "BarreManche", UDim2.fromOffset(400, 76), UDim2.fromScale(0.5, 1), Vector2.new(0.5, 1))
    bar.ClipsDescendants = true
    local scale = Instance.new("UIScale")
    scale.Parent = bar
    Theme.icon(bar, "Jouet", "boutonMesJouets", UDim2.fromOffset(42, 42), UDim2.fromOffset(8, 18), Vector2.zero)
    local title = Theme.label(
        bar,
        "Phase",
        "Ensemble, ramenez les jouets !",
        UDim2.fromOffset(260, 21),
        UDim2.fromOffset(56, 6),
        Theme.YELLOW,
        Vector2.zero,
        16
    )
    local score = Theme.label(
        bar,
        "Score",
        "0 / 6",
        UDim2.fromOffset(92, 27),
        UDim2.fromOffset(56, 28),
        Theme.WHITE,
        Vector2.zero,
        22
    )
    local clock = Theme.label(
        bar,
        "Chrono",
        "05:00",
        UDim2.fromOffset(76, 27),
        UDim2.fromOffset(153, 28),
        Theme.WHITE,
        Vector2.zero,
        22
    )
    local mine = Theme.label(
        bar,
        "Contribution",
        "Toi : 0",
        UDim2.fromOffset(90, 27),
        UDim2.fromOffset(234, 28),
        Theme.SOFT_TEXT,
        Vector2.zero,
        17
    )
    local progress = Theme.progress(
        bar,
        "Progression",
        0,
        UDim2.fromOffset(264, 8),
        UDim2.fromOffset(56, 60),
        Vector2.zero,
        Theme.MINT
    )
    local fill = progress:FindFirstChild("Remplissage") :: Frame
    local button =
        Theme.roundImageButton(bar, "Classement", "menuClassement", UDim2.fromOffset(48, 48), UDim2.fromOffset(340, 5))
    Theme.label(
        bar,
        "Bilan",
        "Classement",
        UDim2.fromOffset(72, 16),
        UDim2.fromOffset(324, 55),
        Theme.SOFT_TEXT,
        Vector2.zero,
        12
    )

    local snapshot: Snapshot? = nil
    local personal: Personal? = nil
    local modal: Modal.Modal? = nil
    local body: Frame? = nil
    local modalSignature = ""
    local shownResult = -1
    local heardResult = -1
    local lastTick = ""

    local function blocked(): boolean
        local menus = player:GetAttribute("MenusOuverts")
        local camera = workspace.CurrentCamera
        return (typeof(menus) == "number" and menus > 0)
            or player:GetAttribute("VueCoffre") == true
            or (camera ~= nil and camera.CameraType == Enum.CameraType.Scriptable)
    end

    local function eventVisible(): boolean
        for _, pair in { { "Evenements", "BandeauEvenement" }, { "EvenementsCuisine", "BandeauCuisine" } } do
            local screen = playerGui:FindFirstChild(pair[1])
            local banner = if screen then screen:FindFirstChild(pair[2]) else nil
            if
                screen
                and screen:IsA("ScreenGui")
                and screen.Enabled
                and banner
                and banner:IsA("GuiObject")
                and banner.Visible
            then
                return true
            end
        end
        return false
    end

    local function closeModal(): ()
        local opened = modal
        if opened then
            opened.close()
        end
        modal = nil
        body = nil
        modalSignature = ""
    end

    local function renderModal(): ()
        local s, p, opened = snapshot, personal, modal
        if s == nil or p == nil or opened == nil or not opened.root.Parent then
            return
        end
        local signature = HttpService:JSONEncode({
            id = s.id,
            phase = s.phase,
            total = s.total,
            rows = s.rows,
            count = p.count,
            rank = p.rank,
            cash = p.cash,
            xp = p.xp,
        })
        if s.resultReady then
            shownResult = s.id
        end
        if signature == modalSignature then
            return
        end
        modalSignature = signature
        if body then
            body:Destroy()
        end
        local content = Modal.body(opened)
        body = content
        local isResult = s.phase == "Résultat" or s.phase == "Pause"
        local heading = opened.panel:FindFirstChild("Titre")
        if heading and heading:IsA("TextLabel") then
            heading.Text = if isResult then (if s.won then "BRAVO L'ÉQUIPE !" else "OBJECTIF RATÉ") else "LA MANCHE"
            heading.TextColor3 = if isResult and not s.won then Theme.PINK else Theme.YELLOW
        end
        Theme.label(
            content,
            "Collectif",
            string.format("Ensemble : %d / %d jouets", s.total, s.goal),
            UDim2.new(1, 0, 0, 32),
            UDim2.fromOffset(0, 0),
            Theme.WHITE,
            Vector2.zero,
            26
        )
        Theme.label(
            content,
            "Personnel",
            string.format("Toi : %d jouets  |  Rang : %s", p.count, if p.rank > 0 then tostring(p.rank) else "—"),
            UDim2.new(1, 0, 0, 28),
            UDim2.fromOffset(0, 38),
            Theme.SOFT_TEXT,
            Vector2.zero,
            21
        )
        if isResult then
            Theme.icon(content, "Prime", "tetine", UDim2.fromOffset(32, 32), UDim2.new(0.08, 0, 0, 74), Vector2.zero)
            Theme.label(
                content,
                "Montants",
                string.format("+%s tétines   +%d XP", Theme.formatNumber(p.cash), p.xp),
                UDim2.new(0.78, 0, 0, 32),
                UDim2.new(0.18, 0, 0, 74),
                Theme.MINT,
                Vector2.zero,
                22
            )
        else
            Theme.label(
                content,
                "Regle",
                "Ramène des jouets du monde dans ta base.",
                UDim2.new(1, 0, 0, 32),
                UDim2.fromOffset(0, 74),
                Theme.MINT,
                Vector2.zero,
                20
            )
        end
        local list = Theme.scrollList(
            content,
            "Contributions",
            UDim2.new(1, 0, 1, -120),
            UDim2.fromOffset(0, 120),
            Vector2.zero,
            8
        )
        for index, entry in s.rows do
            local row = Theme.row(
                list,
                "Joueur" .. entry.userId,
                48,
                index,
                if entry.userId == player.UserId then Theme.YELLOW else nil
            )
            Theme.label(
                row,
                "Rang",
                tostring(entry.rank),
                UDim2.new(0.1, 0, 1, -8),
                UDim2.fromOffset(4, 4),
                Theme.YELLOW,
                Vector2.zero,
                22
            )
            local name = Theme.label(
                row,
                "Nom",
                entry.name,
                UDim2.new(0.62, 0, 1, -8),
                UDim2.new(0.14, 0, 0, 4),
                Theme.WHITE,
                Vector2.zero,
                22,
                Enum.TextXAlignment.Left
            )
            name.TextTruncate = Enum.TextTruncate.AtEnd
            Theme.label(
                row,
                "Nombre",
                tostring(entry.count),
                UDim2.new(0.18, 0, 1, -8),
                UDim2.new(0.8, 0, 0, 4),
                Theme.MINT,
                Vector2.zero,
                22
            )
        end
        if #s.rows == 0 then
            Theme.label(
                list,
                "Vide",
                "Le premier dépôt lance le classement !",
                UDim2.new(1, 0, 0, 60),
                UDim2.new(),
                Theme.SOFT_TEXT,
                Vector2.zero,
                22
            )
        end
    end

    local function openModal(): ()
        local s = snapshot
        if s == nil or s.finale or blocked() or Modal.isOpen(modalGui) then
            return
        end
        modal = Modal.open(modalGui, "LA MANCHE", Theme.YELLOW, UDim2.fromOffset(560, 550))
        modalSignature = ""
        if s.resultReady then
            shownResult = s.id
        end
        renderModal()
    end
    button.Activated:Connect(function()
        if modal and modal.root.Parent then
            closeModal()
        else
            openModal()
        end
    end)

    local function updateSnapshot(): ()
        local s = decode(workspace:GetAttribute("MancheClassement")) :: Snapshot?
        local p = decode(player:GetAttribute("ManchePersonnel")) :: Personal?
        if s == nil or p == nil or s.id ~= p.id or s.revision ~= p.revision then
            return
        end
        if snapshot and (snapshot.id ~= s.id or s.finale) then
            closeModal()
        end
        snapshot, personal = s, p
        renderModal()
    end
    local connections = {
        workspace:GetAttributeChangedSignal("MancheClassement"):Connect(updateSnapshot),
        player:GetAttributeChangedSignal("ManchePersonnel"):Connect(updateSnapshot),
    }
    updateSnapshot()

    task.spawn(function()
        while gui.Parent do
            local s, p = snapshot, personal
            local camera = workspace.CurrentCamera
            if camera then
                scale.Scale = math.min(1, (camera.ViewportSize.X - 24) / 400, camera.ViewportSize.Y / 650)
                -- Zone basse centrale, au-dessus des cartes et barres existantes ; aucun HUD déplacé.
                local top = player:GetAttribute("BarrePouvoirsHaut")
                local bottom = if typeof(top) == "number" then top else 20
                local weapons = playerGui:FindFirstChild("BarreArmes")
                local weaponBar = if weapons then weapons:FindFirstChild("Armes") else nil
                if weaponBar and weaponBar:IsA("Frame") then
                    bottom = math.max(bottom, camera.ViewportSize.Y - weaponBar.AbsolutePosition.Y)
                end
                bar.Position = UDim2.new(0.5, 0, 1, -math.max(20, bottom + 12))
            end
            bar.Visible = s ~= nil and not blocked()
            if s and p then
                local seconds = math.max(0, math.ceil(s.endsAt - workspace:GetServerTimeNow()))
                score.Text = string.format("%d / %d", s.total, s.goal)
                mine.Text = string.format("Toi : %d", p.count)
                clock.Text = if s.endsAt > 0 then string.format("%02d:%02d", seconds // 60, seconds % 60) else "—"
                fill.Size = UDim2.fromScale(math.clamp(s.total / math.max(s.goal, 1), 0, 1), 1)
                title.Text = if s.phase == "Active"
                    then (if s.won
                        then "Objectif atteint ! Continuez !"
                        elseif seconds <= Tuning.ROUND_LAST_MINUTE_SECONDS then "Dernière minute : tous ensemble !"
                        else "Ensemble, ramenez les jouets !")
                    elseif s.phase == "Résultat" then (if s.won
                        then "BRAVO L'ÉQUIPE !"
                        elseif s.finale then "Objectif raté : cache-toi !"
                        else "Objectif raté — bilan")
                    elseif s.phase == "Pause" then "Prochaine manche dans..."
                    elseif s.phase == "Préparation" then "Préparez-vous à voler ensemble !"
                    else "En attente de l'équipe..."
                local urgent = s.phase == "Active" and seconds <= Tuning.ROUND_URGENT_SECONDS
                clock.TextColor3 = if urgent then Theme.PINK else Theme.WHITE
                local tickKey = tostring(s.id) .. ":" .. seconds
                if urgent and seconds > 0 and tickKey ~= lastTick then
                    lastTick = tickKey
                    Sfx.play("tick")
                end
                if s.phase == "Résultat" and heardResult ~= s.id then
                    heardResult = s.id
                    if s.won then
                        Sfx.play("fanfare")
                    end
                end
                -- Célébration dans la barre, sans caméra ni effet couvrant les dangers.
                local celebrate = s.phase == "Résultat" and s.won and player:GetAttribute("EffetsReduits") ~= true
                title.TextColor3 = if celebrate
                    then Theme.YELLOW:Lerp(Theme.WHITE, (math.sin(os.clock() * 5) + 1) / 2)
                    else Theme.YELLOW
                if s.resultReady and shownResult ~= s.id and not blocked() and not eventVisible() then
                    openModal()
                end
            end
            task.wait(0.1)
        end
    end)
    gui.Destroying:Connect(function()
        for _, connection in connections do
            connection:Disconnect()
        end
        closeModal()
        modalGui:Destroy()
    end)
end

return RoundController
