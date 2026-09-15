--!strict

--[[
    Zone
    Utilitaires purs sur des volumes definis par des BasePart (bases, chambre du geant).
]]

local Zone = {}

-- Vrai si la position est a l'interieur du volume de la piece (rotation comprise).
function Zone.Contains(part: BasePart, position: Vector3): boolean
    local localPos = part.CFrame:PointToObjectSpace(position)
    local half = part.Size / 2
    return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

-- La piece principale d'un jouet : lui-meme s'il est une BasePart, sinon la PrimaryPart
-- ou la premiere BasePart trouvee dans le modele.
function Zone.PrimaryPart(instance: Instance): BasePart?
    if instance:IsA("BasePart") then
        return instance
    end
    if instance:IsA("Model") and instance.PrimaryPart then
        return instance.PrimaryPart
    end
    return instance:FindFirstChildWhichIsA("BasePart", true)
end

return table.freeze(Zone)
