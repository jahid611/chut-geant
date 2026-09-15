-- Interieur de la boite a mouchoirs (base 3), d'apres l'image de reference de l'utilisateur : une piece fermee en carton
-- sombre, un trou ovale au plafond par ou filtre une lueur de ciel, un sol recouvert de mouchoirs deplies qui forment
-- des plis et des bosses, de petites lumieres posees au sol. L'ambiance (lumiere, brume) est appliquee cote client par
-- AmbianceController (reglage « Mouchoirs »).
--
-- A lancer APRES build-chambre.luau (qui recree la zone Base3 dans la chambre) :
--   node tools/scene-run.mjs tools/scene/build-interieur-mouchoirs.luau
-- Un ancien interieur est range dans ServerStorage.Archive, sans ses tags.

local CS = game:GetService("CollectionService")
local SS = game:GetService("ServerStorage")

local out = {}
local ORIGIN = Vector3.new(1600, -900, 0) -- centre du sol ; loin de la pantoufle (x = 0) et hors de la zone GiantRoom
local W, H, D = 360, 170, 420
local rng = Random.new(20260914)

local archive = SS:FindFirstChild("Archive") or Instance.new("Folder")
archive.Name = "Archive"
archive.Parent = SS
local old = workspace:FindFirstChild("InterieurMouchoirs")
if old then
	for _, d in old:GetDescendants() do
		for _, tag in CS:GetTags(d) do
			CS:RemoveTag(d, tag)
		end
	end
	old.Name = "InterieurMouchoirs_" .. os.time()
	old.Parent = archive
end

local room = Instance.new("Model")
room.Name = "InterieurMouchoirs"
room.Parent = workspace

local function part(parent, name, size, cframe, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	for k, v in props or {} do
		p[k] = v
	end
	p.Parent = parent
	return p
end
local function invisible(parent, name, cframe, size)
	return part(parent, name, size or Vector3.new(1, 1, 1), cframe, Color3.new(1, 1, 1), nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
end

-- 1. La boite en carton : sol, parois, plafond perce d'un ovale.
local structure = Instance.new("Folder")
structure.Name = "Carton"
structure.Parent = room
local cardboard = Enum.Material.Cardboard
-- carton gris-bleu assez clair pour se voir dans la penombre (62,68,78 disparaissait dans le noir)
local wallColor = Color3.fromRGB(112, 120, 134)
part(structure, "FondCarton", Vector3.new(W, 4, D), CFrame.new(ORIGIN - Vector3.new(0, 2, 0)), Color3.fromRGB(70, 76, 86), cardboard)
part(structure, "ParoiFond", Vector3.new(W, H, 6), CFrame.new(ORIGIN + Vector3.new(0, H / 2, -D / 2 - 3)), wallColor, cardboard)
part(structure, "ParoiAvant", Vector3.new(W, H, 6), CFrame.new(ORIGIN + Vector3.new(0, H / 2, D / 2 + 3)), wallColor, cardboard)
part(structure, "ParoiGauche", Vector3.new(6, H, D), CFrame.new(ORIGIN + Vector3.new(-W / 2 - 3, H / 2, 0)), wallColor, cardboard)
part(structure, "ParoiDroite", Vector3.new(6, H, D), CFrame.new(ORIGIN + Vector3.new(W / 2 + 3, H / 2, 0)), wallColor, cardboard)

-- Plafond en bandes de 4 studs : chaque bande s'arrete au bord de l'ovale (demi-axes 95 x 70), le trou parait rond.
-- bandes de 2 studs : a 4, le bord de l'ovale se voyait en escalier
local HOLE_A, HOLE_B, STRIP = 95, 70, 2
local holeCenter = Vector3.new(0, 0, -20)
local ceilingY = ORIGIN.Y + H + 3
for x = -W / 2, W / 2 - STRIP, STRIP do
	local cx = x + STRIP / 2
	local dx = (cx - holeCenter.X) / HOLE_A
	local function strip(z0, z1)
		if z1 - z0 > 0.5 then
			part(structure, "Plafond", Vector3.new(STRIP, 6, z1 - z0), CFrame.new(ORIGIN.X + cx, ceilingY, ORIGIN.Z + (z0 + z1) / 2), Color3.fromRGB(55, 60, 70), cardboard)
		end
	end
	if math.abs(dx) < 1 then
		local halfZ = HOLE_B * math.sqrt(1 - dx * dx)
		strip(-D / 2 - 6, holeCenter.Z - halfZ)
		strip(holeCenter.Z + halfZ, D / 2 + 6)
	else
		strip(-D / 2 - 6, D / 2 + 6)
	end
end
-- Au-dessus du trou : la lueur froide de la chambre, un panneau sombre bleute eclaire par-dessous.
local sky = part(room, "LueurDuTrou", Vector3.new(HOLE_A * 2 + 40, 2, HOLE_B * 2 + 40), CFrame.new(ORIGIN.X + holeCenter.X, ceilingY + 40, ORIGIN.Z + holeCenter.Z), Color3.fromRGB(80, 98, 122), Enum.Material.SmoothPlastic, { CastShadow = false })
local skyLight = Instance.new("SurfaceLight")
skyLight.Face = Enum.NormalId.Bottom
skyLight.Color = Color3.fromRGB(150, 175, 210)
skyLight.Brightness = 0.5
skyLight.Range = 60
skyLight.Angle = 90
skyLight.Parent = sky
local shaft = invisible(room, "RayonDuTrou", CFrame.lookAt(Vector3.new(ORIGIN.X + holeCenter.X, ceilingY + 10, ORIGIN.Z + holeCenter.Z), Vector3.new(ORIGIN.X + holeCenter.X, ORIGIN.Y, ORIGIN.Z + holeCenter.Z)))
local shaftLight = Instance.new("SpotLight")
shaftLight.Face = Enum.NormalId.Front
shaftLight.Color = Color3.fromRGB(150, 175, 210)
shaftLight.Brightness = 1.5
shaftLight.Range = 60
shaftLight.Angle = 70
shaftLight.Parent = shaft
-- Parois lisibles : en jeu la lumiere ambiante ne suffisait pas, la piece paraissait noire. Une lueur douce et froide
-- remonte le long de chaque paroi depuis le sol (SurfaceLight vers la paroi), comme sur la reference.
-- Face = sens de la lumiere : Front regarde vers -Z, Back vers +Z. Le mur du fond (-Z) est eclaire par Front, celui
-- de devant (+Z) par Back (inverses au premier essai : ces deux parois restaient noires, teste en jeu).
local wallGlow = {
	{ Vector3.new(0, 12, -D / 2 + 30), Enum.NormalId.Front, Vector3.new(W, 4, 2) },
	{ Vector3.new(0, 12, D / 2 - 30), Enum.NormalId.Back, Vector3.new(W, 4, 2) },
	{ Vector3.new(-W / 2 + 30, 12, 0), Enum.NormalId.Left, Vector3.new(2, 4, D) },
	{ Vector3.new(W / 2 - 30, 12, 0), Enum.NormalId.Right, Vector3.new(2, 4, D) },
}
for i, g in wallGlow do
	local p = invisible(room, "LueurParoi" .. i, CFrame.new(ORIGIN + g[1]), g[3])
	local sl = Instance.new("SurfaceLight")
	sl.Face = g[2]
	sl.Color = Color3.fromRGB(150, 170, 200)
	sl.Brightness = 1.2
	sl.Range = 60
	sl.Angle = 80
	sl.Parent = p
end
table.insert(out, "carton et trou ovale")

-- 2. Le sol de mouchoirs : grandes feuilles fines posees de travers, et des plis en tente (deux feuilles qui se
-- rejoignent sur une arete), comme sur la reference.
local tissues = Instance.new("Folder")
tissues.Name = "Mouchoirs"
tissues.Parent = room
local tissueColor = Color3.fromRGB(150, 158, 170)
for i = 1, 70 do
	local w, d = rng:NextNumber(40, 90), rng:NextNumber(40, 80)
	local x = rng:NextNumber(-W / 2 + 20, W / 2 - 20)
	local z = rng:NextNumber(-D / 2 + 20, D / 2 - 20)
	local cf = CFrame.new(ORIGIN.X + x, ORIGIN.Y + 0.3 + i * 0.02, ORIGIN.Z + z)
		* CFrame.Angles(math.rad(rng:NextNumber(-2, 2)), math.rad(rng:NextNumber(0, 180)), math.rad(rng:NextNumber(-2, 2)))
	local shade = rng:NextNumber(-10, 10)
	part(tissues, "Feuille", Vector3.new(w, 0.3, d), cf, Color3.fromRGB(tissueColor.R * 255 + shade, tissueColor.G * 255 + shade, tissueColor.B * 255 + shade), Enum.Material.Fabric, { CastShadow = true })
end
for i = 1, 16 do
	local x = rng:NextNumber(-W / 2 + 40, W / 2 - 40)
	local z = rng:NextNumber(-D / 2 + 40, D / 2 - 60)
	-- laisser libre l'allee centrale entre l'arrivee et la boite
	if math.abs(x) > 35 then
		local yaw = math.rad(rng:NextNumber(0, 180))
		local len, slope, rise = rng:NextNumber(30, 60), rng:NextNumber(20, 32), math.rad(rng:NextNumber(18, 30))
		local base = CFrame.new(ORIGIN.X + x, ORIGIN.Y, ORIGIN.Z + z) * CFrame.Angles(0, yaw, 0)
		local h = math.sin(rise) * slope / 2
		for side = -1, 1, 2 do
			local cf = base * CFrame.new(side * math.cos(rise) * slope / 4, h, 0) * CFrame.Angles(0, 0, -side * rise)
			part(tissues, "Pli", Vector3.new(slope / 2 + 2, 0.3, len), cf, tissueColor, Enum.Material.Fabric, { CastShadow = true })
		end
	end
end
table.insert(out, "sol de mouchoirs")

-- 3. Petites lumieres posees sur les mouchoirs, qui menent vers la boite (reference : deux points lumineux au sol).
local lamps = Instance.new("Folder")
lamps.Name = "Veilleuses"
lamps.Parent = room
for i, z in { 120, 20, -80 } do
	local orb = part(lamps, "PetiteLumiere" .. i, Vector3.new(1.4, 1.4, 1.4), CFrame.new(ORIGIN.X + (if i % 2 == 0 then 12 else -10), ORIGIN.Y + 1.5, ORIGIN.Z + z), Color3.fromRGB(215, 235, 255), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false, CastShadow = false })
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(200, 220, 255)
	-- douce : a 2,2 / 40 le mouchoir devenait blanc cru autour de la lumiere
	l.Brightness = 0.9
	l.Range = 30
	l.Shadows = true
	l.Parent = orb
end

-- 4. La boite a jouets, au fond, eclairee.
local chestSrc = SS:FindFirstChild("DecorModels") and SS.DecorModels:FindFirstChild("ToyChest")
if chestSrc then
	local chest = chestSrc:Clone()
	chest.Name = "BoiteAJouets"
	local _, s0 = chest:GetBoundingBox()
	chest:ScaleTo(chest:GetScale() * (70 / math.max(s0.X, s0.Y, s0.Z)))
	local _, s = chest:GetBoundingBox()
	-- Coffre n°1 a gauche (x -120) : les coffres achetes s'alignent vers la droite (pas de 80) et restent dans la piece.
	chest:PivotTo(CFrame.new(ORIGIN.X - 120, ORIGIN.Y + 1 + s.Y / 2, ORIGIN.Z - D / 2 + 70) * CFrame.Angles(0, math.rad(180), 0))
	chest.Parent = room
	local ccf, cs = chest:GetBoundingBox()
	-- Les vrais coffres (achetables, remplis de jouets physiques) sont poses en jeu par BaseService a cet endroit :
	-- ce modele ne sert qu'a placer lumieres, etincelles et panneau.
	chest:Destroy()

	local spot = invisible(room, "ProjecteurBoite", CFrame.lookAt(ccf.Position + Vector3.new(0, 55, 30), ccf.Position))
	local sl = Instance.new("SpotLight")
	sl.Face = Enum.NormalId.Front
	sl.Color = Color3.fromRGB(255, 215, 140)
	-- Le joueur arrive colle au coffre : lumieres de la boite baissees (constate dans la pantoufle, ecran blanc).
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
	local base3 = zones and (zones:FindFirstChild("Base1Mouchoirs") or zones:FindFirstChild("Base3"))
	if base3 then
		-- 2e base attribuee (apres la pantoufle) : les interieurs d'abord
		base3.Name = "Base1Mouchoirs"
		base3.Size = Vector3.new(90, 40, 70)
		base3.CFrame = CFrame.new(ccf.Position.X, ORIGIN.Y + 20, ccf.Position.Z + cs.Z / 2 + 30)
		-- Coffres reels poses par BaseService : bas du coffre n°1 (face etoilee vers l'arrivee), coffres achetes
		-- alignes vers la droite avec un pas de 80 studs (x -120, -40, 40, 120 : tous dans la piece).
		base3:SetAttribute("DisplayCFrame", nil)
		base3:SetAttribute("DisplaySize", nil)
		base3:SetAttribute(
			"ChestCFrame",
			CFrame.new(ccf.Position.X, ccf.Position.Y - cs.Y / 2, ccf.Position.Z) * CFrame.Angles(0, math.rad(180), 0)
		)
		base3:SetAttribute("ChestStep", Vector3.new(80, 0, 0))
		base3:SetAttribute("ChestSize", 70)
		table.insert(out, "Base3 devant la boite a jouets")
	else
		table.insert(out, "Base3 introuvable : lancer build-chambre.luau d'abord")
	end
else
	table.insert(out, "manque DecorModels.ToyChest")
end

-- 5. Portes : face de la boite a mouchoirs dans la chambre -> arrivee ; lumiere de sortie -> retour dans la chambre.
-- Arrivee a cote de la boule « Retour chambre » et du coffre n°1 (demande utilisateur). ~11 studs de la sortie
-- (-168, -150), hors de sa zone (6 studs) et hors de la zone de depot (x -165..-75, z -120..-50).
local arrival = Vector3.new(ORIGIN.X - 135, ORIGIN.Y + 4, ORIGIN.Z - D / 2 + 165)
-- Sortie visible des l'arrivee, a 14 studs devant a droite (retour utilisateur : trop loin derriere le joueur).
-- Sortie juste a cote de la boite a jouets (coffre n°1 en x -120, z = -D/2 + 70) : on depose puis on ressort sans
-- retraverser la piece (demande utilisateur). A gauche du coffre et un peu devant ; les coffres achetes vont a droite.
-- Contre le flanc gauche du coffre, hors de la zone de depot (x -165..-75, z -120..-50) : a (-170, -106) la sortie
-- etait a 60 studs du coffre.
-- Demande utilisateur : la boule en face du coffre n°1, a quelques studs (face avant du coffre a z = -D/2 + 95).
-- 13 studs devant etait « trop pres » (retour utilisateur) : boule a ~30 studs devant la face avant.
-- Comme dans la pantoufle (capture utilisateur) : ~70 studs devant la face avant (z = -D/2 + 95), juste apres la
-- zone de depot (qui s'arrete a z = -D/2 + 160).
local exitPos = Vector3.new(ORIGIN.X - 120, ORIGIN.Y + 7, ORIGIN.Z - D / 2 + 165)
-- Boule de 3 studs et lumiere douce : a 8 studs de l'arrivee, la boule de 7 studs aveuglait (teste dans la pantoufle).
local exitOrb = part(room, "LumiereSortie", Vector3.new(3, 3, 3), CFrame.new(exitPos), Color3.fromRGB(170, 190, 255), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false, CastShadow = false })
local exitLight = Instance.new("PointLight")
exitLight.Color = Color3.fromRGB(170, 190, 255)
exitLight.Brightness = 0.8
exitLight.Range = 18
exitLight.Parent = exitOrb
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

local tissueBox = workspace:FindFirstChild("Chambre") and workspace.Chambre.Decor:FindFirstChild("Base_TissueBox")
if tissueBox then
	local tcf, ts = tissueBox:GetBoundingBox()
	local front = tcf.Position.Z - ts.Z / 2
	local outsidePos = Vector3.new(tcf.Position.X, 4, front - 22)
	-- Declencheur DANS la boite (demande utilisateur : y entrer vraiment) : on saute sur la boite et on se laisse
	-- tomber par la fente du dessus ; le volume est au fond, sous la fente. Collisions precises pour garder la fente.
	for _, p in tissueBox:GetDescendants() do
		if p:IsA("MeshPart") then
			pcall(function()
				p.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
			end)
		end
	end
	local entree = invisible(
		room,
		"PorteEntreeMouchoirs",
		CFrame.new(tcf.Position.X, tcf.Position.Y - ts.Y * 0.2, tcf.Position.Z),
		Vector3.new(ts.X * 0.5, ts.Y * 0.4, ts.Z * 0.5)
	)
	_ = front
	entree.CanTouch = true
	-- le joueur arrive tourne vers le coffre n°1 (x -120)
	entree:SetAttribute("Destination", CFrame.lookAt(arrival, Vector3.new(ORIGIN.X - 120, arrival.Y, ORIGIN.Z - D / 2 + 70)))
	CS:AddTag(entree, "BaseDoor")
	-- Zone de sortie etroite (6 studs) : a 14 studs elle englobait le point d'arrivee (~8 studs) et renvoyait le
	-- joueur dans la chambre sans qu'il bouge (constate dans la pantoufle).
	local sortie = invisible(room, "PorteSortieMouchoirs", CFrame.new(exitPos), Vector3.new(6, 14, 6))
	sortie.CanTouch = true
	sortie:SetAttribute("Destination", CFrame.lookAt(outsidePos, outsidePos + Vector3.new(0, 0, -1)))
	CS:AddTag(sortie, "BaseDoor")
	table.insert(out, "portes ok")
else
	table.insert(out, "Base_TissueBox introuvable dans la chambre")
end

local zone = invisible(room, "ZoneInterieurMouchoirs", CFrame.new(ORIGIN + Vector3.new(0, H / 2, 0)), Vector3.new(W + 20, H + 60, D + 20))
CS:AddTag(zone, "InteriorZone")
zone:SetAttribute("Ambiance", "Mouchoirs")

-- pieces verrouillees contre les deplacements accidentels dans l'editeur (cf. build-chambre)
for _, d in (workspace:FindFirstChild("InterieurMouchoirs") or Instance.new("Folder")):GetDescendants() do
	if d:IsA("BasePart") then
		d.Locked = true
	end
end
table.insert(out, "interieur mouchoirs ok")
return table.concat(out, " | ")
