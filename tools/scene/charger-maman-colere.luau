-- Charge le modèle 3D « maman en colère » dans ReplicatedStorage.ScreamerModels.MamanColere (jumpscare, Ui/Screamer) :
-- ancré, sans collision, pivot au centre, 12 studs de haut. L'ancien modèle part dans ServerStorage.Archive.
-- Identifiant : assets/models/maman-colere/registry.json (clé maman-colere-hd, 48 000 triangles en 8 morceaux).
local RS = game:GetService("ReplicatedStorage")
local folder = RS:FindFirstChild("ScreamerModels")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "ScreamerModels"
	folder.Parent = RS
end
local ok, objects = pcall(function()
	return game:GetObjects("rbxassetid://84576689767246")
end)
if not ok or not objects[1] then
	return "echec GetObjects : " .. tostring(objects)
end
local root = objects[1]
local model = Instance.new("Model")
model.Name = "MamanColere"
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
local old = folder:FindFirstChild("MamanColere")
if old then
	local archive = game:GetService("ServerStorage"):FindFirstChild("Archive")
	if archive then
		old.Name = "MamanColere_avant_hd"
		old.Parent = archive
	end
end
local _, size = model:GetBoundingBox()
local scale = 12 / math.max(size.Y, 0.001)
model:ScaleTo(scale)
local cf, size2 = model:GetBoundingBox()
model.WorldPivot = CFrame.new(cf.Position)
model:PivotTo(CFrame.new())
model.Parent = folder
return string.format("ok parts=%d taille=%.1fx%.1fx%.1f echelle=%.3f", parts, size2.X, size2.Y, size2.Z, scale)
