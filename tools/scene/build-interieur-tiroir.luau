-- Interieur du tiroir (base « Drawer », zone Base5 de la chambre) : on est au fond d'un tiroir de commode en bois,
-- entrouvert. Des montagnes de chaussettes colorees, des pelotes de laine, des boutons geants, et une lame de
-- lumiere chaude qui entre par la fente du tiroir. L'ambiance est appliquee par AmbianceController (« Tiroir »).
--
-- A lancer APRES build-chambre.luau (qui recree la zone Base5 dans la chambre) :
--   node tools/scene-run.mjs tools/scene/build-interieur-tiroir.luau
-- Un ancien interieur est range dans ServerStorage.Archive, sans ses tags.

local CS = game:GetService("CollectionService")
local SS = game:GetService("ServerStorage")

local out = {}
local NAME = "InterieurTiroir"
local ORIGIN = Vector3.new(6400, -900, 0)
local W, H, D = 380, 150, 420
local ZONE_NAMES = { "Base4Tiroir", "Base5" }
local ZONE_NEW = "Base4Tiroir"
local BASE_MODEL = "Base_Drawer"
local AMBIANCE = "Tiroir"
local rng = Random.new(20260918)
local warm = Color3.fromRGB(255, 222, 170)

local archive = SS:FindFirstChild("Archive") or Instance.new("Folder")
archive.Name = "Archive"
archive.Parent = SS
local old = workspace:FindFirstChild(NAME)
if old then
	for _, d in old:GetDescendants() do
		for _, tag in CS:GetTags(d) do
			CS:RemoveTag(d, tag)
		end
	end
	old.Name = NAME .. "_" .. os.time()
	old.Parent = archive
end

local room = Instance.new("Model")
room.Name = NAME
room.Parent = workspace

local function part(parent, name, size, cframe, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props or {} do
		p[k] = v
	end
	p.Parent = parent
	return p
end
local function invisible(parent, name, cframe, size)
	return part(parent, name, size or Vector3.new(1, 1, 1), cframe, Color3.new(1, 1, 1), nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
end
local function blob(parent, name, size, cframe, color, material, props)
	local p = part(parent, name, size, cframe, color, material, props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end
local function at(x, y, z)
	return CFrame.new(ORIGIN + Vector3.new(x, y, z))
end
local function inPath(x, z)
	return x < -55 and z < 25
end

-- 1. Le tiroir en bois : fond en lattes, parois, dessous du meuble au-dessus avec une fente de lumiere a l'avant.
local structure = Instance.new("Folder")
structure.Name = "Tiroir"
structure.Parent = room
local wood = Color3.fromRGB(196, 150, 104)
part(structure, "FondTiroir", Vector3.new(W, 4, D), at(0, -2, 0), Color3.fromRGB(214, 172, 124), Enum.Material.WoodPlanks)
part(structure, "ParoiFond", Vector3.new(W, H, 8), at(0, H / 2, -D / 2 - 4), wood, Enum.Material.Wood)
part(structure, "ParoiAvant", Vector3.new(W, H, 8), at(0, H / 2, D / 2 + 4), Color3.fromRGB(176, 130, 88), Enum.Material.Wood)
part(structure, "ParoiGauche", Vector3.new(8, H, D), at(-W / 2 - 4, H / 2, 0), wood, Enum.Material.Wood)
part(structure, "ParoiDroite", Vector3.new(8, H, D), at(W / 2 + 4, H / 2, 0), wood, Enum.Material.Wood)
-- dessous du meuble : tout le plafond sauf une fente de 26 studs le long de la paroi avant (tiroir entrouvert)
local SLIT = 26
part(structure, "DessousMeuble", Vector3.new(W + 16, 8, D - SLIT), at(0, H + 14, -SLIT / 2), Color3.fromRGB(120, 86, 58), Enum.Material.Wood)
local slitLight = part(room, "Fente", Vector3.new(W, 1, SLIT - 2), at(0, H + 40, D / 2 - SLIT / 2), Color3.fromRGB(255, 236, 200), Enum.Material.Neon, { CanCollide = false, CastShadow = false })
local sfl = Instance.new("SurfaceLight")
sfl.Face = Enum.NormalId.Bottom
sfl.Color = warm
sfl.Brightness = 1.4
sfl.Range = 60
sfl.Angle = 90
sfl.Parent = slitLight
-- lame de lumiere : projecteurs alignes sous la fente, penches vers le fond du tiroir
for i = 0, 4 do
	local x = -W / 2 + 40 + i * (W - 80) / 4
	local src = invisible(room, "LameLumiere" .. i, CFrame.lookAt(ORIGIN + Vector3.new(x, H + 10, D / 2 - SLIT / 2), ORIGIN + Vector3.new(x * 0.8, 0, D / 2 - 170)))
	local sl = Instance.new("SpotLight")
	sl.Face = Enum.NormalId.Front
	sl.Color = warm
	sl.Brightness = 1.8
	sl.Range = 60
	sl.Angle = 45
	sl.Shadows = true
	sl.Parent = src
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(255, 236, 200))
	dust.LightEmission = 0.7
	dust.Transparency = NumberSequence.new(0.5, 1)
	dust.Size = NumberSequence.new(0.22)
	dust.Lifetime = NumberRange.new(5, 8)
	dust.Rate = 3
	dust.Speed = NumberRange.new(2, 4)
	dust.SpreadAngle = Vector2.new(20, 20)
	dust.EmissionDirection = Enum.NormalId.Front
	dust.Parent = src
end
for i, g in {
	{ Vector3.new(0, 14, -D / 2 + 30), Enum.NormalId.Front, Vector3.new(W, 4, 2) },
	{ Vector3.new(-W / 2 + 30, 14, 0), Enum.NormalId.Left, Vector3.new(2, 4, D) },
	{ Vector3.new(W / 2 - 30, 14, 0), Enum.NormalId.Right, Vector3.new(2, 4, D) },
} do
	local p = invisible(room, "LueurParoi" .. i, CFrame.new(ORIGIN + g[1]), g[3])
	local sl = Instance.new("SurfaceLight")
	sl.Face = g[2]
	sl.Color = Color3.fromRGB(255, 210, 170)
	sl.Brightness = 0.9
	sl.Range = 60
	sl.Angle = 80
	sl.Parent = p
end
table.insert(out, "tiroir en bois et fente de lumiere")

-- 2. Montagnes de chaussettes : chaque chaussette = tube a rayures + talon + bout arrondis, empilees en tas.
local socks = Instance.new("Folder")
socks.Name = "Chaussettes"
socks.Parent = room
local palette = {
	{ Color3.fromRGB(240, 120, 150), Color3.fromRGB(255, 236, 240) },
	{ Color3.fromRGB(110, 170, 240), Color3.fromRGB(240, 246, 255) },
	{ Color3.fromRGB(120, 200, 140), Color3.fromRGB(250, 236, 120) },
	{ Color3.fromRGB(250, 180, 80), Color3.fromRGB(120, 80, 60) },
	{ Color3.fromRGB(170, 120, 220), Color3.fromRGB(250, 250, 250) },
	{ Color3.fromRGB(230, 80, 70), Color3.fromRGB(255, 255, 255) },
}
local function sock(cf, length, colors)
	local radius = 6
	local stripes = 5
	for s = 0, stripes - 1 do
		local segment = length / stripes
		local localX = -length / 2 + segment * (s + 0.5)
		part(socks, "Tube", Vector3.new(segment + 0.2, radius * 2, radius * 2), cf * CFrame.new(localX, 0, 0), colors[(s % 2) + 1], Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	-- talon et bout du pied, dans la couleur principale
	part(socks, "Talon", Vector3.new(radius * 2.2, radius * 2.2, radius * 2.2), cf * CFrame.new(length / 2, -2, 0), colors[1], Enum.Material.Fabric, { Shape = Enum.PartType.Ball, CanCollide = false })
	blob(socks, "Pied", Vector3.new(24, radius * 1.9, radius * 2), cf * CFrame.new(length / 2 + 6, -7, 0) * CFrame.Angles(0, 0, math.rad(-70)), colors[1], Enum.Material.Fabric, { CanCollide = false })
	-- revers elastique
	part(socks, "Revers", Vector3.new(4, radius * 2.3, radius * 2.3), cf * CFrame.new(-length / 2, 0, 0), colors[2], Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
end
local piles = { Vector2.new(60, 90), Vector2.new(-120, 120), Vector2.new(120, -60), Vector2.new(20, -160), Vector2.new(140, 150) }
for p, center in piles do
	local count = rng:NextInteger(9, 14)
	-- butte de chaussettes en boule sous le tas (donne la forme de montagne)
	blob(socks, "BaseTas", Vector3.new(90, 26, 80), at(center.X, 8, center.Y), palette[(p % #palette) + 1][1], Enum.Material.Fabric, { CanCollide = false })
	for i = 1, count do
		local t = i / count
		local r = (1 - t) * 38
		local a = rng:NextNumber(0, math.pi * 2)
		local cf = at(center.X + math.cos(a) * r, 10 + t * 42 + rng:NextNumber(-3, 3), center.Y + math.sin(a) * r)
			* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-25, 25)))
		sock(cf, rng:NextNumber(30, 44), palette[rng:NextInteger(1, #palette)])
	end
end
-- quelques chaussettes isolees par terre
for i = 1, 10 do
	local x = rng:NextNumber(-W / 2 + 30, W / 2 - 30)
	local z = rng:NextNumber(-D / 2 + 30, D / 2 - 40)
	if not inPath(x, z) then
		sock(at(x, 6, z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0), rng:NextNumber(30, 40), palette[rng:NextInteger(1, #palette)])
	end
end
table.insert(out, "montagnes de chaussettes")

-- 3. Pelotes de laine avec leur fil qui traine.
local yarn = Instance.new("Folder")
yarn.Name = "PelotesDeLaine"
yarn.Parent = room
local yarnColors = { Color3.fromRGB(255, 160, 190), Color3.fromRGB(150, 210, 250), Color3.fromRGB(250, 220, 120), Color3.fromRGB(180, 230, 170), Color3.fromRGB(210, 170, 240) }
for i = 1, 8 do
	local x = rng:NextNumber(-W / 2 + 40, W / 2 - 40)
	local z = rng:NextNumber(-D / 2 + 40, D / 2 - 50)
	if not inPath(x, z) then
		local size = rng:NextNumber(16, 28)
		local color = yarnColors[rng:NextInteger(1, #yarnColors)]
		part(yarn, "Pelote", Vector3.new(size, size, size), at(x, size / 2, z), color, Enum.Material.Fabric)
		-- brins enroules visibles sur la pelote
		for k = 1, 6 do
			part(yarn, "Brin", Vector3.new(size * 1.02, 1, size * 0.9), at(x, size / 2, z) * CFrame.Angles(math.rad(rng:NextNumber(0, 180)), math.rad(rng:NextNumber(0, 180)), 0), Color3.new(color.R * 0.85, color.G * 0.85, color.B * 0.85), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		end
		local prev = ORIGIN + Vector3.new(x, 1.2, z)
		local dir = rng:NextNumber(0, math.pi * 2)
		for s = 1, 10 do
			dir += rng:NextNumber(-0.6, 0.6)
			local nextPos = prev + Vector3.new(math.cos(dir) * 9, 0, math.sin(dir) * 9)
			local mid = (prev + nextPos) / 2
			part(yarn, "Fil", Vector3.new(10, 1.6, 1.6), CFrame.lookAt(mid, nextPos) * CFrame.Angles(0, math.rad(90), 0), color, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
			prev = nextPos
		end
	end
end
table.insert(out, "pelotes de laine")

-- 4. Boutons geants a quatre trous.
local buttons = Instance.new("Folder")
buttons.Name = "Boutons"
buttons.Parent = room
local buttonColors = { Color3.fromRGB(230, 70, 90), Color3.fromRGB(60, 130, 220), Color3.fromRGB(250, 200, 60), Color3.fromRGB(90, 190, 120), Color3.fromRGB(245, 245, 240) }
for i = 1, 11 do
	local x = rng:NextNumber(-W / 2 + 30, W / 2 - 30)
	local z = rng:NextNumber(-D / 2 + 30, D / 2 - 40)
	if not inPath(x, z) then
		local diameter = rng:NextNumber(20, 38)
		local tilt = if i % 3 == 0 then math.rad(rng:NextNumber(55, 75)) else math.rad(rng:NextNumber(0, 8))
		local cf = at(x, if i % 3 == 0 then diameter / 2 else 1.6, z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0) * CFrame.Angles(tilt, 0, 0)
		local color = buttonColors[rng:NextInteger(1, #buttonColors)]
		part(buttons, "Bouton", Vector3.new(3, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Plastic, { Shape = Enum.PartType.Cylinder })
		part(buttons, "Rebord", Vector3.new(3.6, diameter * 0.2, diameter * 0.2), cf * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Plastic, { Shape = Enum.PartType.Cylinder, Transparency = 1, CanCollide = false })
		for hx = -1, 1, 2 do
			for hz = -1, 1, 2 do
				part(buttons, "Trou", Vector3.new(3.4, diameter * 0.12, diameter * 0.12), cf * CFrame.new(hx * diameter * 0.12, 0.2, hz * diameter * 0.12) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 30, 30), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, CanCollide = false })
			end
		end
	end
end
table.insert(out, "boutons geants")

-- 5. La boite a jouets, les lumieres, et la zone de base devant.
local ccf, cs
local chestSrc = SS:FindFirstChild("DecorModels") and SS.DecorModels:FindFirstChild("ToyChest")
if chestSrc then
	local chest = chestSrc:Clone()
	local _, s0 = chest:GetBoundingBox()
	chest:ScaleTo(chest:GetScale() * (70 / math.max(s0.X, s0.Y, s0.Z)))
	local _, s = chest:GetBoundingBox()
	chest:PivotTo(CFrame.new(ORIGIN.X - 120, ORIGIN.Y + 1 + s.Y / 2, ORIGIN.Z - D / 2 + 70) * CFrame.Angles(0, math.rad(180), 0))
	chest.Parent = room
	ccf, cs = chest:GetBoundingBox()
	chest:Destroy()

	local spot = invisible(room, "ProjecteurBoite", CFrame.lookAt(ccf.Position + Vector3.new(0, 55, 30), ccf.Position))
	local sl = Instance.new("SpotLight")
	sl.Face = Enum.NormalId.Front
	sl.Color = Color3.fromRGB(255, 215, 140)
	sl.Brightness = 1.2
	sl.Range = 60
	sl.Angle = 60
	sl.Shadows = true
	sl.Parent = spot
	local glow = invisible(room, "LueurBoite", CFrame.new(ccf.Position + Vector3.new(0, cs.Y * 0.25, 0)))
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(255, 200, 110)
	pl.Brightness = 0.7
	pl.Range = 50
	pl.Parent = glow
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Lifetime = NumberRange.new(1.5, 2.5)
	sparkle.Rate = 10
	sparkle.Speed = NumberRange.new(2, 5)
	sparkle.SpreadAngle = Vector2.new(35, 35)
	sparkle.Parent = glow
	local sign = invisible(room, "PanneauBoite", CFrame.new(ccf.Position + Vector3.new(0, cs.Y / 2 + 18, 0)))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(360, 70)
	gui.MaxDistance = 500
	gui.LightInfluence = 0
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "BOÎTE À JOUETS"
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 214, 102)
	label.TextStrokeColor3 = Color3.fromRGB(40, 30, 20)
	label.TextStrokeTransparency = 0
	label.Parent = gui

	local zones = workspace:FindFirstChild("Chambre") and workspace.Chambre:FindFirstChild("Zones")
	local baseZone = nil
	for _, n in ZONE_NAMES do
		baseZone = baseZone or (zones and zones:FindFirstChild(n))
	end
	if baseZone then
		baseZone.Name = ZONE_NEW
		baseZone.Size = Vector3.new(90, 40, 70)
		baseZone.CFrame = CFrame.new(ccf.Position.X, ORIGIN.Y + 20, ccf.Position.Z + cs.Z / 2 + 30)
		baseZone:SetAttribute("DisplayCFrame", nil)
		baseZone:SetAttribute("DisplaySize", nil)
		baseZone:SetAttribute("ChestCFrame", CFrame.new(ccf.Position.X, ccf.Position.Y - cs.Y / 2, ccf.Position.Z) * CFrame.Angles(0, math.rad(180), 0))
		baseZone:SetAttribute("ChestStep", Vector3.new(80, 0, 0))
		baseZone:SetAttribute("ChestSize", 70)
		table.insert(out, ZONE_NEW .. " devant la boite a jouets")
	else
		table.insert(out, "zone de base introuvable : lancer build-chambre.luau d'abord")
	end
else
	table.insert(out, "manque DecorModels.ToyChest")
end

-- 6. Portes.
local arrival = Vector3.new(ORIGIN.X - 135, ORIGIN.Y + 4, ORIGIN.Z - D / 2 + 165)
local exitPos = Vector3.new(ORIGIN.X - 120, ORIGIN.Y + 7, ORIGIN.Z - D / 2 + 165)
local exitOrb = part(room, "LumiereSortie", Vector3.new(3, 3, 3), CFrame.new(exitPos), Color3.fromRGB(170, 190, 255), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false, CastShadow = false })
local exitLight = Instance.new("PointLight")
exitLight.Color = Color3.fromRGB(170, 190, 255)
exitLight.Brightness = 0.8
exitLight.Range = 18
exitLight.Parent = exitOrb
local exitHalo = Instance.new("ParticleEmitter")
exitHalo.Texture = "rbxasset://textures/particles/sparkles_main.dds"
exitHalo.Color = ColorSequence.new(Color3.fromRGB(190, 205, 255))
exitHalo.LightEmission = 1
exitHalo.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
exitHalo.Lifetime = NumberRange.new(1, 2)
exitHalo.Rate = 12
exitHalo.Speed = NumberRange.new(1, 3)
exitHalo.SpreadAngle = Vector2.new(180, 180)
exitHalo.Parent = exitOrb
local exitLabel = Instance.new("BillboardGui")
exitLabel.Size = UDim2.fromOffset(220, 40)
exitLabel.StudsOffset = Vector3.new(0, 8, 0)
exitLabel.MaxDistance = 120
exitLabel.LightInfluence = 0
exitLabel.Parent = exitOrb
local exitText = Instance.new("TextLabel")
exitText.Size = UDim2.fromScale(1, 1)
exitText.BackgroundTransparency = 1
exitText.Text = "Retour chambre"
exitText.Font = Enum.Font.FredokaOne
exitText.TextScaled = true
exitText.TextColor3 = Color3.fromRGB(200, 215, 255)
exitText.TextStrokeTransparency = 0.4
exitText.Parent = exitLabel

local baseModel = workspace:FindFirstChild("Chambre") and workspace.Chambre.Decor:FindFirstChild(BASE_MODEL)
if baseModel then
	local bcf, bs = baseModel:GetBoundingBox()
	local front = bcf.Position.Z - bs.Z / 2
	local outsidePos = Vector3.new(bcf.Position.X, 4, front - 22)
	local doorW, doorH = math.min(bs.X * 0.45, 9), math.min(bs.Y * 0.4, 8)
	local doorFolder = Instance.new("Folder")
	doorFolder.Name = "PorteDessinee"
	doorFolder.Parent = room
	local doorCenter = Vector3.new(bcf.Position.X, doorH / 2 + 1, front - 0.3)
	part(doorFolder, "Seuil", Vector3.new(doorW, doorH, 0.4), CFrame.new(doorCenter), Color3.fromRGB(50, 34, 20), Enum.Material.SmoothPlastic, { CanCollide = false, CastShadow = false })
	for _, edge in {
		{ Vector3.new(doorW + 1, 0.8, 0.6), Vector3.new(0, doorH / 2, 0) },
		{ Vector3.new(0.8, doorH, 0.6), Vector3.new(-doorW / 2, 0, 0) },
		{ Vector3.new(0.8, doorH, 0.6), Vector3.new(doorW / 2, 0, 0) },
	} do
		part(doorFolder, "Cadre", edge[1], CFrame.new(doorCenter + edge[2] - Vector3.new(0, 0, 0.2)), warm, Enum.Material.Neon, { CanCollide = false, CastShadow = false })
	end
	local doorGlow = invisible(doorFolder, "LueurPorte", CFrame.new(doorCenter - Vector3.new(0, 0, 3)))
	local dl = Instance.new("PointLight")
	dl.Color = warm
	dl.Brightness = 1
	dl.Range = 14
	dl.Parent = doorGlow
	local entree = invisible(room, "PorteEntreeTiroir", CFrame.new(bcf.Position.X, 5, front + 1), Vector3.new(bs.X * 0.8, 10, 8))
	entree.CanTouch = true
	entree:SetAttribute("Destination", CFrame.lookAt(arrival, Vector3.new(ORIGIN.X - 120, arrival.Y, ORIGIN.Z - D / 2 + 70)))
	CS:AddTag(entree, "BaseDoor")
	local sortie = invisible(room, "PorteSortieTiroir", CFrame.new(exitPos), Vector3.new(6, 14, 6))
	sortie.CanTouch = true
	sortie:SetAttribute("Destination", CFrame.lookAt(outsidePos, outsidePos + Vector3.new(0, 0, -1)))
	CS:AddTag(sortie, "BaseDoor")
	table.insert(out, "portes ok")
else
	table.insert(out, BASE_MODEL .. " introuvable dans la chambre")
end

local zone = invisible(room, "ZoneInterieurTiroir", CFrame.new(ORIGIN + Vector3.new(0, H / 2, 0)), Vector3.new(W + 20, H + 60, D + 20))
CS:AddTag(zone, "InteriorZone")
zone:SetAttribute("Ambiance", AMBIANCE)

local count = 0
for _, d in room:GetDescendants() do
	if d:IsA("BasePart") then
		d.Locked = true
		count += 1
	end
end
table.insert(out, "interieur tiroir ok (" .. count .. " pieces)")
return table.concat(out, " | ")
