-- Interieur de la boite a chaussures (base « ShoeBox », zone Base1 de la chambre) : on est a l'interieur d'une boite
-- en carton kraft. Du papier de soie froisse forme des collines roses, une enorme chaussure de ville est couchee sur
-- le flanc, ses lacets trainent au sol comme des cordes, et une lumiere chaude entre par les trous d'aeration.
-- L'ambiance (lumiere, brume) est appliquee cote client par AmbianceController (reglage « Chaussures »).
--
-- A lancer APRES build-chambre.luau (qui recree la zone Base1 dans la chambre) :
--   node tools/scene-run.mjs tools/scene/build-interieur-chaussures.luau
-- Un ancien interieur est range dans ServerStorage.Archive, sans ses tags.

local CS = game:GetService("CollectionService")
local SS = game:GetService("ServerStorage")

local out = {}
local NAME = "InterieurChaussures"
local ORIGIN = Vector3.new(3200, -900, 0) -- loin de la pantoufle (x 0) et des mouchoirs (x 1600)
local W, H, D = 360, 170, 420
-- zone de base : nom donne par cette recette, puis nom d'origine donne par build-chambre
local ZONE_NAMES = { "Base2Chaussures", "Base1" }
local ZONE_NEW = "Base2Chaussures"
local BASE_MODEL = "Base_ShoeBox"
local AMBIANCE = "Chaussures"
local rng = Random.new(20260916)

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
-- Forme arrondie a proportions libres : une piece avec un maillage « Sphere » (la forme Ball reste une boule ronde).
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
local function shade(color, amount)
	return Color3.fromRGB(
		math.clamp(color.R * 255 + amount, 0, 255),
		math.clamp(color.G * 255 + amount, 0, 255),
		math.clamp(color.B * 255 + amount, 0, 255)
	)
end

-- 1. La boite en carton kraft : sol, parois, couvercle.
local structure = Instance.new("Folder")
structure.Name = "Boite"
structure.Parent = room
local kraft = Color3.fromRGB(184, 138, 96)
part(structure, "FondBoite", Vector3.new(W, 4, D), at(0, -2, 0), Color3.fromRGB(150, 108, 72), Enum.Material.Cardboard)
part(structure, "ParoiFond", Vector3.new(W, H, 6), at(0, H / 2, -D / 2 - 3), kraft, Enum.Material.Cardboard)
part(structure, "ParoiAvant", Vector3.new(W, H, 6), at(0, H / 2, D / 2 + 3), kraft, Enum.Material.Cardboard)
part(structure, "ParoiGauche", Vector3.new(6, H, D), at(-W / 2 - 3, H / 2, 0), kraft, Enum.Material.Cardboard)
part(structure, "ParoiDroite", Vector3.new(6, H, D), at(W / 2 + 3, H / 2, 0), kraft, Enum.Material.Cardboard)
part(structure, "Couvercle", Vector3.new(W + 12, 6, D + 12), at(0, H + 3, 0), Color3.fromRGB(120, 86, 58), Enum.Material.Cardboard)
-- bord du couvercle qui depasse a l'interieur, comme une vraie boite
for side = -1, 1, 2 do
	part(structure, "RebordCouvercle", Vector3.new(W, 10, 2), at(0, H - 5, side * (D / 2 - 1)), Color3.fromRGB(140, 100, 66), Enum.Material.Cardboard)
end

-- 2. Trous d'aeration : disques de lumiere chaude sur les parois, et un faisceau qui descend dans la boite.
local holes = Instance.new("Folder")
holes.Name = "TrousAeration"
holes.Parent = room
local warm = Color3.fromRGB(255, 208, 150)
local holeSpots = {
	{ Vector3.new(-W / 2 + 1, 118, -60), Vector3.new(1, 0, 0) },
	{ Vector3.new(-W / 2 + 1, 118, 90), Vector3.new(1, 0, 0) },
	{ Vector3.new(W / 2 - 1, 124, -120), Vector3.new(-1, 0, 0) },
	{ Vector3.new(W / 2 - 1, 124, 40), Vector3.new(-1, 0, 0) },
}
for i, h in holeSpots do
	local pos = ORIGIN + h[1]
	-- disque (cylindre couche dans la paroi : l'axe du cylindre est son X local)
	part(holes, "Trou" .. i, Vector3.new(2, 22, 22), CFrame.lookAt(pos, pos + h[2]) * CFrame.Angles(0, math.rad(90), 0), warm, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false })
	local target = pos + h[2] * 120 + Vector3.new(0, -110, 0)
	local source = invisible(holes, "Faisceau" .. i, CFrame.lookAt(pos + h[2] * 3, target))
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Color = warm
	spot.Brightness = 2.2
	spot.Range = 60
	spot.Angle = 35
	spot.Shadows = true
	spot.Parent = source
	-- poussiere qui danse dans le rayon
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(255, 225, 180))
	dust.LightEmission = 0.8
	dust.Transparency = NumberSequence.new(0.4, 1)
	dust.Size = NumberSequence.new(0.25)
	dust.Lifetime = NumberRange.new(4, 7)
	dust.Rate = 6
	dust.Speed = NumberRange.new(3, 6)
	dust.SpreadAngle = Vector2.new(12, 12)
	dust.EmissionDirection = Enum.NormalId.Front
	dust.Parent = source
end
-- lueurs douces qui remontent le long des parois (sans elles la boite paraissait noire dans la mouchoir)
for i, g in {
	{ Vector3.new(0, 14, -D / 2 + 30), Enum.NormalId.Front, Vector3.new(W, 4, 2) },
	{ Vector3.new(0, 14, D / 2 - 30), Enum.NormalId.Back, Vector3.new(W, 4, 2) },
	{ Vector3.new(-W / 2 + 30, 14, 0), Enum.NormalId.Left, Vector3.new(2, 4, D) },
	{ Vector3.new(W / 2 - 30, 14, 0), Enum.NormalId.Right, Vector3.new(2, 4, D) },
} do
	local p = invisible(room, "LueurParoi" .. i, CFrame.new(ORIGIN + g[1]), g[3])
	local sl = Instance.new("SurfaceLight")
	sl.Face = g[2]
	sl.Color = Color3.fromRGB(255, 196, 150)
	sl.Brightness = 1
	sl.Range = 60
	sl.Angle = 80
	sl.Parent = p
end
-- Eclairage de remplissage chaud (capture interieur-chaussures-avant : parois du fond et couvercle noirs, les lueurs
-- au ras du sol ne portent qu'a 60 studs). Lampes a mi-hauteur le long des parois, et lueurs sous le couvercle.
for i, p in {
	Vector3.new(-W / 2 + 25, 85, -140), Vector3.new(-W / 2 + 25, 85, 0), Vector3.new(-W / 2 + 25, 85, 140),
	Vector3.new(W / 2 - 25, 85, -140), Vector3.new(W / 2 - 25, 85, 0), Vector3.new(W / 2 - 25, 85, 140),
	Vector3.new(-90, 85, -D / 2 + 25), Vector3.new(90, 85, -D / 2 + 25),
	Vector3.new(-90, 85, D / 2 - 25), Vector3.new(90, 85, D / 2 - 25),
} do
	local src = invisible(room, "LampeRemplissage" .. i, at(p.X, p.Y, p.Z))
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(255, 200, 150)
	pl.Brightness = 0.9
	pl.Range = 60
	pl.Shadows = false
	pl.Parent = src
end
for gx = -1, 1 do
	for gz = -1, 1 do
		local p = invisible(room, "LueurCouvercle", at(gx * 110, H - 8, gz * 130), Vector3.new(80, 1, 80))
		local sl = Instance.new("SurfaceLight")
		sl.Face = Enum.NormalId.Bottom
		sl.Color = Color3.fromRGB(255, 190, 140)
		sl.Brightness = 0.7
		sl.Range = 60
		sl.Angle = 120
		sl.Parent = p
	end
end
table.insert(out, "boite kraft et trous d'aeration")

-- 3. Papier de soie froisse : collines douces (traversables) et feuilles froissees posees de travers.
local paper = Instance.new("Folder")
paper.Name = "PapierDeSoie"
paper.Parent = room
local tissuePink = Color3.fromRGB(246, 214, 222)
local tissueWhite = Color3.fromRGB(250, 240, 238)
for i = 1, 26 do
	local x = rng:NextNumber(-W / 2 + 30, W / 2 - 30)
	local z = rng:NextNumber(-D / 2 + 30, D / 2 - 30)
	-- allee libre entre l'arrivee (x -135, z -45) et le coffre n°1 (x -120, z -140) : pas de colline dessus
	if not (x < -60 and z < 20) then
		local size = Vector3.new(rng:NextNumber(50, 110), rng:NextNumber(12, 30), rng:NextNumber(40, 90))
		local color = if i % 3 == 0 then tissueWhite else shade(tissuePink, rng:NextNumber(-12, 8))
		blob(paper, "Colline", size, at(x, size.Y * 0.2, z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 180)), 0), color, Enum.Material.Fabric, { CanCollide = false, CastShadow = true })
	end
end
for i = 1, 60 do
	local x = rng:NextNumber(-W / 2 + 15, W / 2 - 15)
	local z = rng:NextNumber(-D / 2 + 15, D / 2 - 15)
	local cf = at(x, 0.3 + i * 0.02, z) * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), math.rad(rng:NextNumber(0, 180)), math.rad(rng:NextNumber(-6, 6)))
	local color = if i % 2 == 0 then tissueWhite else shade(tissuePink, rng:NextNumber(-10, 10))
	part(paper, "Feuille", Vector3.new(rng:NextNumber(30, 70), 0.3, rng:NextNumber(25, 60)), cf, color, Enum.Material.Fabric)
end
-- plis en tente, comme du papier froisse
for i = 1, 14 do
	local x = rng:NextNumber(-W / 2 + 40, W / 2 - 40)
	local z = rng:NextNumber(-D / 2 + 40, D / 2 - 60)
	if not (x < -60 and z < 20) then
		local base = at(x, 0, z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 180)), 0)
		local len, slope, rise = rng:NextNumber(24, 50), rng:NextNumber(16, 26), math.rad(rng:NextNumber(22, 34))
		local hgt = math.sin(rise) * slope / 2
		for side = -1, 1, 2 do
			local cf = base * CFrame.new(side * math.cos(rise) * slope / 4, hgt, 0) * CFrame.Angles(0, 0, -side * rise)
			part(paper, "Pli", Vector3.new(slope / 2 + 2, 0.3, len), cf, tissuePink, Enum.Material.Fabric)
		end
	end
end
table.insert(out, "papier de soie")

-- 4. L'enorme chaussure de ville couchee sur le flanc, a droite de la boite.
local shoe = Instance.new("Model")
shoe.Name = "ChaussureGeante"
shoe.Parent = room
-- repere de la chaussure : longueur sur X, hauteur sur Y ; couchee de 72 degres sur son flanc
local shoeCF = at(95, 30, 70) * CFrame.Angles(0, math.rad(-28), 0) * CFrame.Angles(math.rad(72), 0, 0)
-- cuir cognac : en 78,46,30 la chaussure sortait entierement noire (capture chaussures-chaussure)
local leather = Color3.fromRGB(168, 102, 58)
local function shoePart(name, size, localCF, color, material, props, round)
	local builder = if round then blob else part
	return builder(shoe, name, size, shoeCF * localCF, color, material, props)
end
shoePart("Semelle", Vector3.new(150, 9, 58), CFrame.new(0, 4.5, 0), Color3.fromRGB(96, 68, 50), Enum.Material.Rubber)
part(shoe, "BoutSemelle", Vector3.new(9, 58, 58), shoeCF * CFrame.new(74, 4.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(96, 68, 50), Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
shoePart("Talon", Vector3.new(34, 20, 54), CFrame.new(-60, -8, 0), Color3.fromRGB(84, 58, 42), Enum.Material.Rubber)
shoePart("Empeigne", Vector3.new(140, 62, 54), CFrame.new(-4, 34, 0), leather, Enum.Material.Leather, { CanCollide = false }, true)
shoePart("Pointe", Vector3.new(60, 40, 54), CFrame.new(52, 22, 0), shade(leather, 8), Enum.Material.Leather, { CanCollide = false }, true)
shoePart("Col", Vector3.new(58, 20, 40), CFrame.new(-36, 62, 0), Color3.fromRGB(110, 70, 46), Enum.Material.Fabric, { CanCollide = false }, true)
-- lumiere chaude posee au-dessus de la chaussure pour detacher le cuir du fond sombre
local shoeGlow = invisible(room, "LueurChaussure", CFrame.new(shoeCF.Position + Vector3.new(-40, 60, -50)))
local shoeLight = Instance.new("PointLight")
shoeLight.Color = Color3.fromRGB(255, 214, 170)
shoeLight.Brightness = 1.2
shoeLight.Range = 60
shoeLight.Parent = shoeGlow
shoePart("Languette", Vector3.new(40, 10, 30), CFrame.new(4, 64, 0) * CFrame.Angles(0, 0, math.rad(-12)), shade(leather, 14), Enum.Material.Leather, { CanCollide = false }, true)
-- surpiqures claires le long de la semelle
for i = -6, 6 do
	shoePart("Surpiqure", Vector3.new(6, 1.2, 1.2), CFrame.new(i * 11, 10, 27.5), Color3.fromRGB(214, 190, 150), Enum.Material.Fabric, { CanCollide = false })
end
-- lacets croises sur le dessus
for i = 0, 4 do
	for side = -1, 1, 2 do
		shoePart("Lacet", Vector3.new(30, 2.2, 2.2), CFrame.new(-8 + i * 11, 66, 0) * CFrame.Angles(0, math.rad(side * 38), 0), Color3.fromRGB(236, 230, 220), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	shoePart("Oeillet", Vector3.new(3, 3, 3), CFrame.new(-8 + i * 11, 66, 12), Color3.fromRGB(196, 160, 90), Enum.Material.Metal, { Shape = Enum.PartType.Ball, CanCollide = false })
	shoePart("Oeillet", Vector3.new(3, 3, 3), CFrame.new(-8 + i * 11, 66, -12), Color3.fromRGB(196, 160, 90), Enum.Material.Metal, { Shape = Enum.PartType.Ball, CanCollide = false })
end
-- deux grands bouts de lacets qui tombent de la chaussure et serpentent au sol, comme des cordes
local laceColor = Color3.fromRGB(236, 230, 220)
for lace = 1, 2 do
	local start = Vector3.new(60, 3, 30 + lace * 12)
	local prev = ORIGIN + start
	for s = 1, 16 do
		local t = s / 16
		local nextPos = ORIGIN + Vector3.new(start.X - t * 190, 3, start.Z + math.sin(t * math.pi * 2.2 + lace) * 36 + t * 60 * (lace - 1.5))
		local mid = (prev + nextPos) / 2
		local length = (nextPos - prev).Magnitude
		part(shoe, "CordeLacet", Vector3.new(length + 1.5, 3.4, 3.4), CFrame.lookAt(mid, nextPos) * CFrame.Angles(0, math.rad(90), 0), laceColor, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
		prev = nextPos
	end
	-- embout plastique du lacet
	part(shoe, "Embout", Vector3.new(8, 3.8, 3.8), CFrame.new(prev) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 180)), 0), Color3.fromRGB(40, 36, 34), Enum.Material.Plastic, { Shape = Enum.PartType.Cylinder })
end
table.insert(out, "chaussure geante et lacets")

-- 5. La boite a jouets au fond a gauche, eclairee, et la zone de base devant.
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
	-- les vrais coffres sont poses en jeu par BaseService : ce modele ne sert qu'a placer lumieres et panneau
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

-- 6. Portes : face de la boite a chaussures dans la chambre -> arrivee ; boule de sortie -> retour dans la chambre.
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
	-- face tournee vers la chambre : cote -Z (les bases sont contre le mur de face, z 290)
	local front = bcf.Position.Z - bs.Z / 2
	local outsidePos = Vector3.new(bcf.Position.X, 4, front - 22)
	-- Petite porte lumineuse dessinee sur la face de la boite : on entre en marchant dedans.
	local doorW, doorH = math.min(bs.X * 0.45, 9), math.min(bs.Y * 0.4, 11)
	local doorFolder = Instance.new("Folder")
	doorFolder.Name = "PorteDessinee"
	doorFolder.Parent = room
	local doorCenter = Vector3.new(bcf.Position.X, doorH / 2 + 1, front - 0.3)
	part(doorFolder, "Seuil", Vector3.new(doorW, doorH, 0.4), CFrame.new(doorCenter), Color3.fromRGB(40, 26, 18), Enum.Material.SmoothPlastic, { CanCollide = false, CastShadow = false })
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
	local entree = invisible(room, "PorteEntreeChaussures", CFrame.new(bcf.Position.X, 5, front + 1), Vector3.new(bs.X * 0.8, 10, 8))
	entree.CanTouch = true
	local chestX = ORIGIN.X - 120
	local chestZ = ORIGIN.Z - D / 2 + 70
	entree:SetAttribute("Destination", CFrame.lookAt(arrival, Vector3.new(chestX, arrival.Y, chestZ)))
	CS:AddTag(entree, "BaseDoor")
	local sortie = invisible(room, "PorteSortieChaussures", CFrame.new(exitPos), Vector3.new(6, 14, 6))
	sortie.CanTouch = true
	sortie:SetAttribute("Destination", CFrame.lookAt(outsidePos, outsidePos + Vector3.new(0, 0, -1)))
	CS:AddTag(sortie, "BaseDoor")
	table.insert(out, "portes ok")
else
	table.insert(out, BASE_MODEL .. " introuvable dans la chambre")
end

local zone = invisible(room, "ZoneInterieurChaussures", CFrame.new(ORIGIN + Vector3.new(0, H / 2, 0)), Vector3.new(W + 20, H + 60, D + 20))
CS:AddTag(zone, "InteriorZone")
zone:SetAttribute("Ambiance", AMBIANCE)

-- pieces verrouillees contre les deplacements accidentels dans l'editeur (cf. build-chambre)
for _, d in room:GetDescendants() do
	if d:IsA("BasePart") then
		d.Locked = true
	end
end
local count = 0
for _, d in room:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
table.insert(out, "interieur chaussures ok (" .. count .. " pieces)")
return table.concat(out, " | ")
