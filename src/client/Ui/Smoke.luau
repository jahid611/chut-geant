--!strict

--[[
    Smoke
    Fumee noire au sol (retour utilisateur du 15/09, image de reference : fumee sombre et ronde, sans bord net) pour
    les zones d'ombre (EventController) et l'ombre de la main geante (HandChaseController) : grosses volutes tres
    sombres, lentes, qui ne s'eclairent pas (LightInfluence 0, LightEmission 0) et s'effacent en douceur. Texture de
    fumee integree a Roblox : aucun televersement.

        local emitter = Smoke.emitter(part, rayon, debit)
        emitter.Enabled = true
]]

local Smoke = {}

Smoke.COLOR = Color3.fromRGB(6, 5, 10)
local TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- Emetteur desactive a la creation, sur une piece plate dont la surface donne la zone d'emission.
function Smoke.emitter(parent: BasePart, radius: number, rate: number): ParticleEmitter
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "FumeeNoire"
    emitter.Texture = TEXTURE
    emitter.Color = ColorSequence.new(Smoke.COLOR)
    emitter.LightEmission = 0
    emitter.LightInfluence = 0
    local puff = math.clamp(radius * 0.55, 5, 18)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, puff * 0.6),
        NumberSequenceKeypoint.new(0.5, puff),
        NumberSequenceKeypoint.new(1, puff * 1.3),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.25, 0.35),
        NumberSequenceKeypoint.new(0.7, 0.55),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(2.5, 4)
    emitter.Speed = NumberRange.new(0.2, 1)
    emitter.SpreadAngle = Vector2.new(60, 60)
    emitter.Acceleration = Vector3.new(0, 0.5, 0)
    emitter.Drag = 1.2
    emitter.Rotation = NumberRange.new(0, 360)
    emitter.RotSpeed = NumberRange.new(-15, 15)
    emitter.Shape = Enum.ParticleEmitterShape.Box
    emitter.EmissionDirection = Enum.NormalId.Top
    emitter.Rate = rate
    emitter.Enabled = false
    emitter.Parent = parent
    return emitter
end

return Smoke
