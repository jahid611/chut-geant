-- Interieur de la pantoufle (base 2), d'apres l'image de reference de l'utilisateur : une etendue immense et sombre
-- de fourrure en dunes, un ciel noir, de petites lumieres qui flottent et, au loin, la boite a jouets qui brille.
-- La fourrure est du terrain Roblox en herbe tres sombre (les brins de l'herbe font les poils).
-- L'ambiance noire (ciel, brume, lumiere) est appliquee cote client par AmbianceController quand le joueur est ici.
--
-- A lancer APRES build-chambre.luau (qui recree la zone Base2 dans la chambre) :
--   node tools/scene-run.mjs tools/scene/build-interieur-pantoufle.luau
-- Un ancien interieur est range dans ServerStorage.Archive, sans ses tags ; le terrain de la zone est regenere.

local CS = game:GetService("CollectionService")
local SS = game:GetService("ServerStorage")
local Terrain = workspace.Terrain

local out = {}
local ORIGIN = Vector3.new(0, -900, 0) -- niveau moyen du sol, hors de la zone GiantRoom : le geant n'y chasse pas
local SIZE = 1200 -- etendue de fourrure (carre, en studs)
local CELL = 8 -- pas du relief
local FUR = Enum.Material.Grass
-- Fourrure rose (demande utilisateur : « les poils au sol dans la pantoufle met les rose plutot que bleu »), assez
-- claire pour que les dunes se devinent dans la penombre.
local FUR_COLOR = Color3.fromRGB(150, 92, 118)

local archive = SS:FindFirstChild("Archive") or Instance.new("Folder")
archive.Name = "Archive"
archive.Parent = SS
local old = workspace:FindFirstChild("InterieurPantoufle")
if old then
	for _, d in old:GetDescendants() do
		for _, tag in CS:GetTags(d) do
			CS:RemoveTag(d, tag)
		end
	end
	old.Name = "InterieurPantoufle_" .. os.time()
	old.Parent = archive
end

local room = Instance.new("Model")
room.Name = "InterieurPantoufle"
room.Parent = workspace

local function invisible(name, cframe, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size or Vector3.new(1, 1, 1)
	p.CFrame = cframe
	p.Parent = room
	return p
end

-- 1. Dunes de fourrure : bruit a deux echelles (grandes vagues + petits remous).
local function duneHeight(x, z)
	return 22 * math.noise(x / 260, z / 260, 0.3) + 9 * math.noise(x / 90, z / 90, 1.7) + 3 * math.noise(x / 30, z / 30, 4.1)
end
Terrain:FillBlock(CFrame.new(ORIGIN + Vector3.new(0, 20, 0)), Vector3.new(SIZE + 40, 200, SIZE + 40), Enum.Material.Air)
local half = SIZE / 2
local bottom = ORIGIN.Y - 60
for x = -half, half - CELL, CELL do
	for z = -half, half - CELL, CELL do
		local cx, cz = x + CELL / 2, z + CELL / 2
		local top = ORIGIN.Y + duneHeight(cx, cz)
		local height = top - bottom
		Terrain:FillBlock(CFrame.new(ORIGIN.X + cx, bottom + height / 2, ORIGIN.Z + cz), Vector3.new(CELL, height, CELL), FUR)
	end
end
Terrain:SetMaterialColor(FUR, FUR_COLOR)
-- Les brins d'herbe (Decoration) font les poils ; la propriete n'est pas modifiable par script partout : on essaie.
local decoOk = pcall(function()
	(Terrain :: any).Decoration = true
end)
table.insert(out, "dunes de fourrure" .. (if decoOk then "" else " (brins : activer Decoration du Terrain a la main)"))

local function surface(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Terrain }
	local hit = workspace:Raycast(Vector3.new(ORIGIN.X + x, ORIGIN.Y + 150, ORIGIN.Z + z), Vector3.new(0, -300, 0), params)
	return if hit then hit.Position.Y else ORIGIN.Y
end

-- 2. Arrivee et sortie : on arrive a un bout de l'etendue, dos a une porte de lumiere qui ramene dans la chambre.
-- Arrivee a cote de la boule « Retour chambre » et de la boite a jouets (demande utilisateur : atterrir sur la
-- sortie en entrant). Pas pile dessus, sinon la sortie renverrait le joueur dans la chambre a la fin du delai :
-- ~10 studs de la sortie (-46, -290), hors de sa zone (6 studs) et hors de la zone de depot (x -45..45, z -280..-210).
-- Arrivee a 12 studs de la boule, en face du coffre : on atterrit dans la zone de depot (un jouet porte est depose
-- des l'arrivee), hors de la petite zone de sortie (6 studs).
-- a cote de la boule (15 studs sur le cote), tourne vers le coffre
local ARRIVAL = Vector2.new(-15, -205)
local arrivalY = surface(ARRIVAL.X, ARRIVAL.Y)
local inside = Vector3.new(ORIGIN.X + ARRIVAL.X, arrivalY + 4, ORIGIN.Z + ARRIVAL.Y)

-- Lueur rose douce au-dessus de l'arrivee : teste en jeu, le joueur et la fourrure autour de lui etaient encore
-- presque noirs apres le fondu. Source haute et large, sans ombre, pour eclairer une clairiere sans faire de spot.
-- Lueur douce : les captures « trop sombres » etaient prises pendant le fondu au noir. Une fois l'ambiance en place,
-- avec 2,6 le joueur et la fourrure ressortaient surexposes (teste en jeu) ; 1,1 suffit a marquer la clairiere.
local arrivalGlow = invisible("LueurArrivee", CFrame.new(inside + Vector3.new(0, 12, -4)))
local arrivalLight = Instance.new("PointLight")
arrivalLight.Color = Color3.fromRGB(255, 190, 220)
-- L'arrivee est maintenant a cote de la boite a jouets, deja eclairee par son projecteur et sa lueur : les trois
-- lumieres ensemble rendaient l'ecran presque blanc (teste en jeu). Lueur d'arrivee eteinte.
arrivalLight.Brightness = 0
arrivalLight.Range = 42
arrivalLight.Enabled = false
arrivalLight.Shadows = false
arrivalLight.Parent = arrivalGlow

-- Sortie visible des l'arrivee, a 14 studs devant a droite (derriere le joueur a 45 studs, il fallait marcher trop
-- longtemps pour la trouver : retour utilisateur). Le joueur arrive regard vers -Z.
-- Sortie juste a cote de la boite a jouets (BOX, plus bas) : on depose ses jouets puis on ressort sans retraverser
-- la pantoufle (demande utilisateur : reduire la marche entre le coffre et la sortie). A gauche du coffre n°1 et un
-- peu devant, car les coffres achetes s'alignent vers la droite.
-- Contre le flanc gauche du coffre (70 studs de large) : ~11 studs du bord, hors de la zone de depot (x -45..45,
-- z -280..-210). A (-58, -266) la sortie etait a 67 studs du coffre, 6,5 s de marche (teste en jeu) : trop loin.
-- Demande utilisateur : la boule en face du coffre, a quelques studs. Le coffre (70 de large, 50 de profondeur) a
-- sa face etoilee vers +Z, face avant a z = -275 : boule a 13 studs devant.
-- 13 studs devant etait « trop pres » (retour utilisateur) : boule a ~30 studs devant la face avant.
-- Capture de l'utilisateur : a 30 studs la boule paraissait collee au coffre ; il la veut ou il se tenait, environ
-- 65-70 studs devant la face avant (z = -275), juste apres la zone de depot (qui s'arrete a z = -210).
local EXIT_XZ = Vector2.new(0, -205)
local exitPos = Vector3.new(ORIGIN.X + EXIT_XZ.X, surface(EXIT_XZ.X, EXIT_XZ.Y) + 7, ORIGIN.Z + EXIT_XZ.Y)
local exitGlow = Instance.new("Part")
exitGlow.Name = "LumiereSortie"
exitGlow.Shape = Enum.PartType.Ball
exitGlow.Material = Enum.Material.Neon
exitGlow.Color = Color3.fromRGB(170, 190, 255)
-- Boule de 3 studs et lumiere douce : depuis que la sortie est a 8 studs de l'arrivee, la boule de 7 studs et sa
-- lumiere (3 / 50) aveuglaient la camera et rendaient le joueur tout blanc (teste en jeu).
exitGlow.Size = Vector3.new(3, 3, 3)
exitGlow.Anchored = true
exitGlow.CanCollide = false
exitGlow.CastShadow = false
exitGlow.CFrame = CFrame.new(exitPos)
exitGlow.Parent = room
local exitLight = Instance.new("PointLight")
exitLight.Color = Color3.fromRGB(170, 190, 255)
exitLight.Brightness = 0.8
exitLight.Range = 18
exitLight.Parent = exitGlow
local exitHalo = Instance.new("ParticleEmitter")
exitHalo.Texture = "rbxasset://textures/particles/sparkles_main.dds"
exitHalo.Color = ColorSequence.new(Color3.fromRGB(190, 205, 255))
exitHalo.LightEmission = 1
exitHalo.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
exitHalo.Lifetime = NumberRange.new(1, 2)
exitHalo.Rate = 12
exitHalo.Speed = NumberRange.new(1, 3)
exitHalo.SpreadAngle = Vector2.new(180, 180)
exitHalo.Parent = exitGlow
local exitLabel = Instance.new("BillboardGui")
exitLabel.Size = UDim2.fromOffset(220, 40)
exitLabel.StudsOffset = Vector3.new(0, 8, 0)
exitLabel.MaxDistance = 120
exitLabel.LightInfluence = 0
exitLabel.Parent = exitGlow
local exitText = Instance.new("TextLabel")
exitText.Size = UDim2.fromScale(1, 1)
exitText.BackgroundTransparency = 1
exitText.Text = "Retour chambre"
exitText.Font = Enum.Font.FredokaOne
exitText.TextScaled = true
exitText.TextColor3 = Color3.fromRGB(200, 215, 255)
exitText.TextStrokeTransparency = 0.4
exitText.Parent = exitLabel

-- 3. La boite a jouets, loin devant, posee sur une dune et eclairee comme un tresor.
local BOX = Vector2.new(0, -300)
local chestSrc = SS:FindFirstChild("DecorModels") and SS.DecorModels:FindFirstChild("ToyChest")
if chestSrc then
	local chest = chestSrc:Clone()
	chest.Name = "BoiteAJouets"
	local _, s0 = chest:GetBoundingBox()
	chest:ScaleTo(chest:GetScale() * (70 / math.max(s0.X, s0.Y, s0.Z)))
	local _, s = chest:GetBoundingBox()
	local boxY = surface(BOX.X, BOX.Y)
	-- rotation 180 : face etoilee tournee vers l'arrivee ; enfoncee de 3 studs dans la fourrure
	chest:PivotTo(CFrame.new(ORIGIN.X + BOX.X, boxY + s.Y / 2 - 3, ORIGIN.Z + BOX.Y) * CFrame.Angles(0, math.rad(180), 0))
	chest.Parent = room
	local ccf, cs = chest:GetBoundingBox()
	-- Les vrais coffres (achetables, remplis de jouets physiques) sont poses en jeu par BaseService a cet endroit :
	-- ce modele ne sert qu'a placer lumieres, etincelles et panneau.
	chest:Destroy()

	local spot = invisible("ProjecteurBoite", CFrame.lookAt(ccf.Position + Vector3.new(0, 55, 30), ccf.Position))
	local sl = Instance.new("SpotLight")
	sl.Face = Enum.NormalId.Front
	sl.Color = Color3.fromRGB(255, 215, 140)
	-- Assez pour que la boite attire l'oeil de loin, sans bruler la vue « Mes jouets » vue de dessus
	-- (a 5 et 3 le coffre et les jouets ressortaient jaune sature, teste en jeu).
	-- Le joueur arrive maintenant colle a la boite : 2,2 (fait pour se voir de loin) saturait l'ecran en blanc.
	sl.Brightness = 0.9
	sl.Range = 60
	sl.Angle = 60
	sl.Shadows = true
	sl.Parent = spot
	local glow = invisible("LueurBoite", CFrame.new(ccf.Position + Vector3.new(0, cs.Y * 0.25, 0)))
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(255, 200, 110)
	pl.Brightness = 0.5
	pl.Range = 55
	pl.Parent = glow
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Lifetime = NumberRange.new(1.5, 2.5)
	sparkle.Rate = 12
	sparkle.Speed = NumberRange.new(2, 5)
	sparkle.SpreadAngle = Vector2.new(35, 35)
	sparkle.Parent = glow

	local sign = invisible("PanneauBoite", CFrame.new(ccf.Position + Vector3.new(0, cs.Y / 2 + 18, 0)))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(360, 70)
	gui.MaxDistance = 900
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "BOÎTE À JOUETS"
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 214, 102)
	label.TextStrokeColor3 = Color3.fromRGB(60, 30, 20)
	label.TextStrokeTransparency = 0
	label.Parent = gui

	-- Zone de depot devant la boite ; les jouets de la base 2 s'exposent DANS la boite.
	-- La zone est renommee Base0Pantoufle : les bases sont attribuees par ordre de nom, le premier joueur recoit
	-- donc la pantoufle (la base vitrine). La recette la retrouve sous ses deux noms si on la relance.
	local zones = workspace:FindFirstChild("Chambre") and workspace.Chambre:FindFirstChild("Zones")
	local base2 = zones and (zones:FindFirstChild("Base0Pantoufle") or zones:FindFirstChild("Base2"))
	if base2 then
		base2.Name = "Base0Pantoufle"
		local frontZ = ccf.Position.Z + cs.Z / 2 + 30
		base2.Size = Vector3.new(90, 40, 70)
		base2.CFrame = CFrame.new(ccf.Position.X, surface(BOX.X, frontZ - ORIGIN.Z) + 18, frontZ)
		-- Coffres reels poses par BaseService : bas du coffre n°1 (face etoilee vers l'arrivee), coffres achetes
		-- alignes vers la droite avec un pas de 80 studs.
		base2:SetAttribute("DisplayCFrame", nil)
		base2:SetAttribute("DisplaySize", nil)
		base2:SetAttribute(
			"ChestCFrame",
			CFrame.new(ccf.Position.X, ccf.Position.Y - cs.Y / 2, ccf.Position.Z) * CFrame.Angles(0, math.rad(180), 0)
		)
		base2:SetAttribute("ChestStep", Vector3.new(80, 0, 0))
		base2:SetAttribute("ChestSize", 70)
		table.insert(out, "Base2 devant la boite a jouets")
	else
		table.insert(out, "Base2 introuvable : lancer build-chambre.luau d'abord")
	end

	-- 4. Petites lumieres qui flottent au-dessus de la fourrure et menent de l'arrivee a la boite.
	local lights = Instance.new("Folder")
	lights.Name = "Lucioles"
	lights.Parent = room
	local count = 9
	for i = 1, count do
		local t = i / (count + 1)
		-- L'arrivee est maintenant a cote de la boite : les lucioles alignees sur le trajet s'entassaient devant le
		-- coffre et se confondaient avec la boule de sortie (teste en jeu). Cercle large autour de la boite.
		local angle = t * math.pi * 2 + 0.4
		local radius = 80 + 40 * math.noise(i, 2.3)
		local x = BOX.X + math.cos(angle) * radius
		local z = BOX.Y + math.sin(angle) * radius
		local y = surface(x, z) + 7 + 3 * math.noise(i, 0.5)
		local orb = Instance.new("Part")
		orb.Name = "Luciole" .. i
		orb.Shape = Enum.PartType.Ball
		orb.Material = Enum.Material.Neon
		orb.Color = Color3.fromRGB(215, 235, 255)
		orb.Size = Vector3.new(1.2, 1.2, 1.2)
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanQuery = false
		orb.CastShadow = false
		orb.CFrame = CFrame.new(ORIGIN.X + x, y, ORIGIN.Z + z)
		orb.Parent = lights
		-- flaque de lumiere bleutee sur la fourrure autour de chaque luciole (reference : halo au sol)
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(190, 215, 255)
		l.Brightness = 2.5
		l.Range = 45
		l.Shadows = true
		l.Parent = orb
	end
	-- deux lueurs lointaines, hors du chemin, pour la profondeur
	for i, pos in { Vector2.new(-320, -120), Vector2.new(360, 60) } do
		local orb = Instance.new("Part")
		orb.Name = "LueurLointaine" .. i
		orb.Shape = Enum.PartType.Ball
		orb.Material = Enum.Material.Neon
		orb.Color = Color3.fromRGB(215, 235, 255)
		orb.Size = Vector3.new(1.5, 1.5, 1.5)
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanQuery = false
		orb.CastShadow = false
		orb.CFrame = CFrame.new(ORIGIN.X + pos.X, surface(pos.X, pos.Y) + 9, ORIGIN.Z + pos.Y)
		orb.Parent = lights
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(190, 215, 255)
		l.Brightness = 2
		l.Range = 45
		l.Parent = orb
	end
else
	table.insert(out, "manque DecorModels.ToyChest")
end

-- 5. Portes : ouverture du talon dans la chambre -> arrivee ; lumiere de sortie -> retour devant la pantoufle.
local slipper = workspace:FindFirstChild("Chambre") and workspace.Chambre.Decor:FindFirstChild("Base_Slipper")
if slipper then
	local scf, ss = slipper:GetBoundingBox()
	local front = scf.Position.Z - ss.Z / 2 -- cote chambre (talon ouvert, rotation 0)
	local outsidePos = Vector3.new(scf.Position.X, 4, front - 22)

	-- Declencheur AU FOND de la pantoufle (demande utilisateur : rentrer vraiment dedans a pied, pas s'approcher) :
	-- petit volume au milieu de la pantoufle, bas, qu'on n'atteint qu'en passant l'ouverture du talon. Teste en jeu :
	-- a pied le joueur avance jusqu'a z = bord + 29 puis bute (la pointe se resserre) ; vers la pointe (centre +13)
	-- le declencheur n'etait jamais touche.
	-- Le fond de la pantoufle est sureleve (mesure : rebord du talon ~8 studs une fois a 34 studs) : on cherche par
	-- rayons le point le plus bas de la surface cote talon (moitie chambre), et le declencheur se pose juste au-dessus.
	-- On y entre donc en sautant dans le talon, puis on se laisse glisser au fond.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { slipper }
	local insoleY, insoleZ = math.huge, scf.Position.Z
	for i = 0, 8 do
		local z = front + ss.Z * (0.05 + 0.5 * i / 8)
		local hit = workspace:Raycast(Vector3.new(scf.Position.X, 80, z), Vector3.new(0, -100, 0), rayParams)
		if hit and hit.Position.Y < insoleY then
			insoleY, insoleZ = hit.Position.Y, z
		end
	end
	if insoleY == math.huge then
		insoleY = 1
	end
	table.insert(out, string.format("fond de la pantoufle y %.1f a z %.0f", insoleY, insoleZ))
	local entree = invisible(
		"PorteEntreePantoufle",
		CFrame.new(scf.Position.X, insoleY + 3, insoleZ),
		Vector3.new(ss.X * 0.55, 6, ss.Z * 0.3)
	)
	entree.CanTouch = true
	-- le joueur arrive tourne vers la boite a jouets
	local boxLook = Vector3.new(ORIGIN.X + 0, inside.Y, ORIGIN.Z - 300)
	entree:SetAttribute("Destination", CFrame.lookAt(inside, boxLook))
	CS:AddTag(entree, "BaseDoor")

	-- Zone de sortie etroite (6 studs) : a 14 studs de large, elle englobait le point d'arrivee (a ~8 studs) et
	-- renvoyait le joueur dans la chambre des la fin du delai, sans qu'il bouge (teste en jeu).
	local sortie = invisible("PorteSortiePantoufle", CFrame.new(exitPos), Vector3.new(6, 14, 6))
	sortie.CanTouch = true
	sortie:SetAttribute("Destination", CFrame.lookAt(outsidePos, outsidePos + Vector3.new(0, 0, -1)))
	CS:AddTag(sortie, "BaseDoor")
	table.insert(out, "portes ok")
else
	table.insert(out, "Base_Slipper introuvable dans la chambre")
end

-- Repere pour l'ambiance cote client : volume de l'interieur.
local zone = invisible("ZoneInterieurPantoufle", CFrame.new(ORIGIN + Vector3.new(0, 40, 0)), Vector3.new(SIZE + 100, 400, SIZE + 100))
CS:AddTag(zone, "InteriorZone")
zone:SetAttribute("Ambiance", "Pantoufle")

-- pieces verrouillees contre les deplacements accidentels dans l'editeur (cf. build-chambre)
for _, d in (workspace:FindFirstChild("InterieurPantoufle") or Instance.new("Folder")):GetDescendants() do
	if d:IsA("BasePart") then
		d.Locked = true
	end
end
table.insert(out, "interieur pantoufle ok")
return table.concat(out, " | ")
