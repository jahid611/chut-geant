-- Chat de la maison avec squelette anatomique (tools/rig-chat.py, asset __ASSET_ID__) : remplace le « Low Poly Cat » assis
-- du Creator Store (maillage d'un autre créateur, impossible à découper) dans ServerStorage.DecorModels.HouseCat.
-- EventService le déplace par PivotTo(CFrame.lookAt) : pivot au centre de la boîte, tête vers -Z (LookVector).
-- CatWalkController anime ses os (Bone) côté client. L'ancien modèle part dans l'Archive.
local SS = game:GetService("ServerStorage")
local decor = SS.DecorModels
local ok, objects = pcall(function()
	return game:GetObjects("rbxassetid://__ASSET_ID__")
end)
if not ok or not objects[1] then
	return "echec GetObjects : " .. tostring(objects)
end
local model = Instance.new("Model")
model.Name = "HouseCat"
local root = objects[1]
if root:IsA("Model") or root:IsA("Folder") then
	for _, child in root:GetChildren() do
		child.Parent = model
	end
else
	root.Parent = model
end
local bones, parts = 0, 0
for _, d in model:GetDescendants() do
	if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
		d:Destroy()
	elseif d:IsA("Bone") then
		bones += 1
	elseif d:IsA("BasePart") then
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		parts += 1
	end
end
-- même encombrement que l'ancien chat (80 studs de haut assis) : un chat debout d'environ 115 studs de long
local _, size = model:GetBoundingBox()
model:ScaleTo(115 / math.max(size.X, size.Z, 0.001))
local cf = model:GetBoundingBox()
model.WorldPivot = CFrame.new(cf.Position)
model:PivotTo(CFrame.new())
local old = decor:FindFirstChild("HouseCat")
local archive = SS:FindFirstChild("Archive")
if old and archive then
	old.Name = "HouseCat_lowpoly_assis_avant"
	old.Parent = archive
end
model.Parent = decor
local _, final = model:GetBoundingBox()
return string.format("ok os=%d pieces=%d taille=%.1fx%.1fx%.1f", bones, parts, final.X, final.Y, final.Z)
