--!strict

--[[
    CatWalkController
    Vraie marche du chat de la maison (Workspace.ChatDeLaMaison, evenement « HouseCat » d'EventService). Le modele est
    un seul maillage avec un squelette anatomique (tools/rig-chat.py) ; ce controleur anime ses os selon la vitesse reelle
    du chat, mesuree image par image (le serveur ne fait que le deplacer).

    Anatomie et allure (chat domestique, digitigrade) :
    - marche a quatre temps en sequence laterale : arriere gauche, avant gauche, arriere droite, avant droite, chaque
      patte decalee d'un quart de cycle ; appui 65 % du cycle, lever 35 % ;
    - patte avant : l'epaule balance, le coude plie pendant le lever, le poignet se replie puis pose les doigts a plat ;
    - patte arriere : la hanche balance, le genou (tourne vers l'avant) plie, le jarret (tourne vers l'arriere) compense
      et le metatarse garde les doigts au sol pendant l'appui ;
    - la colonne ondule legerement de cote, la tete contre-balance pour rester stable, la queue suit avec un retard.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CAT_NAME = "ChatDeLaMaison"
-- distance parcourue par cycle complet de marche, en fraction de la longueur du chat
local STRIDE_OF_LENGTH = 0.55
local MOVING_SPEED = 0.6
local SWING = 0.35

type LegDef = { upper: string, lower: string, foot: string, toe: string?, phase: number, front: boolean }

local LEGS: { LegDef } = {
    { upper = "CuisseG", lower = "JambeG", foot = "MetatarseG", toe = "PatteArriereG", phase = 0, front = false },
    { upper = "EpauleG", lower = "AvantBrasG", foot = "PatteAvantG", phase = 0.25, front = true },
    { upper = "CuisseD", lower = "JambeD", foot = "MetatarseD", toe = "PatteArriereD", phase = 0.5, front = false },
    { upper = "EpauleD", lower = "AvantBrasD", foot = "PatteAvantD", phase = 0.75, front = true },
}

type State = {
    model: Model,
    bones: { [string]: Bone },
    last: Vector3,
    cycle: number,
    amount: number,
    stride: number,
}

local CatWalkController = {}

local function findBones(model: Instance): { [string]: Bone }
    local bones: { [string]: Bone } = {}
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("Bone") then
            bones[descendant.Name] = descendant
        end
    end
    return bones
end

-- position dans le cycle -> balancement (-1 arriere .. 1 avant) et lever (0 au sol .. 1 au plus haut)
local function legCurve(t: number): (number, number)
    local u = t % 1
    if u < SWING then
        local k = u / SWING
        return -math.cos(k * math.pi), math.sin(k * math.pi)
    end
    local k = (u - SWING) / (1 - SWING)
    return math.cos(k * math.pi), 0
end

local function setAngle(bones: { [string]: Bone }, name: string, pitch: number, yaw: number?, roll: number?): ()
    local bone = bones[name]
    if bone then
        bone.Transform = CFrame.Angles(pitch, yaw or 0, roll or 0)
    end
end

local function animate(state: State): ()
    local bones, cycle, amount = state.bones, state.cycle, state.amount
    for _, leg in LEGS do
        local swing, lift = legCurve(cycle + leg.phase)
        swing *= amount
        lift *= amount
        if leg.front then
            setAngle(bones, leg.upper, math.rad(22) * swing)
            setAngle(bones, leg.lower, math.rad(-38) * lift)
            setAngle(bones, leg.foot, math.rad(32) * lift)
        else
            setAngle(bones, leg.upper, math.rad(-20) * swing)
            setAngle(bones, leg.lower, math.rad(42) * lift)
            setAngle(bones, leg.foot, math.rad(-34) * lift)
            if leg.toe then
                setAngle(bones, leg.toe, math.rad(18) * lift)
            end
        end
    end
    local wave = math.sin(cycle * math.pi * 2) * amount
    local bob = math.sin(cycle * math.pi * 4) * amount
    setAngle(bones, "Racine", 0, math.rad(4) * wave, math.rad(2) * bob)
    setAngle(bones, "ColonneLombaire", math.rad(1.5) * bob, math.rad(-3) * wave)
    setAngle(bones, "ColonneThoracique", 0, math.rad(-2) * wave, math.rad(-2) * bob)
    setAngle(bones, "Cou", math.rad(-3) * bob, math.rad(2) * wave)
    setAngle(bones, "Tete", math.rad(2) * bob, math.rad(-1) * wave)
    for index, name in { "Queue1", "Queue2", "Queue3" } do
        local lag = math.sin((cycle - index * 0.12) * math.pi * 2)
        setAngle(bones, name, math.rad(6) * amount, math.rad(8 + index * 6) * lag * amount)
    end
end

function CatWalkController:Init(): () end

function CatWalkController:Start(): ()
    local state: State? = nil
    RunService.RenderStepped:Connect(function(dt: number)
        local found = Workspace:FindFirstChild(CAT_NAME)
        if found == nil or not found:IsA("Model") then
            state = nil
            return
        end
        local current = state
        if current == nil or current.model ~= found then
            local _, size = found:GetBoundingBox()
            current = {
                model = found,
                bones = findBones(found),
                last = found:GetPivot().Position,
                cycle = 0,
                amount = 0,
                stride = math.max(math.max(size.X, size.Z) * STRIDE_OF_LENGTH, 1),
            }
            state = current
        end
        if current == nil or next(current.bones) == nil then
            return
        end
        local position = found:GetPivot().Position
        local moved = Vector3.new(position.X - current.last.X, 0, position.Z - current.last.Z).Magnitude
        current.last = position
        local speed = if dt > 0 then moved / dt else 0
        local target = if speed > MOVING_SPEED then 1 else 0
        current.amount += (target - current.amount) * math.min(dt * 6, 1)
        -- un grand saut (teleportation, respawn du modele) ne fait pas tourner les pattes a toute vitesse
        if moved < current.stride then
            current.cycle = (current.cycle + moved / current.stride) % 1
        end
        animate(current)
    end)
end

return CatWalkController
