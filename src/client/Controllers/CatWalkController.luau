--!strict

--[[
    CatWalkController
    Vraie marche du chat de la maison (Workspace.ChatDeLaMaison, evenement « HouseCat » d'EventService). Le modele est
    un seul maillage avec un squelette anatomique (tools/rig-chat-gpt.py) ; ce controleur anime ses os selon la vitesse
    reelle du chat (le serveur ne fait que le deplacer).

    Axes : les os importes n'ont pas le meme repere que le chat (sur les pattes, l'axe local Z est lateral). L'axe
    lateral et l'axe vertical du chat sont donc exprimes dans le repere de chaque os a partir de sa pose de repos, au
    lieu de supposer un axe (la premiere version tournait les pattes de cote : « il ne marche pas du tout comme un
    chat », 15/09).

    Anatomie et allure (chat domestique, digitigrade) :
    - marche a quatre temps en sequence laterale : arriere gauche, avant gauche, arriere droite, avant droite, chaque
      patte decalee d'un quart de cycle ; appui 65 % du cycle, lever 35 % ;
    - patte avant : l'epaule balance, le coude et le poignet se replient vers l'arriere pendant le lever ;
    - patte arriere : la hanche balance, le genou recule, le jarret avance, les doigts se replient ;
    - la colonne ondule de cote et monte legerement a chaque appui, la tete contre-balance, la queue releve et suit.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CAT_NAME = "ChatDeLaMaison"
-- distance parcourue par cycle complet, en fraction de la longueur du chat (un chat qui marche : environ 0,75)
local STRIDE_OF_LENGTH = 0.75
local MOVING_SPEED = 2
local SWING = 0.35

type LegDef = { upper: string, lower: string, foot: string, toe: string?, phase: number, front: boolean }

local LEGS: { LegDef } = {
    { upper = "CuisseG", lower = "JambeG", foot = "MetatarseG", toe = "PatteArriereG", phase = 0, front = false },
    { upper = "EpauleG", lower = "AvantBrasG", foot = "PatteAvantG", phase = 0.25, front = true },
    { upper = "CuisseD", lower = "JambeD", foot = "MetatarseD", toe = "PatteArriereD", phase = 0.5, front = false },
    { upper = "EpauleD", lower = "AvantBrasD", foot = "PatteAvantD", phase = 0.75, front = true },
}

-- Axes du chat exprimes dans le repere de l'os : lateral (droite du chat) et vertical (haut du chat).
type BoneAxes = { bone: Bone, lateral: Vector3, vertical: Vector3 }

type State = {
    model: Model,
    bones: { [string]: BoneAxes },
    last: Vector3,
    cycle: number,
    amount: number,
    speed: number,
    stride: number,
}

local CatWalkController = {}

local function collectBones(model: Model): { [string]: BoneAxes }
    local pivot = model:GetPivot()
    local bones: { [string]: BoneAxes } = {}
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("Bone") then
            descendant.Transform = CFrame.identity
            local rest = descendant.WorldCFrame.Rotation
            bones[descendant.Name] = {
                bone = descendant,
                lateral = rest:VectorToObjectSpace(pivot.RightVector).Unit,
                vertical = rest:VectorToObjectSpace(pivot.UpVector).Unit,
            }
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

-- pitch : rotation autour de l'axe lateral du chat (positif = l'extremite de l'os part vers l'avant pour un os qui
-- descend) ; yaw : rotation autour de l'axe vertical du chat.
local function pose(bones: { [string]: BoneAxes }, name: string, pitch: number, yaw: number?): ()
    local entry = bones[name]
    if entry then
        entry.bone.Transform = CFrame.fromAxisAngle(entry.lateral, pitch)
            * CFrame.fromAxisAngle(entry.vertical, yaw or 0)
    end
end

local function animate(state: State): ()
    local bones, cycle, amount = state.bones, state.cycle, state.amount
    for _, leg in LEGS do
        local swing, lift = legCurve(cycle + leg.phase)
        swing *= amount
        lift *= amount
        if leg.front then
            pose(bones, leg.upper, math.rad(30) * swing)
            pose(bones, leg.lower, math.rad(-55) * lift)
            pose(bones, leg.foot, math.rad(-45) * lift)
        else
            pose(bones, leg.upper, math.rad(28) * swing)
            pose(bones, leg.lower, math.rad(-45) * lift)
            pose(bones, leg.foot, math.rad(50) * lift)
            if leg.toe then
                pose(bones, leg.toe, math.rad(-25) * lift)
            end
        end
    end
    local wave = math.sin(cycle * math.pi * 2) * amount
    local bob = math.sin(cycle * math.pi * 4) * amount
    pose(bones, "Racine", math.rad(2) * bob, math.rad(5) * wave)
    pose(bones, "ColonneLombaire", math.rad(-2) * bob, math.rad(-4) * wave)
    pose(bones, "ColonneThoracique", math.rad(1.5) * bob, math.rad(-3) * wave)
    pose(bones, "Cou", math.rad(-3) * bob, math.rad(3) * wave)
    pose(bones, "Tete", math.rad(2) * bob, math.rad(-4) * wave)
    for index, name in { "Queue1", "Queue2", "Queue3" } do
        local lag = math.sin((cycle - index * 0.12) * math.pi * 2)
        pose(bones, name, math.rad(-10) * amount, math.rad(8 + index * 7) * lag * amount)
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
                bones = collectBones(found),
                last = found:GetPivot().Position,
                cycle = 0,
                amount = 0,
                speed = 0,
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
        -- le serveur deplace le chat 20 fois par seconde : vitesse lissee, sinon la marche se coupait une image sur deux
        local instant = if dt > 0 then moved / dt else 0
        current.speed += (instant - current.speed) * math.min(dt * 4, 1)
        local target = if current.speed > MOVING_SPEED then 1 else 0
        current.amount += (target - current.amount) * math.min(dt * 5, 1)
        -- un grand saut (teleportation, respawn du modele) ne fait pas tourner les pattes a toute vitesse
        if moved < current.stride then
            current.cycle = (current.cycle + moved / current.stride) % 1
        end
        animate(current)
    end)
end

return CatWalkController
