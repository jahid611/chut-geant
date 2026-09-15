--!strict

--[[
    BabyVisualService
    Montre l'etat du bebe dans le berceau.

    workspace.Geant contient trois modeles poses par la recette build-chambre :
    Dort (bebe endormi), Pleure (bebe reveille qui pleure) et Tetine. GiantService
    pose l'attribut State sur Geant ; ce service bascule la visibilite des deux
    bebes et fait tomber la tetine au reveil, puis la remet en place au coucher.

    Bebe qui se leve et regarde (retour utilisateur du 15/09) : les bebes sont des maillages statiques, sans
    squelette. Au reveil (Waking), le bebe qui pleure pivote autour de son point le plus bas pour se mettre debout,
    face a la chambre ; pendant la chasse et les regards (Hunting, Glance compris) il balaie lentement la piece de
    gauche a droite avec un faisceau de lumiere froide (SpotLight « Regard » soude a sa tete) ; il se recouche en
    douceur quand il se rendort. Mouvements par TweenService sur une CFrameValue (PivotTo), une seule animation a la
    fois.

    Repere du modele (recette build-chambre, verifie par le sens de la tetine) : couche, son UpVector (haut du corps
    debout) pointe vers la tete, et son LookVector (face des modeles Tripo) vers le plafond. Debout, UpVector = haut du
    monde et LookVector = direction du regard. A verifier par capture.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tuning"))

local NoiseService = require(script.Parent:WaitForChild("NoiseService"))

local BabyVisualService = {}

local GAZE_NAME = "Regard"
local RISE_SECONDS = 1.1
local LIE_SECONDS = 0.9
local SCAN_ANGLE = math.rad(38)
local SCAN_HALF_PERIOD = 1.7
-- Direction de la chambre vu du berceau : les bases sont vers +Z. CFrame.Angles(0, pi, 0) regarde vers +Z.
local ROOM_YAW = math.pi

local pacifierRest: CFrame? = nil

-- Pose couchee du bebe qui pleure, mesuree au demarrage (avant toute animation).
type Rest = { pivot: CFrame, center: CFrame, size: Vector3, offset: CFrame, bottomY: number }
local rest: Rest? = nil
local animToken = 0
local wasAwake = false
local currentTween: Tween? = nil
local currentDriver: CFrameValue? = nil

-- Les bebes sont des MeshPart Tripo opaques : visible = 0, cache = 1. La recette de scene
-- peut donc livrer Pleure deja cache. Le faisceau « Regard » reste toujours invisible.
local function setVisible(model: Instance?, visible: boolean): ()
    if model == nil then
        return
    end
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("BasePart") and descendant.Name ~= GAZE_NAME then
            descendant.Transparency = if visible then 0 else 1
        end
    end
end

local function dropPacifier(pacifier: Instance?, falling: boolean): ()
    if pacifier == nil or not pacifier:IsA("Model") then
        return
    end
    if pacifierRest == nil then
        pacifierRest = pacifier:GetPivot()
    end
    local restCFrame = pacifierRest :: CFrame
    local target = if falling
        then restCFrame * CFrame.new(0, -60, 20) * CFrame.Angles(math.rad(70), 0, math.rad(30))
        else restCFrame
    local driver = Instance.new("CFrameValue")
    driver.Value = pacifier:GetPivot()
    driver.Changed:Connect(function(value: CFrame)
        pacifier:PivotTo(value)
    end)
    local tween = TweenService:Create(
        driver,
        TweenInfo.new(if falling then 0.6 else 1.2, if falling then Enum.EasingStyle.Bounce else Enum.EasingStyle.Sine),
        { Value = target }
    )
    tween.Completed:Connect(function()
        driver:Destroy()
    end)
    tween:Play()
end

local function measureRest(model: Model): Rest
    local pivot = model:GetPivot()
    local center, size = model:GetBoundingBox()
    -- demi-hauteur dans le monde de la boite orientee
    local halfY = math.abs(center.RightVector.Y) * size.X / 2
        + math.abs(center.UpVector.Y) * size.Y / 2
        + math.abs(center.LookVector.Y) * size.Z / 2
    return {
        pivot = pivot,
        center = center,
        size = size,
        offset = center:ToObjectSpace(pivot),
        bottomY = center.Position.Y - halfY,
    }
end

-- Pivot du bebe debout, au-dessus de sa position couchee, pieds sur le matelas, tourne de `yaw` autour de la
-- direction de la chambre.
local function standingPivot(r: Rest, yaw: number): CFrame
    local height = r.size.Y
    local centerCFrame = CFrame.new(r.center.Position.X, r.bottomY + height / 2, r.center.Position.Z)
        * CFrame.Angles(0, ROOM_YAW + yaw, 0)
    return centerCFrame * r.offset
end

-- Une seule animation a la fois : la precedente est annulee avant d'en lancer une autre.
local function tweenPivot(model: Model, goal: CFrame, seconds: number, style: Enum.EasingStyle): ()
    local oldTween = currentTween
    if oldTween then
        oldTween:Cancel()
    end
    local oldDriver = currentDriver
    if oldDriver then
        oldDriver:Destroy()
    end
    local driver = Instance.new("CFrameValue")
    driver.Value = model:GetPivot()
    driver.Changed:Connect(function(value: CFrame)
        model:PivotTo(value)
    end)
    local tween =
        TweenService:Create(driver, TweenInfo.new(seconds, style, Enum.EasingDirection.InOut), { Value = goal })
    tween.Completed:Connect(function()
        if currentDriver == driver then
            currentDriver = nil
            currentTween = nil
        end
        driver:Destroy()
    end)
    currentTween = tween
    currentDriver = driver
    tween:Play()
end

-- Faisceau du regard : piece invisible au niveau de la tete, orientee comme le visage, avec un SpotLight.
local function ensureGaze(model: Model, r: Rest): ()
    if model:FindFirstChild(GAZE_NAME) then
        return
    end
    local head = r.center.Position + r.center.UpVector * r.size.Y * 0.36
    local restGaze = CFrame.lookAt(head, head + r.center.LookVector)
    local part = Instance.new("Part")
    part.Name = GAZE_NAME
    part.Size = Vector3.one
    part.Transparency = 1
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    -- relatif a la pose actuelle (le bebe peut etre en train de se recoucher)
    part.CFrame = model:GetPivot() * r.pivot:ToObjectSpace(restGaze)
    local light = Instance.new("SpotLight")
    light.Face = Enum.NormalId.Front
    light.Color = Color3.fromRGB(190, 215, 255)
    light.Brightness = 6
    light.Range = 60
    light.Angle = 45
    light.Shadows = true
    light.Parent = part
    part.Parent = model
end

local function removeGaze(model: Model): ()
    local gaze = model:FindFirstChild(GAZE_NAME)
    if gaze then
        gaze:Destroy()
    end
end

local function animate(model: Model, awake: boolean): ()
    local r = rest
    if r == nil then
        return
    end
    animToken += 1
    local token = animToken
    if not awake then
        removeGaze(model)
        tweenPivot(model, r.pivot, LIE_SECONDS, Enum.EasingStyle.Sine)
        return
    end
    ensureGaze(model, r)
    tweenPivot(model, standingPivot(r, 0), RISE_SECONDS, Enum.EasingStyle.Back)
    task.spawn(function()
        task.wait(RISE_SECONDS)
        local side = 1
        while token == animToken do
            tweenPivot(model, standingPivot(r, SCAN_ANGLE * side), SCAN_HALF_PERIOD, Enum.EasingStyle.Sine)
            task.wait(SCAN_HALF_PERIOD)
            side = -side
        end
    end)
end

local function apply(giant: Instance): ()
    local state = giant:GetAttribute("State")
    local awake = state == "Waking" or state == "Hunting"
    setVisible(giant:FindFirstChild("Dort"), not awake)
    local crying = giant:FindFirstChild("Pleure")
    setVisible(crying, awake)
    dropPacifier(giant:FindFirstChild("Tetine"), awake)
    if awake ~= wasAwake then
        wasAwake = awake
        if crying and crying:IsA("Model") then
            animate(crying, awake)
        end
    end
end

--[[
    Reveil en douceur (idee 19 du carnet) : pendant le sommeil, des que la jauge depasse STIR_FRACTION, le bebe endormi
    se retourne a moitie d'un cote puis de l'autre (roulis autour de son axe tete-pieds, local Y) : derniere chance
    lisible pour s'immobiliser. Attribut Remue sur Geant pour les clients (marmonnement, bulle).
]]
local STIR_FRACTION = 0.8
local STIR_ANGLE = math.rad(14)
local STIR_SECONDS = 0.7
local STIR_CHECK_SECONDS = 0.3
local stirToken = 0
local stirTween: Tween? = nil

local function rollSleeper(sleeper: Model, goal: CFrame): ()
    local previous = stirTween
    if previous then
        previous:Cancel()
    end
    local driver = Instance.new("CFrameValue")
    driver.Value = sleeper:GetPivot()
    driver.Changed:Connect(function(value: CFrame)
        sleeper:PivotTo(value)
    end)
    local tween = TweenService:Create(
        driver,
        TweenInfo.new(STIR_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
        { Value = goal }
    )
    tween.Completed:Connect(function()
        driver:Destroy()
    end)
    stirTween = tween
    tween:Play()
end

local function setStirring(giant: Instance, sleeper: Model, restPivot: CFrame, stirring: boolean): ()
    if (giant:GetAttribute("Remue") == true) == stirring then
        return
    end
    giant:SetAttribute("Remue", stirring)
    stirToken += 1
    local token = stirToken
    if not stirring then
        rollSleeper(sleeper, restPivot)
        return
    end
    task.spawn(function()
        local side = 1
        while token == stirToken do
            rollSleeper(sleeper, restPivot * CFrame.Angles(0, STIR_ANGLE * side, 0))
            task.wait(STIR_SECONDS + 0.5)
            side = -side
        end
    end)
end

function BabyVisualService:Init(): () end

function BabyVisualService:Start(): ()
    local giant = workspace:WaitForChild("Geant", 10)
    if giant == nil then
        warn("[BabyVisualService] workspace.Geant absent : lancer tools/scene/build-chambre.luau")
        return
    end
    local crying = giant:FindFirstChild("Pleure")
    setVisible(crying, false)
    if crying and crying:IsA("Model") then
        rest = measureRest(crying)
    end
    giant:GetAttributeChangedSignal("State"):Connect(function()
        apply(giant)
    end)
    apply(giant)

    local sleeper = giant:FindFirstChild("Dort")
    if sleeper and sleeper:IsA("Model") then
        local sleeperRest = sleeper:GetPivot()
        local elapsed = 0
        RunService.Heartbeat:Connect(function(dt: number)
            elapsed += dt
            if elapsed < STIR_CHECK_SECONDS then
                return
            end
            elapsed = 0
            local state = giant:GetAttribute("State")
            local sleeping = state ~= "Waking" and state ~= "Hunting"
            local loud = NoiseService:Get() >= Tuning.NOISE_MAX * STIR_FRACTION
            setStirring(giant, sleeper, sleeperRest, sleeping and loud)
        end)
    end
end

return BabyVisualService
