-- Poing fermé du bébé en 3D (TRELLIS, asset 119643838462750) : ReplicatedStorage.PoingGeanteModele, que HandChaseController
-- met à la place de la main ouverte quand elle attrape un joueur (« elle ferme la main sur lui », 15/09).
-- Environ 32 studs dans sa plus grande dimension (la main ouverte en fait 45, doigts écartés), pivot au centre, sans
-- collision. La rotation posée plus bas remet le poing dans la convention de MainGeanteModele pour HAND_ROTATION.
-- L'ancien modèle part dans ServerStorage.Archive.
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local ok, objects = pcall(function()
	return game:GetObjects("rbxassetid://119643838462750")
end)
if not ok or not objects[1] then
	return "echec GetObjects : " .. tostring(objects)
end
local model = Instance.new("Model")
model.Name = "PoingGeanteModele"
local root = objects[1]
if root:IsA("Model") or root:IsA("Folder") then
	for _, child in root:GetChildren() do
		child.Parent = model
	end
else
	root.Parent = model
end
local parts = 0
for _, d in model:GetDescendants() do
	if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
		d:Destroy()
	elseif d:IsA("BasePart") then
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		parts += 1
	end
end
local _, size = model:GetBoundingBox()
model:ScaleTo(32 / math.max(size.X, size.Y, size.Z, 0.001))
local cf = model:GetBoundingBox()
model.WorldPivot = CFrame.new(cf.Position)
-- Planche des rotations du 15/09 : dos de la main en haut, doigts repliés dessous, poignet du même côté que la main
-- ouverte une fois HAND_ROTATION appliquée.
model:PivotTo(CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, math.pi, 0))
local center = model:GetBoundingBox()
model.WorldPivot = CFrame.new(center.Position)
model:PivotTo(CFrame.new())
local old = RS:FindFirstChild("PoingGeanteModele")
local archive = SS:FindFirstChild("Archive")
if old and archive then
	old.Name = "PoingGeanteModele_avant"
	old.Parent = archive
end
model.Parent = RS
local _, final = model:GetBoundingBox()
return string.format("ok pieces=%d taille=%.1fx%.1fx%.1f", parts, final.X, final.Y, final.Z)
