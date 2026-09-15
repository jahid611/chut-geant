--!strict

--[[
    ToyInspectController
    Inspection d'un jouet de la chambre (demande utilisateur : « quand je clique sur un jouet, ça zoome juste en face
    et ça me donne ses informations, puis je reviens sur mon personnage »).

    - Clic gauche (ou tap court sur mobile) sur un jouet de workspace.ToysLive qui n'est pas porte : la camera vole
      devant le jouet, un panneau affiche son nom, sa rarete, son revenu en tetines/s et son poids.
    - « Retour », Echap, Retour arriere ou le bouton B de la manette ferment la vue : la camera revient a sa
      position d'avant et suit de nouveau le personnage.
    - Pendant la vue, les deplacements du joueur sont coupes (PlayerModule). La vue se ferme seule si le jouet
      disparait, est ramasse, ou si le personnage reapparait.
    - Rien ne s'ouvre si la camera est deja pilotee par une autre vue (ChestView la passe en Scriptable).
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Toys = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Toys"))

local Assets = require(script.Parent.Parent.Ui.Assets)
local Theme = require(script.Parent.Parent.Ui.Theme)

local FLY_SECONDS = 0.6
local BACK_SECONDS = 0.45
local CLOSE_ACTION = "FermerInspectionJouet"
-- Un tap mobile : court et presque immobile (sinon c'est un glisser pour tourner la camera).
local TAP_MAX_SECONDS = 0.35
local TAP_MAX_PIXELS = 14
local HOVER_INTERVAL = 0.1
local HOVER_ICON = "rbxasset://SystemCursors/PointingHand"

type Session = {
    toy: Model,
    holder: Frame,
    savedCFrame: CFrame,
    savedType: Enum.CameraType,
    connections: { RBXScriptConnection },
}

local ToyInspectController = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local session: Session? = nil
local busy = false
local closeRequested = false

-- Remonte d'une piece touchee jusqu'au modele de jouet, enfant direct de workspace.ToysLive.
local function toyFrom(instance: Instance): Model?
    local live = Workspace:FindFirstChild("ToysLive")
    if live == nil then
        return nil
    end
    local node: Instance? = instance
    while node and node.Parent ~= live do
        node = node.Parent
    end
    if node and node:IsA("Model") and typeof(node:GetAttribute("ToyId")) == "string" then
        return node
    end
    return nil
end

-- Jouet sous un point de l'ecran (coordonnees d'InputObject), en traversant les volumes invisibles.
local function pickToy(screen: Vector3): Model?
    local camera = Workspace.CurrentCamera
    local ray = camera:ScreenPointToRay(screen.X, screen.Y)
    local ignore: { Instance } = {}
    if player.Character then
        table.insert(ignore, player.Character)
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    for _ = 1, 8 do
        params.FilterDescendantsInstances = ignore
        local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
        if hit == nil then
            return nil
        end
        local toy = toyFrom(hit.Instance)
        if toy then
            return if toy:GetAttribute("CarrierUserId") == nil then toy else nil
        end
        if hit.Instance.Transparency < 0.95 then
            return nil
        end
        table.insert(ignore, hit.Instance)
    end
    return nil
end

-- Coupe ou rend les commandes de deplacement du personnage.
-- Pas de WaitForChild : ce place n'a pas de PlayerModule dans PlayerScripts, l'attente bloquait la vue apres
-- l'affichage du panneau (camera jamais deplacee, fiche restee ouverte). Sans module, les touches de deplacement
-- sont avalees pendant la vue.
local FREEZE_ACTION = "InspectionBloqueDeplacement"
local function setControlsEnabled(enabled: boolean): ()
    local scripts = player:FindFirstChild("PlayerScripts")
    local moduleScript = if scripts then scripts:FindFirstChild("PlayerModule") else nil
    if enabled then
        -- Toujours delier le blocage des touches : si le PlayerModule est apparu entre l'ouverture (repli par touches
        -- avalees) et la fermeture, seul Enable() etait appele et les deplacements restaient coupes.
        ContextActionService:UnbindAction(FREEZE_ACTION)
    end
    if moduleScript and moduleScript:IsA("ModuleScript") then
        local ok = pcall(function()
            local controls = (require :: any)(moduleScript):GetControls()
            if enabled then
                controls:Enable()
            else
                controls:Disable()
            end
        end)
        if ok then
            return
        end
    end
    if not enabled then
        ContextActionService:BindActionAtPriority(
            FREEZE_ACTION,
            function(): Enum.ContextActionResult
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.ContextActionPriority.High.Value,
            Enum.PlayerActions.CharacterForward,
            Enum.PlayerActions.CharacterBackward,
            Enum.PlayerActions.CharacterLeft,
            Enum.PlayerActions.CharacterRight,
            Enum.PlayerActions.CharacterJump,
            Enum.KeyCode.W,
            Enum.KeyCode.A,
            Enum.KeyCode.S,
            Enum.KeyCode.D,
            Enum.KeyCode.Space,
            Enum.KeyCode.Thumbstick1,
            Enum.KeyCode.ButtonA
        )
    end
end

local function tweenCamera(goal: CFrame, seconds: number): ()
    local camera = Workspace.CurrentCamera
    local tween = TweenService:Create(
        camera,
        TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
        { CFrame = goal }
    )
    tween:Play()
    tween.Completed:Wait()
end

local function close(): ()
    local current = session
    if current == nil then
        return
    end
    if busy then
        -- Fermeture demandee pendant le vol de la camera (Echap, jouet ramasse, reapparition) : elle etait perdue et
        -- la vue restait ouverte, deplacements coupes. Elle est rejouee a la fin de l'ouverture.
        closeRequested = true
        return
    end
    closeRequested = false
    busy = true
    session = nil
    for _, connection in current.connections do
        connection:Disconnect()
    end
    ContextActionService:UnbindAction(CLOSE_ACTION)
    current.holder:Destroy()
    tweenCamera(current.savedCFrame, BACK_SECONDS)
    local camera = Workspace.CurrentCamera
    camera.CameraType = if current.savedType == Enum.CameraType.Scriptable
        then Enum.CameraType.Custom
        else current.savedType
    setControlsEnabled(true)
    busy = false
end

-- Ligne « libelle : valeur » du panneau.
local function row(parent: Instance, name: string, label: string, value: string, y: number, color: Color3): ()
    Theme.text(
        parent,
        name .. "Libelle",
        label,
        UDim2.new(1, -48, 0, 24),
        UDim2.new(0.5, 0, 0, y),
        Theme.SOFT_TEXT,
        Vector2.new(0.5, 0)
    )
    Theme.text(
        parent,
        name .. "Valeur",
        value,
        UDim2.new(1, -48, 0, 34),
        UDim2.new(0.5, 0, 0, y + 24),
        color,
        Vector2.new(0.5, 0)
    )
end

local function buildPanel(toy: Model): Frame?
    local toyId = toy:GetAttribute("ToyId")
    local def = if typeof(toyId) == "string" then Toys.Get(toyId) else nil
    if def == nil or gui == nil then
        return nil
    end
    local mutationId = toy:GetAttribute("Mutation")
    local mutation = if typeof(mutationId) == "string" then Toys.GetMutation(mutationId) else nil
    local rarity = Theme.RARITY[def.rarity]
    local rarityColor = if rarity then rarity.color else Theme.WHITE

    local holder = Instance.new("Frame")
    holder.Name = "InspectionJouet"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(420, 350)
    holder.Position = UDim2.new(1, -36, 0.5, 0)
    holder.AnchorPoint = Vector2.new(1, 0.5)
    holder.Parent = gui
    local scale = Theme.fit(holder, 0.85)
    local target = scale.Scale
    scale.Scale = target * 0.7
    TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = target }):Play()

    local panel = Theme.panel(holder, "Panneau", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero)
    local stroke = panel:FindFirstChildOfClass("UIStroke")
    if stroke then
        stroke.Color = rarityColor
    end

    local name = def.displayName .. (if mutation then " " .. mutation.displayName else "")
    -- image du jouet a gauche du nom si son rendu est televerse (cle Assets « jouet<ToyId> »)
    local imageKey = "jouet" .. def.id
    local imageId = Assets[imageKey]
    if imageId ~= nil and imageId ~= "rbxassetid://0" then
        Theme.icon(panel, "ImageJouet", imageKey, UDim2.fromOffset(52, 52), UDim2.fromOffset(18, 16), Vector2.zero)
        Theme.text(panel, "Nom", name, UDim2.new(1, -96, 0, 50), UDim2.fromOffset(78, 16), Theme.WHITE, Vector2.zero)
    else
        Theme.text(
            panel,
            "Nom",
            name,
            UDim2.new(1, -40, 0, 50),
            UDim2.new(0.5, 0, 0, 16),
            Theme.WHITE,
            Vector2.new(0.5, 0)
        )
    end

    local pill = Instance.new("Frame")
    pill.Name = "Rarete"
    pill.BackgroundColor3 = rarityColor
    pill.BorderSizePixel = 0
    pill.Size = UDim2.fromOffset(210, 36)
    pill.Position = UDim2.new(0.5, 0, 0, 74)
    pill.AnchorPoint = Vector2.new(0.5, 0)
    pill.Parent = panel
    Theme.corner(pill, 18)
    Theme.text(
        pill,
        "Texte",
        if rarity then rarity.label else def.rarity,
        UDim2.new(1, -24, 1, -8),
        UDim2.fromScale(0.5, 0.5),
        Theme.WHITE,
        Vector2.new(0.5, 0.5)
    )

    local income = Toys.Income(def.id, if mutation then mutation.id else nil)
    row(panel, "Revenu", "Revenu", "+" .. Theme.formatNumber(income) .. " tétines/s", 124, Theme.YELLOW)
    local weight = if def.carriers <= 1 then "Léger" else string.format("Lourd : %d porteurs", def.carriers)
    row(panel, "Poids", "Poids", weight, 192, if def.carriers <= 1 then Theme.MINT else Theme.PINK)

    local back = Theme.button(
        panel,
        "Retour",
        "Retour",
        Theme.PINK,
        UDim2.fromOffset(230, 64),
        UDim2.new(0.5, 0, 1, -18),
        Vector2.new(0.5, 1)
    )
    local padding = back:FindFirstChildOfClass("UIPadding")
    if padding then
        padding.PaddingLeft = UDim.new(0, 58)
    end
    Theme.image(back, "Icone", "retour", UDim2.fromOffset(46, 46), UDim2.new(0, -52, 0.5, 0), Vector2.new(0, 0.5))
    back.Activated:Connect(function()
        task.spawn(close)
    end)
    return holder
end

local function open(toy: Model): ()
    if session or busy then
        return
    end
    local camera = Workspace.CurrentCamera
    if camera.CameraType == Enum.CameraType.Scriptable then
        return
    end
    local holder = buildPanel(toy)
    if holder == nil then
        return
    end
    busy = true
    local current: Session = {
        toy = toy,
        holder = holder,
        savedCFrame = camera.CFrame,
        savedType = camera.CameraType,
        connections = {},
    }
    session = current
    setControlsEnabled(false)
    camera.CameraType = Enum.CameraType.Scriptable

    -- Juste devant la face du jouet (son LookVector a plat), a 1,3 fois sa plus grande dimension, un peu au-dessus.
    -- A 2,2 fois, la camera finissait derriere le personnage, trop loin (capture fiche-jouet-v2). Si un meuble ou un
    -- mur est entre le jouet et ce point, on se place du cote de la camera actuelle. Le regard vise un peu a droite
    -- du jouet pour qu'il reste visible a gauche du panneau.
    local center, size = toy:GetBoundingBox()
    local biggest = math.max(size.X, size.Y, size.Z, 1)
    local distance = math.max(biggest * 1.3, 6)
    local function flat(v: Vector3): Vector3
        local f = Vector3.new(v.X, 0, v.Z)
        return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, 1)
    end
    local front = flat(center.LookVector)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore: { Instance } = { toy }
    if player.Character then
        table.insert(ignore, player.Character)
    end
    params.FilterDescendantsInstances = ignore
    if Workspace:Raycast(center.Position, front * distance, params) then
        front = flat(camera.CFrame.Position - center.Position)
    end
    local right = (-front):Cross(Vector3.yAxis)
    local eye = center.Position + front * distance + Vector3.new(0, biggest * 0.3, 0)
    local lookAt = center.Position + right * biggest * 0.3
    table.insert(
        current.connections,
        toy.AncestryChanged:Connect(function()
            if toy.Parent == nil then
                task.spawn(close)
            end
        end)
    )
    table.insert(
        current.connections,
        toy:GetAttributeChangedSignal("CarrierUserId"):Connect(function()
            if toy:GetAttribute("CarrierUserId") ~= nil then
                task.spawn(close)
            end
        end)
    )
    table.insert(
        current.connections,
        player.CharacterAdded:Connect(function()
            task.spawn(close)
        end)
    )
    ContextActionService:BindAction(
        CLOSE_ACTION,
        function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
            if state == Enum.UserInputState.Begin then
                task.spawn(close)
            end
            return Enum.ContextActionResult.Sink
        end,
        false,
        Enum.KeyCode.Backspace,
        Enum.KeyCode.ButtonB
    )
    tweenCamera(CFrame.lookAt(eye, lookAt), FLY_SECONDS)
    busy = false
    if closeRequested then
        close()
    end
end

-- Pas de fiche pendant l'action : le clic sert aussi a frapper et a viser, et une fiche ouverte en pleine course
-- figeait le personnage d'un coup, le panneau passant inapercu sur le bord de l'ecran (utilisateur du 15/09 :
-- « je cours et je me bloque d'un coup »). Seulement a l'arret, mains vides, sans arme en main.
local function canInspect(): boolean
    local character = player.Character
    local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
    if character == nil or humanoid == nil then
        return false
    end
    if humanoid.MoveDirection.Magnitude > 0.1 or character:FindFirstChildOfClass("Tool") ~= nil then
        return false
    end
    return player:GetAttribute("CarriedToyId") == nil
end

function ToyInspectController:Init(): () end

-- Ouverture par le code (tests en jeu) : meme vue qu'un clic sur le jouet.
function ToyInspectController:Open(toy: Model): ()
    open(toy)
end

function ToyInspectController:Start(): ()
    local screen = Instance.new("ScreenGui")
    screen.Name = "InspectionJouets"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 8
    screen.Parent = player:WaitForChild("PlayerGui")
    gui = screen

    local touchStart: { [InputObject]: { position: Vector3, time: number } } = {}

    UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if input.KeyCode == Enum.KeyCode.Escape then
            if session then
                task.spawn(close)
            end
            return
        end
        if gameProcessed or session or busy then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local toy = pickToy(input.Position)
            if toy and canInspect() then
                task.spawn(open, toy)
            end
        elseif input.UserInputType == Enum.UserInputType.Touch then
            touchStart[input] = { position = input.Position, time = os.clock() }
        end
    end)

    UserInputService.InputEnded:Connect(function(input: InputObject, gameProcessed: boolean)
        if input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local start = touchStart[input]
        touchStart[input] = nil
        if start == nil or gameProcessed or session or busy then
            return
        end
        local moved = (input.Position - start.position).Magnitude
        if os.clock() - start.time <= TAP_MAX_SECONDS and moved <= TAP_MAX_PIXELS then
            local toy = pickToy(input.Position)
            if toy and canInspect() then
                task.spawn(open, toy)
            end
        end
    end)

    -- Main pointee au survol d'un jouet (souris seulement), verifie a intervalle pour ne pas lancer un rayon a
    -- chaque mouvement.
    local lastHover = 0
    UserInputService.InputChanged:Connect(function(input: InputObject)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end
        local now = os.clock()
        if now - lastHover < HOVER_INTERVAL then
            return
        end
        lastHover = now
        local hovering = session == nil and pickToy(input.Position) ~= nil
        UserInputService.MouseIcon = if hovering then HOVER_ICON else ""
    end)
end

return ToyInspectController
