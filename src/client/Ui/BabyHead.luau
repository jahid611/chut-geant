--!strict

--[[
    BabyHead
    Tete du bebe qui pleure dans un ViewportFrame : copie du modele workspace.Geant.Pleure, posee dans la pose couchee
    de reference « Dort » pour que ses axes soient stables (a la capture, le bebe qui pleure est souvent en train de se
    relever et la camera cadrait le haut de la capuche, capture du 15/09). Couche, le visage regarde le LookVector et
    la tete est du cote UpVector. Utilise par la bulle POV (BabyPovController) et le screamer (Ui/Screamer).

        local head = BabyHead.build(viewport)
        if head then camera.CFrame = CFrame.lookAt(head.point + head.frame.LookVector * head.size.Y * 0.8, head.point) end
]]

local Workspace = game:GetService("Workspace")

local GAZE_NAME = "Regard"

export type Head = {
    -- point vise : le visage
    point: Vector3,
    -- repere du modele couche (LookVector = sortie du visage, UpVector = cote de la tete)
    frame: CFrame,
    size: Vector3,
}

local BabyHead = {}

function BabyHead.build(viewport: ViewportFrame): Head?
    local giant = Workspace:FindFirstChild("Geant")
    local crying = if giant then giant:FindFirstChild("Pleure") else nil
    if crying == nil or not crying:IsA("Model") then
        return nil
    end
    local clone = crying:Clone()
    for _, descendant in clone:GetDescendants() do
        local strip = descendant.Name == GAZE_NAME
            or descendant:IsA("Light")
            or descendant:IsA("LuaSourceContainer")
            or descendant:IsA("ParticleEmitter")
        if strip then
            descendant:Destroy()
        elseif descendant:IsA("BasePart") then
            -- le serveur n'a peut-etre pas encore rendu le bebe qui pleure visible
            descendant.Transparency = 0
            descendant.Anchored = true
        end
    end
    clone.Parent = viewport
    local sleeping = if giant then giant:FindFirstChild("Dort") else nil
    if sleeping and sleeping:IsA("Model") then
        clone:PivotTo(sleeping:GetPivot())
    end
    local center, size = clone:GetBoundingBox()
    -- A 0,36 de la longueur la camera visait le sommet du crane : le visage est plus pres du centre du corps.
    return { point = center.Position + center.UpVector * size.Y * 0.13, frame = center, size = size }
end

return BabyHead
