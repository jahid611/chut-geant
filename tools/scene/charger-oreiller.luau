-- Remplace l'oreiller-arme (une simple Part en marbre, contraire à la règle « pas de pièces de base ») par le vrai
-- modèle 3D (TRELLIS, asset __ASSET_ID__) : ServerStorage.WeaponModels.WeaponPillow devient un Model dont la
-- MeshPart est la poignée ; WeaponService en fait l'outil et calcule la prise en main. L'ancien part dans l'Archive.
local SS = game:GetService("ServerStorage")
local folder = SS.WeaponModels
local ok, objects = pcall(function()
	return game:GetObjects("rbxassetid://__ASSET_ID__")
end)
if not ok or not objects[1] then
	return "echec GetObjects : " .. tostring(objects)
end
local model = Instance.new("Model")
model.Name = "WeaponPillow"
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
		d.Anchored = false
		d.CanCollide = false
		d.Massless = true
		parts += 1
	end
end
-- un oreiller qu'un petit voleur tient à deux mains : environ 3,6 studs de long
local _, size = model:GetBoundingBox()
model:ScaleTo(3.6 / math.max(size.X, size.Y, size.Z, 0.001))
local cf = model:GetBoundingBox()
model.WorldPivot = CFrame.new(cf.Position)
model:PivotTo(CFrame.new())
local old = folder:FindFirstChild("WeaponPillow")
local archive = SS:FindFirstChild("Archive")
if old and archive then
	old.Name = "WeaponPillow_marbre_avant"
	old.Parent = archive
end
model.Parent = folder
local _, final = model:GetBoundingBox()
return string.format("ok pieces=%d taille=%.2fx%.2fx%.2f", parts, final.X, final.Y, final.Z)
