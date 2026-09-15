-- Main géante du bébé en 3D (TRELLIS, asset __ASSET_ID__) : ReplicatedStorage.MainGeanteModele, que HandChaseController
-- clone côté client et fait planer au-dessus de l'ombre de la main (« on la voit même pas, que de l'ombre », 15/09).
-- Environ 45 studs dans sa plus grande dimension (l'ombre fait 42 à 60), pivot au centre, sans collision.
-- L'ancien modèle part dans ServerStorage.Archive.
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local ok, objects = pcall(function()
	return game:GetObjects("rbxassetid://__ASSET_ID__")
end)
if not ok or not objects[1] then
	return "echec GetObjects : " .. tostring(objects)
end
local model = Instance.new("Model")
model.Name = "MainGeanteModele"
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
model:ScaleTo(45 / math.max(size.X, size.Y, size.Z, 0.001))
local cf = model:GetBoundingBox()
model.WorldPivot = CFrame.new(cf.Position)
model:PivotTo(CFrame.new())
local old = RS:FindFirstChild("MainGeanteModele")
local archive = SS:FindFirstChild("Archive")
if old and archive then
	old.Name = "MainGeanteModele_avant"
	old.Parent = archive
end
model.Parent = RS
local _, final = model:GetBoundingBox()
return string.format("ok pieces=%d taille=%.1fx%.1fx%.1f", parts, final.X, final.Y, final.Z)
