-- Interieur du carton de demenagement (base « MovingBox », zone Base6 de la chambre) : on est au fond d'un grand
-- carton a moitie rempli. Du papier bulle geant, des chips de calage en polystyrene, des rubans adhesifs, des objets
-- emballes, et la lumiere froide de la nuit qui entre par les rabats ouverts. Ambiance : AmbianceController (« Carton »).
--
-- A lancer APRES build-chambre.luau (qui recree la zone Base6 dans la chambre) :
--   node tools/scene-run.mjs tools/scene/build-interieur-carton.luau
-- Un ancien interieur est range dans ServerStorage.Archive, sans ses tags.

local CS = game:GetService("CollectionService")
local SS = game:GetService("ServerStorage")

local out = {}
local NAME = "InterieurCarton"
local ORIGIN = Vector3.new(8000, -900, 0)
local W, H, D = 380, 190, 420
local ZONE_NAMES = { "Base5Carton", "Base6" }
local ZONE_NEW = "Base5Carton"
local BASE_MODEL = "Base_MovingBox"
local AMBIANCE = "Carton"
local rng = Random.new(20260919)
local cool = Color3.fromRGB(175, 200, 255)

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

-- 1. Le carton : parois en carton brun ondule, fond, rabats ouverts en haut.
local structure = Instance.new("Folder")
structure.Name = "Carton"
structure.Parent = room
local brown = Color3.fromRGB(168, 122, 78)
-- fond plus clair : en 140,100,64 il sortait noir sous la lumiere froide (capture carton-vue)
part(structure, "FondCarton", Vector3.new(W, 4, D), at(0, -2, 0), Color3.fromRGB(205, 160, 112), Enum.Material.Cardboard)
-- lumieres douces au ras du sol, pour que le fond et les objets restent lisibles loin des rayons de lune
for i, p in { Vector3.new(-100, 40, -100), Vector3.new(100, 40, -100), Vector3.new(-100, 40, 110), Vector3.new(100, 40, 110), Vector3.new(0, 40, 0) } do
	local src = Instance.new("Part")
	src.Name = "LumiereSol" .. i
	src.Anchored = true
	src.Transparency = 1
	src.CanCollide = false
	src.CanQuery = false
	src.CanTouch = false
	src.Size = Vector3.new(1, 1, 1)
	src.CFrame = at(p.X, p.Y, p.Z)
	src.Parent = room
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(235, 225, 210)
	pl.Brightness = 0.9
	pl.Range = 60
	pl.Parent = src
end
part(structure, "ParoiFond", Vector3.new(W, H, 6), at(0, H / 2, -D / 2 - 3), brown, Enum.Material.Cardboard)
part(structure, "ParoiAvant", Vector3.new(W, H, 6), at(0, H / 2, D / 2 + 3), brown, Enum.Material.Cardboard)
part(structure, "ParoiGauche", Vector3.new(6, H, D), at(-W / 2 - 3, H / 2, 0), Color3.fromRGB(156, 112, 72), Enum.Material.Cardboard)
part(structure, "ParoiDroite", Vector3.new(6, H, D), at(W / 2 + 3, H / 2, 0), Color3.fromRGB(156, 112, 72), Enum.Material.Cardboard)
-- cannelures du carton ondule : fines lignes verticales sur les parois
for i = 0, 22 do
	local x = -W / 2 + 10 + i * (W - 20) / 22
	part(structure, "Cannelure", Vector3.new(1, H - 10, 0.6), at(x, H / 2, -D / 2 + 0.2), Color3.fromRGB(150, 108, 68), Enum.Material.Cardboard, { CanCollide = false })
end
-- rabats du dessus ouverts vers l'exterieur, laissant voir la nuit
for side = -1, 1, 2 do
	part(structure, "RabatLong", Vector3.new(W + 6, 4, 150), at(0, H + 55, side * (D / 2 + 60)) * CFrame.Angles(math.rad(side * 58), 0, 0), Color3.fromRGB(150, 108, 68), Enum.Material.Cardboard)
	part(structure, "RabatCourt", Vector3.new(140, 4, D + 6), at(side * (W / 2 + 55), H + 50, 0) * CFrame.Angles(0, 0, math.rad(-side * 62)), Color3.fromRGB(140, 100, 62), Enum.Material.Cardboard)
end
-- la nuit au-dessus : panneau bleu sombre eclaire par-dessous, et un faisceau de lune
local sky = part(room, "CielNuit", Vector3.new(W + 200, 2, D + 200), at(0, H + 140, 0), Color3.fromRGB(40, 52, 90), Enum.Material.SmoothPlastic, { CastShadow = false })
local skyLight = Instance.new("SurfaceLight")
skyLight.Face = Enum.NormalId.Bottom
skyLight.Color = cool
skyLight.Brightness = 0.6
skyLight.Range = 60
skyLight.Angle = 90
skyLight.Parent = sky
for i, off in { Vector3.new(-60, 0, -40), Vector3.new(70, 0, 60), Vector3.new(0, 0, -150) } do
	local shaft = invisible(room, "RayonLune" .. i, CFrame.lookAt(ORIGIN + Vector3.new(off.X, H + 20, off.Z), ORIGIN + Vector3.new(off.X * 0.7, 0, off.Z * 0.7)))
	local sl = Instance.new("SpotLight")
	sl.Face = Enum.NormalId.Front
	sl.Color = cool
	sl.Brightness = 1.7
	sl.Range = 60
	sl.Angle = 70
	sl.Shadows = true
	sl.Parent = shaft
end
for i, g in {
	{ Vector3.new(0, 14, -D / 2 + 30), Enum.NormalId.Front, Vector3.new(W, 4, 2) },
	{ Vector3.new(0, 14, D / 2 - 30), Enum.NormalId.Back, Vector3.new(W, 4, 2) },
	{ Vector3.new(-W / 2 + 30, 14, 0), Enum.NormalId.Left, Vector3.new(2, 4, D) },
	{ Vector3.new(W / 2 - 30, 14, 0), Enum.NormalId.Right, Vector3.new(2, 4, D) },
} do
	local p = invisible(room, "LueurParoi" .. i, CFrame.new(ORIGIN + g[1]), g[3])
	local sl = Instance.new("SurfaceLight")
	sl.Face = g[2]
	sl.Color = Color3.fromRGB(200, 190, 175)
	sl.Brightness = 1
	sl.Range = 60
	sl.Angle = 80
	sl.Parent = p
end
table.insert(out, "carton et rabats ouverts")

-- 2. Rubans adhesifs : sur les jointures du fond et en travers des parois.
local tape = Instance.new("Folder")
tape.Name = "RubansAdhesifs"
tape.Parent = room
local tapeColor = Color3.fromRGB(214, 176, 112)
local tapeProps = { Transparency = 0.25, Reflectance = 0.12, CanCollide = false }
part(tape, "RubanFond", Vector3.new(W, 0.4, 14), at(0, 0.25, 0), tapeColor, Enum.Material.SmoothPlastic, tapeProps)
part(tape, "RubanFond", Vector3.new(14, 0.4, D), at(0, 0.3, 0), tapeColor, Enum.Material.SmoothPlastic, tapeProps)
for i, z in { -D / 2 + 0.6, D / 2 - 0.6 } do
	part(tape, "RubanParoi" .. i, Vector3.new(16, H, 0.4), at(0, H / 2, z), tapeColor, Enum.Material.SmoothPlastic, tapeProps)
end
-- rouleau de scotch geant pose au sol
local rollCF = at(-40, 11, 150) * CFrame.Angles(0, 0, math.rad(90))
part(tape, "Rouleau", Vector3.new(22, 60, 60), rollCF, tapeColor, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, Transparency = 0.1, Reflectance = 0.15 })
part(tape, "CoeurRouleau", Vector3.new(22.5, 34, 34), rollCF, Color3.fromRGB(130, 96, 60), Enum.Material.Cardboard, { Shape = Enum.PartType.Cylinder, CanCollide = false })
part(tape, "BoutRuban", Vector3.new(60, 0.4, 20), at(-40, 0.3, 190) * CFrame.Angles(0, math.rad(12), 0), tapeColor, Enum.Material.SmoothPlastic, tapeProps)
table.insert(out, "rubans adhesifs")

-- 3. Papier bulle geant : feuilles transparentes couvertes de bulles, posees et drapees.
local bubbles = Instance.new("Folder")
bubbles.Name = "PapierBulle"
bubbles.Parent = room
local sheets = { { Vector3.new(90, 1.5, -90), 0, 0 }, { Vector3.new(-10, 1.5, 60), 25, 0 }, { Vector3.new(120, 14, 100), -15, 18 }, { Vector3.new(-150, 10, 160), 40, -14 } }
for s, sheet in sheets do
	local cf = at(sheet[1].X, sheet[1].Y, sheet[1].Z) * CFrame.Angles(0, math.rad(sheet[2]), math.rad(sheet[3]))
	-- en Glass les bulles sortaient noires : plastique lisse translucide et brillant
	part(bubbles, "Feuille" .. s, Vector3.new(76, 0.4, 76), cf, Color3.fromRGB(226, 238, 250), Enum.Material.SmoothPlastic, { Transparency = 0.45, Reflectance = 0.15, CanCollide = false, CastShadow = false })
	for bx = 0, 7 do
		for bz = 0, 7 do
			part(bubbles, "Bulle", Vector3.new(6.5, 6.5, 6.5), cf * CFrame.new(-33 + bx * 9.4, 1, -33 + bz * 9.4), Color3.fromRGB(240, 248, 255), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, Transparency = 0.3, Reflectance = 0.25, CanCollide = false, CastShadow = false })
		end
	end
end
table.insert(out, "papier bulle")

-- 4. Chips de calage en polystyrene, en tas et eparpillees.
local peanuts = Instance.new("Folder")
peanuts.Name = "ChipsDeCalage"
peanuts.Parent = room
local function peanut(cf)
	-- chips en forme de huit : deux lobes arrondis
	blob(peanuts, "Chips", Vector3.new(7, 3.4, 4), cf * CFrame.new(-2.4, 0, 0), Color3.fromRGB(246, 244, 238), Enum.Material.Plastic, { CanCollide = false })
	blob(peanuts, "Chips", Vector3.new(7, 3.4, 4), cf * CFrame.new(2.4, 0, 0) * CFrame.Angles(0, math.rad(35), 0), Color3.fromRGB(240, 238, 232), Enum.Material.Plastic, { CanCollide = false })
end
-- le tas en (-150, -60) englobait le point d'arrivee (-135, -45) : le joueur apparaissait dans le polystyrene
-- (capture interieur-carton-avant). Deplace au centre, hors de l'allee arrivee -> boite a jouets.
local heaps = { Vector2.new(10, -20), Vector2.new(150, -150), Vector2.new(140, 170), Vector2.new(-120, 180) }
for _, heap in heaps do
	blob(peanuts, "TasChips", Vector3.new(80, 22, 70), at(heap.X, 6, heap.Y), Color3.fromRGB(236, 234, 228), Enum.Material.Plastic, { CanCollide = false })
	for i = 1, 26 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0, 36)
		local y = 16 - r * 0.28 + rng:NextNumber(0, 5)
		peanut(at(heap.X + math.cos(a) * r, y, heap.Y + math.sin(a) * r * 0.85) * CFrame.Angles(math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(0, 360))))
	end
end
for i = 1, 45 do
	local x = rng:NextNumber(-W / 2 + 15, W / 2 - 15)
	local z = rng:NextNumber(-D / 2 + 15, D / 2 - 15)
	if not inPath(x, z) then
		peanut(at(x, 1.8, z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-20, 20))))
	end
end
table.insert(out, "chips de calage")

-- 5. Objets emballes : colis en papier kraft ficeles de scotch, et une lampe enveloppee de papier bulle.
local parcels = Instance.new("Folder")
parcels.Name = "ObjetsEmballes"
parcels.Parent = room
for i, p in {
	{ Vector3.new(60, 0, 190), Vector3.new(48, 36, 40), 12 },
	{ Vector3.new(160, 0, 20), Vector3.new(40, 52, 34), -20 },
	{ Vector3.new(-160, 0, 60), Vector3.new(56, 30, 44), 30 },
	{ Vector3.new(80, 36, 190), Vector3.new(30, 22, 26), 40 },
} do
	local size = p[2]
	local cf = at(p[1].X, p[1].Y + size.Y / 2, p[1].Z) * CFrame.Angles(0, math.rad(p[3]), 0)
	part(parcels, "Colis" .. i, size, cf, Color3.fromRGB(196, 160, 116), Enum.Material.Fabric)
	part(parcels, "Scotch", Vector3.new(size.X + 0.4, size.Y + 0.4, 5), cf, tapeColor, Enum.Material.SmoothPlastic, { Transparency = 0.2, CanCollide = false })
	part(parcels, "Scotch", Vector3.new(5, size.Y + 0.5, size.Z + 0.4), cf, tapeColor, Enum.Material.SmoothPlastic, { Transparency = 0.2, CanCollide = false })
end
-- lampe emballee : forme de lampe sous une enveloppe de papier bulle
local lampBase = at(-60, 0, -10)
part(parcels, "PiedLampe", Vector3.new(4, 50, 4), lampBase * CFrame.new(0, 25, 0), Color3.fromRGB(230, 220, 200), Enum.Material.SmoothPlastic)
blob(parcels, "AbatJour", Vector3.new(34, 26, 34), lampBase * CFrame.new(0, 56, 0), Color3.fromRGB(250, 230, 190), Enum.Material.Fabric)
blob(parcels, "Enveloppe", Vector3.new(46, 80, 46), lampBase * CFrame.new(0, 40, 0), Color3.fromRGB(226, 238, 250), Enum.Material.Glass, { Transparency = 0.6, Reflectance = 0.25, CanCollide = false, CastShadow = false })
_ = inPath
table.insert(out, "objets emballes")

-- 6. La boite a jouets, les lumieres, et la zone de base devant.
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

-- 7. Portes.
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
	local doorW, doorH = math.min(bs.X * 0.45, 9), math.min(bs.Y * 0.4, 11)
	local doorFolder = Instance.new("Folder")
	doorFolder.Name = "PorteDessinee"
	doorFolder.Parent = room
	local doorCenter = Vector3.new(bcf.Position.X, doorH / 2 + 1, front - 0.3)
	part(doorFolder, "Seuil", Vector3.new(doorW, doorH, 0.4), CFrame.new(doorCenter), Color3.fromRGB(40, 30, 22), Enum.Material.SmoothPlastic, { CanCollide = false, CastShadow = false })
	for _, edge in {
		{ Vector3.new(doorW + 1, 0.8, 0.6), Vector3.new(0, doorH / 2, 0) },
		{ Vector3.new(0.8, doorH, 0.6), Vector3.new(-doorW / 2, 0, 0) },
		{ Vector3.new(0.8, doorH, 0.6), Vector3.new(doorW / 2, 0, 0) },
	} do
		part(doorFolder, "Cadre", edge[1], CFrame.new(doorCenter + edge[2] - Vector3.new(0, 0, 0.2)), cool, Enum.Material.Neon, { CanCollide = false, CastShadow = false })
	end
	local doorGlow = invisible(doorFolder, "LueurPorte", CFrame.new(doorCenter - Vector3.new(0, 0, 3)))
	local dl = Instance.new("PointLight")
	dl.Color = cool
	dl.Brightness = 1
	dl.Range = 14
	dl.Parent = doorGlow
	local entree = invisible(room, "PorteEntreeCarton", CFrame.new(bcf.Position.X, 5, front + 1), Vector3.new(bs.X * 0.8, 10, 8))
	entree.CanTouch = true
	entree:SetAttribute("Destination", CFrame.lookAt(arrival, Vector3.new(ORIGIN.X - 120, arrival.Y, ORIGIN.Z - D / 2 + 70)))
	CS:AddTag(entree, "BaseDoor")
	local sortie = invisible(room, "PorteSortieCarton", CFrame.new(exitPos), Vector3.new(6, 14, 6))
	sortie.CanTouch = true
	sortie:SetAttribute("Destination", CFrame.lookAt(outsidePos, outsidePos + Vector3.new(0, 0, -1)))
	CS:AddTag(sortie, "BaseDoor")
	table.insert(out, "portes ok")
else
	table.insert(out, BASE_MODEL .. " introuvable dans la chambre")
end

local zone = invisible(room, "ZoneInterieurCarton", CFrame.new(ORIGIN + Vector3.new(0, H / 2, 0)), Vector3.new(W + 20, H + 80, D + 20))
CS:AddTag(zone, "InteriorZone")
zone:SetAttribute("Ambiance", AMBIANCE)

local count = 0
for _, d in room:GetDescendants() do
	if d:IsA("BasePart") then
		d.Locked = true
		count += 1
	end
end
table.insert(out, "interieur carton ok (" .. count .. " pieces)")
return table.concat(out, " | ")
