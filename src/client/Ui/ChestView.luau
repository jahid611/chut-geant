--!strict

--[[
    ChestView
    Vue « Mes jouets » (maquette docs/mockups/higgsfield/mes-jouets.png).

    La camera quitte le personnage, s'approche du coffre par l'avant puis plonge au-dessus : on voit le
    coffre vu de dessus avec les vrais jouets 3D que le serveur y a jetes (ils tombent par la physique).
    Un bandeau « BOÎTE À JOUETS n°k », la jauge de remplissage, le revenu en tetines, des fleches pour
    passer d'un coffre a l'autre, l'achat du coffre suivant quand tout est plein, et « Retour ».
    Les coffres sont lus dans workspace.BaseChests.Base_<UserId> (voir BaseService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Tuning"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local VIEW_FOV = 50
-- Au-dela de cette distance entre la camera et le coffre, on passe par un fondu au noir plutot qu'un long vol.
local FADE_DISTANCE = 350

local ChestView = {}

local isOpen = false

local function chestsOf(player: Player): { Model }
    local root = Workspace:FindFirstChild("BaseChests")
    local folder = if root then root:FindFirstChild("Base_" .. player.UserId) else nil
    local list: { Model } = {}
    if folder then
        for _, child in folder:GetChildren() do
            if child:IsA("Model") and typeof(child:GetAttribute("Index")) == "number" then
                table.insert(list, child)
            end
        end
    end
    table.sort(list, function(a: Model, b: Model)
        return (a:GetAttribute("Index") :: number) < (b:GetAttribute("Index") :: number)
    end)
    return list
end

local function numberAttribute(instance: Instance, name: string): number
    local value = instance:GetAttribute(name)
    return if typeof(value) == "number" then value else 0
end

-- Cadrage vu de dessus : la cavite remplit l'ecran, l'avant du coffre en bas.
local function topDown(chest: Model): (CFrame?, CFrame?)
    local cavity = chest:GetAttribute("CavityCFrame")
    local size = chest:GetAttribute("CavitySize")
    if typeof(cavity) ~= "CFrame" or typeof(size) ~= "Vector3" then
        return nil, nil
    end
    local camera = Workspace.CurrentCamera
    local aspect = camera.ViewportSize.X / math.max(camera.ViewportSize.Y, 1)
    local halfTan = math.tan(math.rad(VIEW_FOV) / 2)
    local needForDepth = size.Z * 2.1 / (2 * halfTan)
    local needForWidth = size.X * 1.6 / (2 * halfTan * aspect)
    local height = math.max(needForDepth, needForWidth) + size.Y
    local target = cavity.Position + Vector3.new(0, size.Y * 0.4, 0)
    local goal = CFrame.lookAt(target + Vector3.new(0, height, 0), target, -cavity.LookVector)
    -- approche : devant et au-dessus du coffre, regard vers lui
    local approach = CFrame.lookAt(
        cavity.Position + cavity.LookVector * (size.X * 1.8) + Vector3.new(0, size.X * 1.1, 0),
        cavity.Position
    )
    return goal, approach
end

function ChestView.open(gui: Instance, onClosed: () -> ()): ()
    if isOpen then
        return
    end
    local player = Players.LocalPlayer
    local chests = chestsOf(player)
    if #chests == 0 then
        Theme.toast(gui, "Tu n'as pas encore de coffre à jouets.", Theme.RED)
        onClosed()
        return
    end
    isOpen = true
    -- la colonne des menus de gauche se cache pendant la vue (MenuController) : la fleche passait par-dessus
    player:SetAttribute("VueCoffre", true)

    local camera = Workspace.CurrentCamera
    local savedType = camera.CameraType
    local savedCFrame = camera.CFrame
    local savedFov = camera.FieldOfView
    camera.CameraType = Enum.CameraType.Scriptable
    local index = 1
    local busy = false
    local connections: { RBXScriptConnection } = {}

    local overlay = Instance.new("Frame")
    overlay.Name = "VueCoffre"
    overlay.BackgroundTransparency = 1
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.Parent = gui

    local fade = Instance.new("Frame")
    fade.Name = "Fondu"
    fade.BackgroundColor3 = Color3.new(0, 0, 0)
    fade.BackgroundTransparency = 1
    fade.Size = UDim2.fromScale(1, 1)
    fade.ZIndex = 20
    fade.Parent = overlay

    local controls = Instance.new("Frame")
    controls.Name = "Commandes"
    controls.BackgroundTransparency = 1
    controls.Size = UDim2.fromScale(1, 1)
    controls.Visible = false
    controls.Parent = overlay

    -- Bandeau titre
    -- Titre et jauge dans un meme cadre, une seule mise a l'echelle : mis a l'echelle chacun de leur cote, ils
    -- grossissaient l'un sur l'autre (capture utilisateur).
    local header = Instance.new("Frame")
    header.Name = "Entete"
    header.BackgroundTransparency = 1
    header.Size = UDim2.fromOffset(640, 160)
    header.Position = UDim2.new(0.5, 0, 0, 10)
    header.AnchorPoint = Vector2.new(0.5, 0)
    header.Parent = controls
    Theme.fit(header, 0.72)
    local banner = Theme.panel(header, "Titre", UDim2.fromOffset(640, 76), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
    local title = Theme.text(
        banner,
        "Texte",
        "",
        UDim2.new(1, -150, 1, -16),
        UDim2.fromScale(0.5, 0.5),
        Theme.WHITE,
        Vector2.new(0.5, 0.5)
    )
    -- etoiles : icone Higgsfield (aucun emoji ni symbole texte dans l'interface)
    Theme.image(banner, "EtoileG", "etoile", UDim2.fromOffset(58, 58), UDim2.new(0, 16, 0.5, 0), Vector2.new(0, 0.5))
    Theme.image(banner, "EtoileD", "etoile", UDim2.fromOffset(58, 58), UDim2.new(1, -16, 0.5, 0), Vector2.new(1, 0.5))

    -- Jauge de remplissage
    local capacity =
        Theme.panel(header, "Capacite", UDim2.fromOffset(580, 62), UDim2.new(0.5, 0, 0, 90), Vector2.new(0.5, 0))
    Theme.image(capacity, "Icone", "articleCoffre", UDim2.fromOffset(72, 52), UDim2.fromOffset(10, 5), Vector2.zero)
    local track = Instance.new("Frame")
    track.Name = "Piste"
    track.BackgroundColor3 = Theme.NAVY_DARK
    track.BorderSizePixel = 0
    track.Size = UDim2.fromOffset(470, 36)
    track.Position = UDim2.fromOffset(94, 13)
    track.Parent = capacity
    Theme.corner(track, 18)
    local fill = Instance.new("Frame")
    fill.Name = "Remplissage"
    fill.BackgroundColor3 = Theme.GREEN
    fill.BorderSizePixel = 0
    fill.Size = UDim2.fromScale(0, 1)
    fill.Parent = track
    Theme.corner(fill, 18)
    local capacityLabel = Theme.text(
        track,
        "Texte",
        "",
        UDim2.new(1, 0, 1, -8),
        UDim2.fromScale(0.5, 0.5),
        Theme.WHITE,
        Vector2.new(0.5, 0.5)
    )
    capacityLabel.ZIndex = 2

    -- Revenu
    local income =
        Theme.panel(controls, "Revenu", UDim2.fromOffset(236, 88), UDim2.new(1, -18, 0, 94), Vector2.new(1, 0))
    Theme.fit(income, 0.72)
    Theme.image(income, "Icone", "tetine", UDim2.fromOffset(70, 70), UDim2.fromOffset(8, 9), Vector2.zero)
    local incomeLabel =
        Theme.text(income, "Montant", "", UDim2.fromOffset(140, 42), UDim2.fromOffset(84, 8), Theme.WHITE, Vector2.zero)
    Theme.text(
        income,
        "Unite",
        "tétines/s",
        UDim2.fromOffset(140, 26),
        UDim2.fromOffset(84, 52),
        Theme.SOFT_TEXT,
        Vector2.zero
    )

    -- Fleches et boutons
    -- fleches et retour : icones Higgsfield ; la fleche de gauche est la meme icone retournee
    local previous = Theme.button(
        controls,
        "Precedent",
        "",
        Theme.NAVY,
        UDim2.fromOffset(96, 96),
        UDim2.new(0, 24, 0.5, 0),
        Vector2.new(0, 0.5)
    )
    Theme.fit(previous)
    local previousIcon = Theme.image(
        previous,
        "Icone",
        "fleche",
        UDim2.fromScale(1, 1),
        UDim2.fromScale(0.5, 0.5),
        Vector2.new(0.5, 0.5)
    )
    previousIcon.Rotation = 180
    local nextButton = Theme.button(
        controls,
        "Suivant",
        "",
        Theme.NAVY,
        UDim2.fromOffset(96, 96),
        UDim2.new(1, -24, 0.5, 0),
        Vector2.new(1, 0.5)
    )
    Theme.fit(nextButton)
    Theme.image(nextButton, "Icone", "fleche", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
    local back = Theme.button(
        controls,
        "Retour",
        "Retour",
        Theme.PINK,
        UDim2.fromOffset(290, 78),
        UDim2.new(0.5, 0, 1, -18),
        Vector2.new(0.5, 1)
    )
    Theme.fit(back)
    local backPadding = back:FindFirstChildOfClass("UIPadding")
    if backPadding then
        backPadding.PaddingLeft = UDim.new(0, 64)
    end
    Theme.image(back, "Icone", "retour", UDim2.fromOffset(54, 54), UDim2.new(0, -58, 0.5, 0), Vector2.new(0, 0.5))
    local buyChest = Theme.button(
        controls,
        "AcheterCoffre",
        "",
        Theme.GREEN,
        UDim2.fromOffset(430, 62),
        UDim2.new(0.5, 0, 1, -112),
        Vector2.new(0.5, 1)
    )
    Theme.fit(buyChest)

    local function refresh(): ()
        local chest: Model? = chests[index]
        if chest == nil then
            return
        end
        local count = numberAttribute(chest, "Count")
        local cap = math.max(numberAttribute(chest, "Capacity"), 1)
        title.Text = string.format("BOÎTE À JOUETS n°%d", index)
        fill.Size = UDim2.fromScale(math.clamp(count / cap, 0, 1), 1)
        fill.BackgroundColor3 = if count >= cap then Theme.PINK else Theme.GREEN
        capacityLabel.Text = string.format("%d / %d jouets", count, cap)
        incomeLabel.Text = "+" .. Theme.formatNumber(numberAttribute(player, "Income"))
        previous.Visible = #chests > 1
        nextButton.Visible = #chests > 1
        local allFull = true
        for _, other in chests do
            if numberAttribute(other, "Count") < numberAttribute(other, "Capacity") then
                allFull = false
            end
        end
        buyChest.Visible = allFull and #chests < Tuning.MAX_CHESTS
        buyChest.Text = "Acheter un coffre – " .. Theme.formatNumber(Tuning.CHEST_PRICE)
    end

    local function watch(chest: Model): ()
        table.insert(connections, chest:GetAttributeChangedSignal("Count"):Connect(refresh))
    end
    for _, chest in chests do
        watch(chest)
    end
    table.insert(connections, player:GetAttributeChangedSignal("Income"):Connect(refresh))

    local function tween(goal: { [string]: any }, seconds: number, style: Enum.EasingStyle): ()
        local t = TweenService:Create(camera, TweenInfo.new(seconds, style, Enum.EasingDirection.InOut), goal)
        t:Play()
        t.Completed:Wait()
    end

    local function fadeTo(transparency: number, seconds: number): ()
        local t = TweenService:Create(fade, TweenInfo.new(seconds), { BackgroundTransparency = transparency })
        t:Play()
        t.Completed:Wait()
    end

    local function flyTo(chest: Model, entering: boolean): ()
        local goal, approach = topDown(chest)
        if goal == nil or approach == nil then
            return
        end
        if entering then
            if (camera.CFrame.Position - approach.Position).Magnitude > FADE_DISTANCE then
                fadeTo(0, 0.25)
                camera.CFrame = approach * CFrame.new(0, 0, 40)
                task.spawn(fadeTo, 1, 0.35)
            end
            tween({ CFrame = approach }, 0.55, Enum.EasingStyle.Quad)
            -- plongee dans le coffre
            tween({ CFrame = goal, FieldOfView = VIEW_FOV }, 0.9, Enum.EasingStyle.Sine)
        else
            tween({ CFrame = goal }, 0.5, Enum.EasingStyle.Sine)
        end
    end

    local function close(): ()
        if busy then
            return
        end
        busy = true
        controls.Visible = false
        for _, connection in connections do
            connection:Disconnect()
        end
        if (camera.CFrame.Position - savedCFrame.Position).Magnitude > FADE_DISTANCE then
            fadeTo(0, 0.25)
            camera.CFrame = savedCFrame
            camera.FieldOfView = savedFov
        else
            tween({ CFrame = savedCFrame, FieldOfView = savedFov }, 0.6, Enum.EasingStyle.Sine)
        end
        camera.CameraType = savedType
        overlay:Destroy()
        isOpen = false
        player:SetAttribute("VueCoffre", nil)
        onClosed()
    end

    local function switch(step: number): ()
        if busy or #chests < 2 then
            return
        end
        busy = true
        index = (index - 1 + step) % #chests + 1
        refresh()
        flyTo(chests[index], false)
        busy = false
    end

    previous.Activated:Connect(function()
        switch(-1)
    end)
    nextButton.Activated:Connect(function()
        switch(1)
    end)
    back.Activated:Connect(close)
    buyChest.Activated:Connect(function()
        if busy then
            return
        end
        busy = true
        buyChest.Text = "..."
        local ok, success, message = pcall(function()
            return (Remotes.Get("BuyItem") :: RemoteFunction):InvokeServer("Chest")
        end)
        if ok and success == true then
            Theme.toast(gui, if typeof(message) == "string" then message else "Coffre acheté !", Theme.GREEN)
            -- attendre que le nouveau coffre soit replique, puis s'y rendre
            local deadline = os.clock() + 3
            local before = #chests
            while #chestsOf(player) <= before and os.clock() < deadline do
                task.wait(0.1)
            end
            chests = chestsOf(player)
            watch(chests[#chests])
            index = #chests
            refresh()
            flyTo(chests[index], false)
        else
            Theme.toast(gui, if ok and typeof(message) == "string" then message else "Achat impossible.", Theme.RED)
            refresh()
        end
        busy = false
    end)

    refresh()
    busy = true
    flyTo(chests[index], true)
    busy = false
    controls.Visible = true
end

return ChestView
