-- Interieur de la boite de cereales (base « CerealBox », zone Base4 de la chambre) : on est tout petit au fond
-- d'une boite de cereales ouverte. Des dunes de miettes dorees, des flocons et des anneaux colores geants, une
-- flaque de lait, un sachet plastique geant qui brille, et une lumiere doree qui tombe par l'ouverture du dessus.
-- L'ambiance est appliquee cote client par AmbianceController (reglage « Cereales »).
--
-- A lancer APRES build-chambre.luau (qui recree la zone Base4 dans la chambre) :
--   node tools/scene-run.mjs tools/scene/build-interieur-cereales.luau
-- Un ancien interieur est range dans ServerStorage.Archive, sans ses tags ; le terrain de la zone est regenere.

local CS = game:GetService("CollectionService")
local SS = game:GetService("ServerStorage")
local Terrain = workspace.Terrain

local out = {}
local NAME = "InterieurCereales"
local ORIGIN = Vector3.new(4800, -900, 0)
local W, H, D = 360, 190, 420
local ZONE_NAMES = { "Base3Cereales", "Base4" }
local ZONE_NEW = "Base3Cereales"
local BASE_MODEL = "Base_CerealBox"
local AMBIANCE = "Cereales"
local rng = Random.new(20260917)
local warm = Color3.fromRGB(255, 205, 110)

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
local function shade(color, amount)
	return Color3.fromRGB(
		math.clamp(color.R * 255 + amount, 0, 255),
		math.clamp(color.G * 255 + amount, 0, 255),
		math.clamp(color.B * 255 + amount, 0, 255)
	)
end
-- allee libre entre l'arrivee (x -135, z -45) et le coffre n°1 (x -120, z -140)
local function inPath(x, z)
	return x < -55 and z < 25
end

-- 1. La boite : parois de carton imprime (jaune dore), fond, et une ouverture en haut (rabats ouverts).
local structure = Instance.new("Folder")
structure.Name = "Boite"
structure.Parent = room
local wallColor = Color3.fromRGB(226, 172, 70)
part(structure, "FondBoite", Vector3.new(W, 4, D), at(0, -2, 0), Color3.fromRGB(196, 150, 80), Enum.Material.Cardboard)
part(structure, "ParoiFond", Vector3.new(W, H, 6), at(0, H / 2, -D / 2 - 3), wallColor, Enum.Material.Cardboard)
part(structure, "ParoiAvant", Vector3.new(W, H, 6), at(0, H / 2, D / 2 + 3), wallColor, Enum.Material.Cardboard)
part(structure, "ParoiGauche", Vector3.new(6, H, D), at(-W / 2 - 3, H / 2, 0), shade(wallColor, -14), Enum.Material.Cardboard)
part(structure, "ParoiDroite", Vector3.new(6, H, D), at(W / 2 + 3, H / 2, 0), shade(wallColor, -14), Enum.Material.Cardboard)
-- bandes decoratives imprimees (rouge et blanc) en haut des parois
for _, s in {
	{ Vector3.new(W, 14, 1), Vector3.new(0, H - 30, -D / 2 + 0.2) },
	{ Vector3.new(W, 14, 1), Vector3.new(0, H - 30, D / 2 - 0.2) },
	{ Vector3.new(1, 14, D), Vector3.new(-W / 2 + 0.2, H - 30, 0) },
	{ Vector3.new(1, 14, D), Vector3.new(W / 2 - 0.2, H - 30, 0) },
} do
	part(structure, "BandeRouge", s[1], at(s[2].X, s[2].Y, s[2].Z), Color3.fromRGB(214, 60, 52), Enum.Material.SmoothPlastic, { CanCollide = false })
	part(structure, "BandeBlanche", s[1] - Vector3.new(0, 8, 0), at(s[2].X, s[2].Y - 11, s[2].Z), Color3.fromRGB(250, 244, 230), Enum.Material.SmoothPlastic, { CanCollide = false })
end
-- plafond : deux bandes laissent une ouverture de 150 x 200 au centre
local OPEN_X, OPEN_Z = 150, 200
part(structure, "PlafondGauche", Vector3.new((W - OPEN_X) / 2, 6, D + 12), at(-(W + OPEN_X) / 4, H + 3, 0), shade(wallColor, -40), Enum.Material.Cardboard)
part(structure, "PlafondDroit", Vector3.new((W - OPEN_X) / 2, 6, D + 12), at((W + OPEN_X) / 4, H + 3, 0), shade(wallColor, -40), Enum.Material.Cardboard)
part(structure, "PlafondFond", Vector3.new(OPEN_X, 6, (D - OPEN_Z) / 2), at(0, H + 3, -(D + OPEN_Z) / 4), shade(wallColor, -40), Enum.Material.Cardboard)
part(structure, "PlafondAvant", Vector3.new(OPEN_X, 6, (D - OPEN_Z) / 2), at(0, H + 3, (D + OPEN_Z) / 4), shade(wallColor, -40), Enum.Material.Cardboard)
-- rabats ouverts vers l'exterieur
for side = -1, 1, 2 do
	part(structure, "Rabat", Vector3.new(OPEN_X, 4, 80), at(0, H + 30, side * (OPEN_Z / 2 + 36)) * CFrame.Angles(math.rad(side * 55), 0, 0), shade(wallColor, -20), Enum.Material.Cardboard)
end
-- au-dessus de l'ouverture : la lueur doree de la chambre
local sky = part(room, "LueurOuverture", Vector3.new(OPEN_X + 60, 2, OPEN_Z + 60), at(0, H + 60, 0), Color3.fromRGB(120, 96, 60), Enum.Material.SmoothPlastic, { CastShadow = false })
local skyLight = Instance.new("SurfaceLight")
skyLight.Face = Enum.NormalId.Bottom
skyLight.Color = warm
skyLight.Brightness = 0.9
skyLight.Range = 60
skyLight.Angle = 90
skyLight.Parent = sky
for i, off in { Vector3.new(-40, 0, -50), Vector3.new(40, 0, 50) } do
	local shaft = invisible(room, "RayonOuverture" .. i, CFrame.lookAt(ORIGIN + Vector3.new(off.X, H + 8, off.Z), ORIGIN + Vector3.new(off.X * 0.4, 0, off.Z * 0.4)))
	local sl = Instance.new("SpotLight")
	sl.Face = Enum.NormalId.Front
	sl.Color = warm
	sl.Brightness = 2
	sl.Range = 60
	sl.Angle = 70
	sl.Shadows = true
	sl.Parent = shaft
end
for i, g in {
	{ Vector3.new(0, 16, -D / 2 + 30), Enum.NormalId.Front, Vector3.new(W, 4, 2) },
	{ Vector3.new(0, 16, D / 2 - 30), Enum.NormalId.Back, Vector3.new(W, 4, 2) },
	{ Vector3.new(-W / 2 + 30, 16, 0), Enum.NormalId.Left, Vector3.new(2, 4, D) },
	{ Vector3.new(W / 2 - 30, 16, 0), Enum.NormalId.Right, Vector3.new(2, 4, D) },
} do
	local p = invisible(room, "LueurParoi" .. i, CFrame.new(ORIGIN + g[1]), g[3])
	local sl = Instance.new("SurfaceLight")
	sl.Face = g[2]
	sl.Color = Color3.fromRGB(255, 214, 150)
	sl.Brightness = 1
	sl.Range = 60
	sl.Angle = 80
	sl.Parent = p
end
table.insert(out, "boite de cereales ouverte")

-- 2. Dunes de miettes (terrain sable dore), aplaties sur l'allee, sous le lait et devant le coffre.
Terrain:FillBlock(at(0, H / 2, 0), Vector3.new(W + 8, H, D + 8), Enum.Material.Air)
local CELL = 8
local function duneHeight(x, z)
	local h = 10 * math.noise(x / 110, z / 110, 2.1) + 5 * math.noise(x / 40, z / 40, 7.3) + 8
	if inPath(x, z) then
		h = 1
	end
	-- flaque de lait (centre 60, -30) et abords du coffre : plat
	if (Vector2.new(x, z) - Vector2.new(60, -30)).Magnitude < 60 or (x < -40 and z < -90) then
		h = math.min(h, 1)
	end
	return math.max(h, 1)
end
for x = -W / 2, W / 2 - CELL, CELL do
	for z = -D / 2, D / 2 - CELL, CELL do
		local cx, cz = x + CELL / 2, z + CELL / 2
		local top = duneHeight(cx, cz)
		Terrain:FillBlock(at(cx, top / 2 - 0.5, cz), Vector3.new(CELL, top + 1, CELL), Enum.Material.Sand)
	end
end
Terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(214, 168, 92))
local function surface(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Terrain, structure }
	local hit = workspace:Raycast(ORIGIN + Vector3.new(x, H - 5, z), Vector3.new(0, -H - 10, 0), params)
	return if hit then hit.Position.Y - ORIGIN.Y else 0
end
table.insert(out, "dunes de miettes")

-- 3. Flocons et anneaux geants poses sur les dunes.
local cereal = Instance.new("Folder")
cereal.Name = "Cereales"
cereal.Parent = room
local flakeColors = { Color3.fromRGB(232, 160, 60), Color3.fromRGB(214, 132, 48), Color3.fromRGB(242, 190, 90), Color3.fromRGB(196, 116, 44) }
for i = 1, 170 do
	local x = rng:NextNumber(-W / 2 + 12, W / 2 - 12)
	local z = rng:NextNumber(-D / 2 + 12, D / 2 - 12)
	if not inPath(x, z) and (Vector2.new(x, z) - Vector2.new(60, -30)).Magnitude > 55 then
		local y = surface(x, z)
		local size = Vector3.new(rng:NextNumber(9, 16), rng:NextNumber(1.8, 3), rng:NextNumber(8, 14))
		blob(cereal, "Flocon", size, at(x, y + 1, z) * CFrame.Angles(math.rad(rng:NextNumber(-30, 30)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-30, 30))), flakeColors[rng:NextInteger(1, #flakeColors)], Enum.Material.Sand, { CanCollide = false })
	end
end
local ringColors = { Color3.fromRGB(232, 64, 70), Color3.fromRGB(88, 196, 92), Color3.fromRGB(150, 90, 210), Color3.fromRGB(250, 206, 60), Color3.fromRGB(250, 140, 50) }
for i = 1, 32 do
	local x = rng:NextNumber(-W / 2 + 20, W / 2 - 20)
	local z = rng:NextNumber(-D / 2 + 20, D / 2 - 20)
	if not inPath(x, z) and (Vector2.new(x, z) - Vector2.new(60, -30)).Magnitude > 60 then
		local y = surface(x, z)
		local radius = rng:NextNumber(4.5, 7)
		local color = ringColors[rng:NextInteger(1, #ringColors)]
		local ringCF = at(x, y + radius * 0.6, z) * CFrame.Angles(math.rad(rng:NextNumber(40, 80)), math.rad(rng:NextNumber(0, 360)), 0)
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			part(cereal, "Anneau", Vector3.new(radius * 0.75, radius * 0.75, radius * 0.75), ringCF * CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius), color, Enum.Material.Sand, { Shape = Enum.PartType.Ball, CanCollide = false })
		end
	end
end
table.insert(out, "flocons et anneaux")

-- 4. Flaque de lait et gouttes.
local milk = Instance.new("Folder")
milk.Name = "Lait"
milk.Parent = room
local milkY = surface(60, -30)
part(milk, "Flaque", Vector3.new(1.2, 96, 80), at(60, milkY + 0.4, -30) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(250, 248, 242), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, Reflectance = 0.18, CanCollide = false })
blob(milk, "Bord", Vector3.new(70, 2.4, 58), at(95, milkY + 0.6, -10), Color3.fromRGB(250, 248, 242), Enum.Material.SmoothPlastic, { Reflectance = 0.18, CanCollide = false })
for i = 1, 10 do
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(52, 75)
	local drop = rng:NextNumber(2.5, 5)
	part(milk, "Goutte", Vector3.new(drop, drop, drop), at(60 + math.cos(a) * r, milkY + drop * 0.3, -30 + math.sin(a) * r), Color3.fromRGB(252, 250, 246), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, Reflectance = 0.2, CanCollide = false })
end
-- flocons qui flottent sur le lait
for i = 1, 8 do
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(5, 35)
	blob(milk, "FloconMouille", Vector3.new(12, 2, 10), at(60 + math.cos(a) * r, milkY + 1.1, -30 + math.sin(a) * r) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0), flakeColors[rng:NextInteger(1, #flakeColors)], Enum.Material.Sand, { CanCollide = false })
end
table.insert(out, "flaque de lait")

-- 5. Le sachet plastique geant, froisse et brillant, affaisse contre la paroi du fond a droite.
local bag = Instance.new("Folder")
bag.Name = "Sachet"
bag.Parent = room
local film = { Transparency = 0.55, Reflectance = 0.3, CanCollide = false, CastShadow = false }
local bagBase = at(110, 0, 120)
for i = 1, 9 do
	local off = Vector3.new(rng:NextNumber(-60, 60), rng:NextNumber(10, 60), rng:NextNumber(-45, 45))
	local size = Vector3.new(rng:NextNumber(60, 110), rng:NextNumber(30, 70), rng:NextNumber(40, 80))
	blob(bag, "Film", size, bagBase * CFrame.new(off) * CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), math.rad(rng:NextNumber(0, 180)), math.rad(rng:NextNumber(-20, 20))), Color3.fromRGB(228, 238, 255), Enum.Material.Glass, film)
end
-- plis brillants du plastique
for i = 1, 12 do
	local off = Vector3.new(rng:NextNumber(-70, 70), rng:NextNumber(15, 75), rng:NextNumber(-50, 50))
	-- en Neon les plis ressortaient comme des batons blancs (capture cereales-vue) : film plus opaque et brillant
	blob(bag, "Reflet", Vector3.new(rng:NextNumber(20, 45), 1.2, rng:NextNumber(6, 12)), bagBase * CFrame.new(off) * CFrame.Angles(math.rad(rng:NextNumber(-60, 60)), math.rad(rng:NextNumber(0, 180)), math.rad(rng:NextNumber(-60, 60))), Color3.fromRGB(248, 250, 255), Enum.Material.Glass, { Transparency = 0.3, Reflectance = 0.5, CanCollide = false, CastShadow = false })
end
-- cereales encore dans le sachet
for i = 1, 20 do
	local off = Vector3.new(rng:NextNumber(-50, 50), rng:NextNumber(6, 40), rng:NextNumber(-35, 35))
	blob(bag, "FloconSachet", Vector3.new(12, 2.5, 10), bagBase * CFrame.new(off) * CFrame.Angles(math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(0, 360)), 0), flakeColors[rng:NextInteger(1, #flakeColors)], Enum.Material.Sand, { CanCollide = false })
end
local bagGlow = invisible(bag, "LueurSachet", bagBase * CFrame.new(0, 50, -60))
local bgl = Instance.new("PointLight")
bgl.Color = Color3.fromRGB(255, 236, 190)
bgl.Brightness = 1.2
bgl.Range = 55
bgl.Parent = bagGlow
table.insert(out, "sachet plastique")

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
-- 2 studs plus haut que dans les autres interieurs : le sable de l'allee affleure a +1
local arrival = Vector3.new(ORIGIN.X - 135, ORIGIN.Y + 6, ORIGIN.Z - D / 2 + 165)
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
	part(doorFolder, "Seuil", Vector3.new(doorW, doorH, 0.4), CFrame.new(doorCenter), Color3.fromRGB(50, 34, 16), Enum.Material.SmoothPlastic, { CanCollide = false, CastShadow = false })
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
	local entree = invisible(room, "PorteEntreeCereales", CFrame.new(bcf.Position.X, 5, front + 1), Vector3.new(bs.X * 0.8, 10, 8))
	entree.CanTouch = true
	entree:SetAttribute("Destination", CFrame.lookAt(arrival, Vector3.new(ORIGIN.X - 120, arrival.Y, ORIGIN.Z - D / 2 + 70)))
	CS:AddTag(entree, "BaseDoor")
	local sortie = invisible(room, "PorteSortieCereales", CFrame.new(exitPos), Vector3.new(6, 14, 6))
	sortie.CanTouch = true
	sortie:SetAttribute("Destination", CFrame.lookAt(outsidePos, outsidePos + Vector3.new(0, 0, -1)))
	CS:AddTag(sortie, "BaseDoor")
	table.insert(out, "portes ok")
else
	table.insert(out, BASE_MODEL .. " introuvable dans la chambre")
end

local zone = invisible(room, "ZoneInterieurCereales", CFrame.new(ORIGIN + Vector3.new(0, H / 2, 0)), Vector3.new(W + 20, H + 80, D + 20))
CS:AddTag(zone, "InteriorZone")
zone:SetAttribute("Ambiance", AMBIANCE)

local count = 0
for _, d in room:GetDescendants() do
	if d:IsA("BasePart") then
		d.Locked = true
		count += 1
	end
end
table.insert(out, "interieur cereales ok (" .. count .. " pieces)")
return table.concat(out, " | ")
