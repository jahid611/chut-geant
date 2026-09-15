-- Construit la chambre du bebe selon docs/mockups/plan-chambre.png, a partir des modeles de ServerStorage.
-- Lancee en mode edition via le MCP (node tools/run-recipe.mjs tools/scene/build-chambre.luau).
-- Rien n'est detruit : une ancienne chambre et les anciennes zones de test sont rangees dans ServerStorage.Archive.

local CS = game:GetService("CollectionService")
local SS = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")

local W, D, H = 800, 640, 360 -- largeur X, profondeur Z, hauteur des murs (studs ; un joueur mesure ~5 studs)
local out = {}

local archive = SS:FindFirstChild("Archive") or Instance.new("Folder")
archive.Name = "Archive"
archive.Parent = SS
for _, name in { "Chambre", "Zones", "ChambreEbauche", "Vitrine", "VitrineTeddy", "VitrineShoeBox", "VitrineCerealBox", "TestLissage", "Jouets", "Geant" } do
	local old = workspace:FindFirstChild(name)
	if old then
		-- Une chambre archivee ne doit plus porter de tags de jeu (ToySpawn, Base, GiantRoom...).
		for _, d in old:GetDescendants() do
			for _, tag in CS:GetTags(d) do
				CS:RemoveTag(d, tag)
			end
		end
		old.Name = name .. "_" .. os.time()
		old.Parent = archive
	end
end

local room = Instance.new("Model")
room.Name = "Chambre"
room.Parent = workspace
local structure = Instance.new("Folder", room)
structure.Name = "Structure"
local decor = Instance.new("Folder", room)
decor.Name = "Decor"
local zones = Instance.new("Folder", room)
zones.Name = "Zones"

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

-- Structure : sol, murs, plinthes, plafond
part(structure, "Sol", Vector3.new(W, 4, D), CFrame.new(0, -2, 0), Color3.fromRGB(190, 142, 96), Enum.Material.WoodPlanks)
local wallColor = Color3.fromRGB(150, 178, 214)
-- Mur du fond perce a l'emplacement de la fenetre (170 x 130, centree x = 0, y = 230) : on voit le vrai ciel de nuit.
local WIN_W, WIN_H, WIN_Y = 170, 130, 230
local zFond = -D / 2 - 4
local winBottom, winTop = WIN_Y - WIN_H / 2, WIN_Y + WIN_H / 2
local sideW = (W + 16 - WIN_W) / 2
part(structure, "MurFond", Vector3.new(W + 16, winBottom, 8), CFrame.new(0, winBottom / 2, zFond), wallColor)
part(structure, "MurFond", Vector3.new(W + 16, H - winTop, 8), CFrame.new(0, (H + winTop) / 2, zFond), wallColor)
part(structure, "MurFond", Vector3.new(sideW, WIN_H, 8), CFrame.new(-(WIN_W / 2 + sideW / 2), WIN_Y, zFond), wallColor)
part(structure, "MurFond", Vector3.new(sideW, WIN_H, 8), CFrame.new(WIN_W / 2 + sideW / 2, WIN_Y, zFond), wallColor)
part(structure, "MurFace", Vector3.new(W + 16, H, 8), CFrame.new(0, H / 2, D / 2 + 4), wallColor)
part(structure, "MurGauche", Vector3.new(8, H, D), CFrame.new(-W / 2 - 4, H / 2, 0), wallColor)
-- Mur droit perce pour la porte de la chambre (mini-jeu « Maman arrive ! »), avec un bout de couloir derriere.
local DOOR_Z, DOOR_W, DOOR_H = 180, 130, 290
local doorZ0, doorZ1 = DOOR_Z - DOOR_W / 2, DOOR_Z + DOOR_W / 2
part(structure, "MurDroit", Vector3.new(8, H, doorZ0 + D / 2), CFrame.new(W / 2 + 4, H / 2, (-D / 2 + doorZ0) / 2), wallColor)
part(structure, "MurDroit", Vector3.new(8, H, D / 2 - doorZ1), CFrame.new(W / 2 + 4, H / 2, (doorZ1 + D / 2) / 2), wallColor)
part(structure, "MurDroit", Vector3.new(8, H - DOOR_H, DOOR_W), CFrame.new(W / 2 + 4, (H + DOOR_H) / 2, DOOR_Z), wallColor)
local hall = Color3.fromRGB(225, 196, 160)
-- Couloir large et profond : la maman y attend cachee sur le cote, puis glisse devant la porte ouverte.
local HALL_DEPTH, HALL_LEN = 150, DOOR_W + 420
-- Le couloir ne fait pas d'ombre : pendant « Maman arrive ! » la lumiere de la lune passe a travers et n'entre dans la
-- chambre que par la porte (vraies ombres au sol, EventService:IsLitThroughDoor).
local noShadow = { CastShadow = false }
part(structure, "CouloirFond", Vector3.new(8, DOOR_H + 30, HALL_LEN), CFrame.new(W / 2 + 8 + HALL_DEPTH + 4, (DOOR_H + 30) / 2, DOOR_Z), hall, nil, noShadow)
part(structure, "CouloirSol", Vector3.new(HALL_DEPTH, 4, HALL_LEN), CFrame.new(W / 2 + 8 + HALL_DEPTH / 2, -2, DOOR_Z), Color3.fromRGB(150, 110, 75), Enum.Material.WoodPlanks, noShadow)
part(structure, "CouloirPlafond", Vector3.new(HALL_DEPTH, 4, HALL_LEN), CFrame.new(W / 2 + 8 + HALL_DEPTH / 2, DOOR_H + 32, DOOR_Z), hall, nil, noShadow)
for side = -1, 1, 2 do
	part(structure, "CouloirCote", Vector3.new(HALL_DEPTH, DOOR_H + 30, 8), CFrame.new(W / 2 + 8 + HALL_DEPTH / 2, (DOOR_H + 30) / 2, DOOR_Z + side * (HALL_LEN / 2 + 4)), hall, nil, noShadow)
end
local white = Color3.fromRGB(240, 236, 228)
part(structure, "PlintheFond", Vector3.new(W, 14, 3), CFrame.new(0, 7, -D / 2 + 1.5), white)
part(structure, "PlintheFace", Vector3.new(W, 14, 3), CFrame.new(0, 7, D / 2 - 1.5), white)
part(structure, "PlintheGauche", Vector3.new(3, 14, D), CFrame.new(-W / 2 + 1.5, 7, 0), white)
part(structure, "PlintheDroite", Vector3.new(3, 14, 180 - 65 + D / 2), CFrame.new(W / 2 - 1.5, 7, (-D / 2 + 115) / 2), white)
part(structure, "PlintheDroite", Vector3.new(3, 14, D / 2 - 245), CFrame.new(W / 2 - 1.5, 7, (245 + D / 2) / 2), white)
part(structure, "Plafond", Vector3.new(W + 16, 4, D + 16), CFrame.new(0, H + 2, 0), Color3.fromRGB(120, 135, 170))

-- Textures generees (assets/textures, ids d'Image releves depuis les Decals de assets/textures/registry.json)
local PARQUET = "rbxassetid://111036815924939"
local PAPIER_PEINT = "rbxassetid://98773939461556"
local function texture(target, face, image, tile, color)
	local t = Instance.new("Texture")
	t.Texture = image
	t.Face = face
	t.StudsPerTileU = tile
	t.StudsPerTileV = tile
	t.Color3 = color or Color3.new(1, 1, 1)
	t.Parent = target
end
local sol = structure:FindFirstChild("Sol")
sol.Material = Enum.Material.SmoothPlastic
sol.Color = Color3.fromRGB(255, 255, 255)
-- Echelle geant : 1 stud ~ 4 mm, une latte de 12 cm ~ 28 studs, soit ~250 studs pour les 9 lattes de la tuile.
texture(sol, Enum.NormalId.Top, PARQUET, 250)
for _, w in { { "MurFond", Enum.NormalId.Back }, { "MurFace", Enum.NormalId.Front }, { "MurGauche", Enum.NormalId.Right }, { "MurDroit", Enum.NormalId.Left } } do
	-- Un mur peut etre en plusieurs morceaux (mur du fond perce) : chaque morceau recoit la texture, decalee de sa
	-- position dans le mur entier pour que le motif continue sans raccord visible.
	local TILE = 320
	for _, wall in structure:GetChildren() do
		if wall.Name == w[1] and wall:IsA("BasePart") then
			wall.Color = Color3.fromRGB(255, 255, 255)
			local left = wall.Position.X - wall.Size.X / 2
			local top = wall.Position.Y + wall.Size.Y / 2
			local t = Instance.new("Texture")
			t.Texture = PAPIER_PEINT
			t.Face = w[2]
			t.StudsPerTileU = TILE
			t.StudsPerTileV = TILE
			t.Color3 = Color3.fromRGB(190, 205, 240)
			if w[1] == "MurFond" then
				t.OffsetStudsU = -((left + (W + 16) / 2) % TILE)
				t.OffsetStudsV = -((H - top) % TILE)
			end
			t.Parent = wall
		end
	end
end

-- Fenetre avec lune (mur du fond, au-dessus du berceau)
-- Vraie vitre : transparente, le ciel etoile et la lune de Roblox se voient a travers.
local glass = part(structure, "Fenetre", Vector3.new(170, 130, 1), CFrame.new(0, 230, -D / 2 + 1), Color3.fromRGB(170, 200, 255), Enum.Material.Glass, { Transparency = 0.85, CastShadow = false })
for _, f in {
	{ Vector3.new(190, 10, 4), CFrame.new(0, 300, -D / 2 + 2) },
	{ Vector3.new(190, 10, 4), CFrame.new(0, 160, -D / 2 + 2) },
	{ Vector3.new(10, 150, 4), CFrame.new(-90, 230, -D / 2 + 2) },
	{ Vector3.new(10, 150, 4), CFrame.new(90, 230, -D / 2 + 2) },
	{ Vector3.new(6, 130, 4), CFrame.new(0, 230, -D / 2 + 2) },
} do
	part(structure, "CadreFenetre", f[1], f[2], white)
end
-- La lune n'est plus une boule neon : c'est celle du ciel Roblox, placee dans l'axe de la fenetre (voir Lighting).
local moonLight = Instance.new("SpotLight")
moonLight.Color = Color3.fromRGB(150, 180, 255)
moonLight.Brightness = 5
moonLight.Range = 60
moonLight.Angle = 70
moonLight.Face = Enum.NormalId.Front
moonLight.Shadows = true
moonLight.Parent = glass
local moonBeam = part(structure, "RayonLune", Vector3.new(2, 2, 2), CFrame.lookAt(Vector3.new(0, 230, -D / 2 + 10), Vector3.new(0, 0, -40)), white, Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
local beamLight = Instance.new("SpotLight")
beamLight.Color = Color3.fromRGB(140, 170, 255)
beamLight.Brightness = 6
beamLight.Range = 60
beamLight.Angle = 45
beamLight.Face = Enum.NormalId.Front
beamLight.Shadows = true
beamLight.Parent = moonBeam

-- Tapis rond (zone silencieuse)
local RUG_Z = 70
local rug = part(structure, "Tapis", Vector3.new(1.2, 380, 380), CFrame.new(0, 0.6, RUG_Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(236, 226, 204), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
CS:AddTag(rug, "QuietZone")
rug.Color = Color3.fromRGB(255, 255, 255)
texture(rug, Enum.NormalId.Right, "rbxassetid://136740012456958", 120)
-- Tapis lune en peluche (Tripo) : s'il est charge, il remplace le cylindre, qui reste comme zone silencieuse invisible.
local rugModel = SS:FindFirstChild("DecorModels") and SS.DecorModels:FindFirstChild("Rug")
if rugModel then
	rug.Transparency = 1
	rug.CanCollide = false
	for _, t in rug:GetChildren() do
		t:Destroy()
	end
	local m = rugModel:Clone()
	m.Name = "TapisLune"
	local _, s = m:GetBoundingBox()
	-- Le GLB arrive debout (epaisseur sur Z) : on le couche si sa plus petite dimension n'est pas la hauteur.
	if s.Y > math.min(s.X, s.Z) then
		m:PivotTo(m:GetPivot() * CFrame.Angles(math.rad(-90), 0, 0))
		_, s = m:GetBoundingBox()
	end
	-- Epaisseur a l'echelle des joueurs (5 studs) : 26 studs de peluche feraient un mur. On ecrase la MeshPart sur
	-- son axe local qui pointe vers le haut, jusqu'a RUG_THICKNESS.
	local RUG_THICKNESS = 5
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			local up = p.CFrame:VectorToObjectSpace(Vector3.yAxis)
			local ax, ay, az = math.abs(up.X), math.abs(up.Y), math.abs(up.Z)
			local k = RUG_THICKNESS / s.Y
			if ax >= ay and ax >= az then
				p.Size = Vector3.new(p.Size.X * k, p.Size.Y, p.Size.Z)
			elseif ay >= az then
				p.Size = Vector3.new(p.Size.X, p.Size.Y * k, p.Size.Z)
			else
				p.Size = Vector3.new(p.Size.X, p.Size.Y, p.Size.Z * k)
			end
		end
	end
	_, s = m:GetBoundingBox()
	-- Recule vers le berceau : le bord avant s'arrete avant les bases (mur de face a z = 250).
	m:PivotTo(CFrame.new(0, s.Y / 2, RUG_Z) * m:GetPivot().Rotation)
	m.Parent = structure
end

-- Modeles
local function place(folderName, modelName, position, rotY, parent, name)
	local folder = SS:FindFirstChild(folderName)
	local src = folder and folder:FindFirstChild(modelName)
	if not src then
		table.insert(out, "manque " .. folderName .. "." .. modelName)
		return nil
	end
	local c = src:Clone()
	c.Name = name or modelName
	local _, s = c:GetBoundingBox()
	c:PivotTo(CFrame.new(position.X, s.Y / 2 + (position.Y or 0), position.Z) * CFrame.Angles(0, math.rad(rotY or 0), 0))
	c.Parent = parent or decor
	return c
end

-- Rotation du berceau : sa longueur doit suivre l'axe X (le bebe est couche dans ce sens).
-- Berceau v2 : un seul grand cote a un tour de lit plein (qui cachait le bebe) ; a 180 il est contre le mur de la
-- fenetre et les barreaux regardent la chambre.
local CRIB_ROT = 180
-- Berceau v2 (avec couverture) s'il est charge, sinon le premier.
local cribName = if SS.DecorModels:FindFirstChild("Crib2") then "Crib2" else "Crib"
local crib = place("DecorModels", cribName, Vector3.new(0, 0, -150), CRIB_ROT, decor, "Crib")
-- Tiroirs vers le centre de la piece (le modele Tripo regarde vers -Z).
place("DecorModels", "Dresser", Vector3.new(-316, 0, -10), -90, decor, "CommodeGauche")
place("DecorModels", "Dresser", Vector3.new(316, 0, -10), 90, decor, "CommodeDroite")
place("DecorModels", "Bookcase", Vector3.new(-285, 0, -240), 180)
place("DecorModels", "WallShelf", Vector3.new(-396, 170, 150), 90)
place("DecorModels", "ToyChest", Vector3.new(285, 0, -240), 180)
-- Les objets laches par terre subissent la gravite : on les desancre, la physique tourne quelques secondes
-- (Workspace:StepPhysics, disponible en edition pour les plugins), puis on les reancre la ou ils sont tombes.
-- ATTENTION : Workspace:StepPhysics ne deplace rien ici en edition (mesure : bebe 55 studs au-dessus de la couverture,
-- pantoufle 1 stud au-dessus du parquet alors que la recette annoncait « pose par gravite »). La gravite est donc
-- simulee par rayons : sous toute l'empreinte de l'objet, on mesure l'ecart entre son dessous et ce qu'il y a en
-- dessous, et l'objet descend de l'ecart le plus petit, jusqu'au premier point de contact.
local function worldBounds(model)
	local minV, maxV = nil, nil
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local cf, s = p.CFrame, p.Size / 2
			for _, c in { Vector3.new(1, 1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, -1, -1) } do
				local w = cf:PointToWorldSpace(s * c)
				minV = if minV then Vector3.new(math.min(minV.X, w.X), math.min(minV.Y, w.Y), math.min(minV.Z, w.Z)) else w
				maxV = if maxV then Vector3.new(math.max(maxV.X, w.X), math.max(maxV.Y, w.Y), math.max(maxV.Z, w.Z)) else w
			end
		end
	end
	return minV, maxV
end

-- maxGroundY (facultatif) : on ignore les appuis plus hauts, pour qu'un objet se couche au fond d'un contenant
-- au lieu de rester pose sur ses bords (bebe sur les barreaux ou le bord de l'oreiller).
local function settle(model, _seconds, extraExclude, maxGroundY)
	local minV, maxV = worldBounds(model)
	if not minV then
		return
	end
	local onlyModel = RaycastParams.new()
	onlyModel.FilterType = Enum.RaycastFilterType.Include
	onlyModel.FilterDescendantsInstances = { model }
	local exclude = { model, zones }
	for _, e in extraExclude or {} do
		table.insert(exclude, e)
	end
	local others = RaycastParams.new()
	others.FilterType = Enum.RaycastFilterType.Exclude
	others.FilterDescendantsInstances = exclude
	local drop, N = math.huge, 6
	for i = 0, N do
		for j = 0, N do
			local x = minV.X + (maxV.X - minV.X) * (0.05 + 0.9 * i / N)
			local z = minV.Z + (maxV.Z - minV.Z) * (0.05 + 0.9 * j / N)
			-- dessous de l'objet a cet endroit (rayon qui monte depuis sous sa boite)
			local under = workspace:Raycast(Vector3.new(x, minV.Y - 1, z), Vector3.new(0, maxV.Y - minV.Y + 2, 0), onlyModel)
			if under then
				local ground = workspace:Raycast(under.Position - Vector3.new(0, 0.05, 0), Vector3.new(0, -400, 0), others)
				if ground and (maxGroundY == nil or ground.Position.Y <= maxGroundY) then
					drop = math.min(drop, under.Position.Y - ground.Position.Y)
				end
			end
		end
	end
	if drop < math.huge then
		model:PivotTo(model:GetPivot() - Vector3.new(0, drop, 0))
		table.insert(out, string.format("%s pose au contact (descente %.1f)", model.Name, drop))
	else
		table.insert(out, model.Name .. " : aucun sol trouve dessous")
	end
end

local rings = place("DecorModels", "StackingRings", Vector3.new(-185, 0, -255), 20)
if rings then
	-- La pyramide d'anneaux a ete renversee par le bebe : lachee penchee, elle tombe sur le cote.
	local cf, s = rings:GetBoundingBox()
	rings:PivotTo(CFrame.new(cf.Position.X, s.Y / 2 + 2, cf.Position.Z) * CFrame.Angles(0, math.rad(35), 0) * CFrame.Angles(0, 0, math.rad(70)))
	settle(rings, 4)
end

-- Anneau de dentition tombe du berceau : lache penche entre le tapis et le berceau, pose par gravite.
local teether = place("DecorModels", "Rattle", Vector3.new(150, 0, -70), 40)
if teether then
	local cf, s = teether:GetBoundingBox()
	teether:PivotTo(CFrame.new(cf.Position.X, s.Y / 2 + 6, cf.Position.Z) * CFrame.Angles(math.rad(65), math.rad(40), 0))
	settle(teether, 3)
end

-- Veilleuses = vraies sources de lumiere. Une PointLight Roblox porte au plus 60 studs alors qu'une commode en mesure 150 :
-- la lumiere de chaque lampe est repartie sur plusieurs sources (au-dessus de la lampe, mur, facade, flaque au sol),
-- comme la lueur d'une veilleuse qui s'etale, et la lampe elle-meme brille (emissive de sa SurfaceAppearance).
local function lightPoint(parent, name, position, color, brightness, shadows)
	local p = part(parent, name, Vector3.new(1, 1, 1), CFrame.new(position), white, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = 60
	l.Shadows = shadows
	l.Parent = p
end

-- Deux lampes differentes : champignon a gauche, capybara a droite. rot = rotation autour de Y, 0 = face vers la piece.
local LAMPS = {
	{ dresser = "CommodeGauche", name = "VeilleuseGauche", model = "NightLamp", rot = 0, color = Color3.fromRGB(255, 150, 80) },
	{ dresser = "CommodeDroite", name = "VeilleuseDroite", model = "NightLamp2", rot = 0, color = Color3.fromRGB(255, 196, 96) },
}
for _, spec in LAMPS do
	local dresser = decor:FindFirstChild(spec.dresser)
	if dresser then
		local cf, s = dresser:GetBoundingBox()
		local top = cf.Position.Y + s.Y / 2
		local lamp = place("DecorModels", spec.model, Vector3.new(cf.Position.X, top, cf.Position.Z), spec.rot, decor, spec.name)
		if lamp then
			local lcf, ls = lamp:GetBoundingBox()
			for _, d in lamp:GetDescendants() do
				if d:IsA("SurfaceAppearance") then
					pcall(function()
						d.EmissiveStrength = 3
						d.EmissiveTint = spec.color
					end)
				end
			end
			local lights = Instance.new("Folder")
			lights.Name = "Lumieres"
			lights.Parent = decor
			local inward = -math.sign(lcf.Position.X) -- vers le centre de la piece
			local x, z = lcf.Position.X, lcf.Position.Z
			local lampTop = top + ls.Y
			-- Une seule source a 60 studs dessine un disque net : on repartit la lueur sur 6 sources qui se chevauchent
			-- et faiblissent en s'eloignant. Pas plus de 6 par lampe : au-dela, le moteur abandonne des lumieres quand
			-- trop se recouvrent a l'ecran (verifie : 28 sources = commode de droite eteinte). Aucune source a moins de
			-- 45 studs d'un mur (sinon disque net sur le papier peint).
			-- { vers la piece, hauteur par rapport au haut de la lampe, lateral, luminosite, ombres }
			local SOURCES = {
				{ 8, 25, 0, 1.4, true }, -- au-dessus de la lampe : dessus de la commode, ombre de la lampe
				{ 55, 0, 0, 0.5, false }, -- bord avant du dessus
				{ 30, -10, 60, 0.35, false }, -- cote gauche du dessus
				{ 30, -10, -60, 0.35, false }, -- cote droit du dessus
				{ 100, -60, 0, 0.5, false }, -- facade des tiroirs, lumiere qui descend
				{ 150, -135, 0, 0.35, false }, -- lueur au sol devant la commode
			}
			for i, o in SOURCES do
				local pos = Vector3.new(x + inward * o[1], math.max(lampTop + o[2], 20), z + o[3])
				lightPoint(lights, string.format("%s_Lueur%d", spec.name, i), pos, spec.color, o[4], o[5])
			end
		end
	end
end

-- Le bebe dans le berceau : endormi visible, qui pleure cache (BabyVisualService bascule selon Geant.State)
local geant = Instance.new("Model")
geant.Name = "Geant"
geant:SetAttribute("State", "Sleeping")
geant.Parent = workspace
if crib then
	local ccf, cs = crib:GetBoundingBox()
	-- Hauteur reelle du matelas : rayon vertical sur le seul berceau (57 studs pour le modele Tripo).
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { crib }
	-- Mediane de 9 rayons sur le couchage (hors tetes de lit) : un seul rayon au centre peut tomber dans un creux
	-- de la couverture (berceau v2 : 48 au centre pour 110 autour).
	local heights = {}
	for _, dx in { -45, 0, 45 } do
		for _, dz in { -30, 0, 30 } do
			local r = workspace:Raycast(ccf.Position + Vector3.new(dx, 300, dz), Vector3.new(0, -600, 0), rayParams)
			if r then
				table.insert(heights, r.Position.Y)
			end
		end
	end
	table.sort(heights)
	local mattressY = if #heights > 0 then heights[math.ceil(#heights / 2)] else ccf.Position.Y - cs.Y / 2 + cs.Y * 0.32
	table.insert(out, string.format("couchage y%.0f", mattressY))
	-- Le dos et la couverture s'enfoncent dans le matelas, sinon le bebe semble leviter.
	local BABY_SINK = 22
	local BABY_SCALE = 0.8
	for _, pair in { { "BodySleeping", "Dort" }, { "BodyCrying", "Pleure" } } do
		local src = SS.BabyParts:FindFirstChild(pair[1])
		if src then
			local b = src:Clone()
			b.Name = pair[2]
			-- Le berceau v2 est plus etroit : a 160 studs le bebe depassait des barreaux. 80 % le couche dedans.
			b:ScaleTo(b:GetScale() * BABY_SCALE)
			b:PivotTo(CFrame.new(ccf.Position.X, mattressY + 40, ccf.Position.Z) * CFrame.Angles(0, math.rad(90 + CRIB_ROT), 0) * CFrame.Angles(math.rad(90), 0, 0))
			local _, bs = b:GetBoundingBox()
			b:PivotTo(b:GetPivot() + Vector3.new(0, (mattressY - BABY_SINK + bs.Y / 2) - (b:GetBoundingBox()).Position.Y, 0))
			b.Parent = geant
			if pair[2] == "Pleure" then
				for _, d in b:GetDescendants() do
					if d:IsA("BasePart") then
						d.Transparency = 1
					end
				end
			end
		end
	end
	-- Gravite : le bebe endormi est lache au-dessus de la couverture et retombe dans le berceau ; celui qui pleure
	-- (invisible) ne gene pas la chute puis prend exactement la meme pose. Collisions precises sur le berceau et le
	-- bebe, sinon le bebe se pose sur la boite englobante du berceau et semble leviter.
	local function preciseCollisions(model)
		for _, d in model:GetDescendants() do
			if d:IsA("MeshPart") then
				pcall(function()
					d.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
				end)
			end
		end
	end
	local function setCollide(model, on)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = on
			end
		end
	end
	local dort, pleure = geant:FindFirstChild("Dort"), geant:FindFirstChild("Pleure")
	preciseCollisions(crib)
	if dort then
		preciseCollisions(dort)
		if pleure then
			setCollide(pleure, false)
		end
		-- Juste au-dessus de la couverture (sous les tetes de lit, pour ne pas s'y poser), descente jusqu'au premier
		-- contact, puis 6 studs d'enfoncement : la couverture est moelleuse.
		local babyMin = worldBounds(dort)
		dort:PivotTo(dort:GetPivot() + Vector3.new(0, mattressY + 15 - babyMin.Y, 0))
		settle(dort, 0, { pleure }, mattressY + 12)
		dort:PivotTo(dort:GetPivot() - Vector3.new(0, 6, 0))
		if pleure then
			pleure:PivotTo(dort:GetPivot())
			setCollide(pleure, true)
		end
	end

	local pac = SS.BabyParts:FindFirstChild("Pacifier")
	if pac then
		local p = pac:Clone()
		p.Name = "Tetine"
		-- Lachee au-dessus du matelas, a cote de la tete du bebe : elle retombe par gravite.
		-- la tete du bebe suit l'oreiller (bord a couronne) du berceau v2 corrige du miroir : cote -X une fois tourne a 180
		local headSide = if CRIB_ROT == 180 then -1 else 1
		p:PivotTo(CFrame.new(ccf.Position.X + 55 * headSide, mattressY + 40, ccf.Position.Z + 35) * CFrame.Angles(math.rad(60), math.rad(25), 0))
		p.Parent = geant
		settle(p, 3)
	end
	local mob = SS.DecorModels:FindFirstChild("Mobile")
	if mob then
		local m = mob:Clone()
		m:PivotTo(CFrame.new(ccf.Position.X, ccf.Position.Y + cs.Y / 2 + 60, ccf.Position.Z))
		m.Parent = decor
	end
	-- Point legendaire sur le matelas, a cote du bebe
	local legend = part(zones, "SpawnLegendaire", Vector3.new(4, 1, 4), CFrame.new(ccf.Position.X + 60, mattressY, ccf.Position.Z), white, nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	legend:SetAttribute("Rarity", "Legendary")
	CS:AddTag(legend, "ToySpawn")

	-- Trampoline devant le berceau, cote du jouet legendaire (demande utilisateur du 15/09) : la toile invisible
	-- taguee « Trampoline » renvoie le joueur en cloche sur le matelas (TrampolineService, attribut Target).
	local trampoSrc = SS.DecorModels:FindFirstChild("Trampoline")
	if trampoSrc then
		local tramp = trampoSrc:Clone()
		tramp.Name = "Trampoline"
		local tx, tz = ccf.Position.X + 60, ccf.Position.Z + math.max(cs.X, cs.Z) / 2 + 34
		tramp:PivotTo(CFrame.new(tx, 30, tz))
		tramp.Parent = decor
		settle(tramp, 3)
		for _, p in tramp:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
			end
		end
		local tcf, tsize = tramp:GetBoundingBox()
		local pad = part(zones, "ToileTrampoline", Vector3.new(tsize.X * 0.8, 2, tsize.Z * 0.8), CFrame.new(tcf.Position.X, tcf.Position.Y + tsize.Y / 2, tcf.Position.Z), white, nil, { Transparency = 1, CanCollide = false, CanQuery = false })
		pad:SetAttribute("Target", Vector3.new(ccf.Position.X + 60, mattressY + 4, ccf.Position.Z))
		-- sommet du vol : 30 studs au-dessus du haut du berceau (le rebord arretait le joueur)
		pad:SetAttribute("Apex", ccf.Position.Y + cs.Y / 2 + 30)
		CS:AddTag(pad, "Trampoline")
		table.insert(out, "trampoline pose devant le berceau")
	else
		table.insert(out, "trampoline absent (DecorModels.Trampoline)")
	end
end

-- Bases des joueurs le long du mur de face
local baseNames = { "ShoeBox", "Slipper", "TissueBox", "CerealBox", "Drawer", "MovingBox" }
-- Rotations verifiees par capture de face : la face du modele regarde la chambre (tiroir 0, pantoufle 270, le reste 180).
-- Rangee des bases collee au mur de face (face interieure a z = 320), a distance du tapis (bord avant z = 223).
local BASE_Z = 290
local baseRotations = { ShoeBox = 180, Slipper = 270, Slipper2 = 0, TissueBox = 180, CerealBox = 180, Drawer = 0, MovingBox = 180 }
for i, modelName in baseNames do
	local x = -325 + (i - 1) * 130
	-- La pantoufle lapin ouverte au talon (Slipper2) remplace l'ancienne des qu'elle est chargee.
	local sourceName = if modelName == "Slipper" and SS.BaseModels:FindFirstChild("Slipper2") then "Slipper2" else modelName
	local rotation = baseRotations[sourceName] or baseRotations[modelName]
	local baseModel = place("BaseModels", sourceName, Vector3.new(x, 1, BASE_Z), rotation, decor, "Base_" .. modelName)
	if baseModel and sourceName == "Slipper2" then
		-- Pantoufle ramenee a 34 studs (au lieu de 60) : trop haute pour un joueur de 5 studs (retour utilisateur,
		-- mesure : fond cote talon a 10-14 studs). A 34, le rebord du talon passe sous la hauteur d'un saut.
		local _, rawSize = baseModel:GetBoundingBox()
		baseModel:ScaleTo(baseModel:GetScale() * (34 / math.max(rawSize.X, rawSize.Y, rawSize.Z)))
		local pcf, psz = baseModel:GetBoundingBox()
		baseModel:PivotTo(baseModel:GetPivot() + Vector3.new(0, psz.Y / 2 + 1 - pcf.Position.Y, 0))
		-- Base ou l'on entre : collisions qui suivent la vraie forme (sinon une boite invisible bouche l'ouverture).
		for _, p in baseModel:GetDescendants() do
			if p:IsA("MeshPart") then
				local ok = pcall(function()
					p.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
				end)
				table.insert(out, "Slipper2 collisions precises " .. tostring(ok))
			end
			if p:IsA("BasePart") then
				p.CastShadow = true
			end
		end
		-- Posee par gravite : la semelle touche vraiment le parquet (plus d'air dessous, donc une ombre de contact).
		settle(baseModel, 3)
	elseif baseModel and modelName == "CerealBox" then
		-- Le maillage Tripo de la boite est penche d'environ 8 degres : on le redresse puis on le repose au sol.
		baseModel:PivotTo(baseModel:GetPivot() * CFrame.Angles(0, 0, math.rad(8)))
		local cf, s = baseModel:GetBoundingBox()
		baseModel:PivotTo(baseModel:GetPivot() + Vector3.new(0, s.Y / 2 - cf.Position.Y, 0))
	elseif baseModel then
		settle(baseModel, 3)
	end
	local zone = part(zones, "Base" .. i, Vector3.new(90, 60, 60), CFrame.new(x, 30, BASE_Z), white, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	CS:AddTag(zone, "Base")
end

-- Points d'apparition des jouets, par rarete (plus pres du bebe = plus rare)
local spawns = {
	{ "Common", Vector3.new(-74, 0, 136) }, { "Common", Vector3.new(74, 0, 136) }, { "Common", Vector3.new(0, 0, 174) },
	{ "Common", Vector3.new(-236, 0, 136) }, { "Common", Vector3.new(236, 0, 136) },
	{ "Uncommon", Vector3.new(-120, 0, 40) }, { "Uncommon", Vector3.new(120, 0, 40) },
	{ "Rare", Vector3.new(-161, 0, -62) }, { "Rare", Vector3.new(161, 0, -62) }, { "Rare", Vector3.new(-217, 0, -161) },
	{ "Epic", Vector3.new(-130, 0, -205) }, { "Epic", Vector3.new(130, 0, -149) },
}
-- Chaque point se pose sur ce qu'il y a dessous (parquet ou tapis), pour qu'un jouet n'apparaisse pas enfonce.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.FilterDescendantsInstances = { zones }
for i, s in spawns do
	local ground = workspace:Raycast(Vector3.new(s[2].X, 120, s[2].Z), Vector3.new(0, -240, 0), groundParams)
	local groundY = if ground then ground.Position.Y else 0
	local p = part(zones, "Spawn" .. i, Vector3.new(4, 1, 4), CFrame.new(s[2].X, groundY + 0.5, s[2].Z), white, nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	p:SetAttribute("Rarity", s[1])
	CS:AddTag(p, "ToySpawn")
end
-- Trois fois plus de jouets (retour utilisateur « il y a peu de jouets ») : 24 points de plus tires sur une grille du
-- sol libre (parquet ou tapis, pas sur un meuble), a 45 studs au moins les uns des autres ; rarete selon la
-- distance au berceau (au fond, z negatif).
local EXTRA_SPAWNS = 24
local rng = Random.new(2026)
local candidates = {}
for x = -340, 340, 34 do
	for z = -250, 220, 34 do
		table.insert(candidates, Vector3.new(x + rng:NextNumber(-8, 8), 0, z + rng:NextNumber(-8, 8)))
	end
end
for i = #candidates, 2, -1 do
	local j = rng:NextInteger(1, i)
	candidates[i], candidates[j] = candidates[j], candidates[i]
end
local taken = {}
for _, s in spawns do
	table.insert(taken, Vector3.new(s[2].X, 0, s[2].Z))
end
local added = 0
for _, c in candidates do
	if added >= EXTRA_SPAWNS then
		break
	end
	local free = true
	for _, t in taken do
		if (t - c).Magnitude < 45 then
			free = false
			break
		end
	end
	-- rayon depuis sous le plafond : s'il touche un meuble (haut), le point est rejete
	local ground = if free then workspace:Raycast(Vector3.new(c.X, 340, c.Z), Vector3.new(0, -400, 0), groundParams) else nil
	if ground and ground.Position.Y < 8 then
		local rarity = if c.Z > 100 then "Common" elseif c.Z > 0 then "Uncommon" elseif c.Z > -180 then "Rare" else "Epic"
		local p = part(zones, "SpawnPlus" .. added + 1, Vector3.new(4, 1, 4), CFrame.new(c.X, ground.Position.Y + 0.5, c.Z), white, nil, { Transparency = 1, CanCollide = false, CanQuery = false })
		p:SetAttribute("Rarity", rarity)
		CS:AddTag(p, "ToySpawn")
		table.insert(taken, c)
		added += 1
	end
end
table.insert(out, "points de jouets en plus : " .. added)

-- Lattes qui grincent et cachettes sous les commodes
-- Lattes hors du tapis (le tapis est une zone silencieuse) : de part et d'autre, et entre le tapis et le berceau.
for i, pos in { Vector3.new(-215, 0, 12), Vector3.new(215, 0, 12), Vector3.new(-120, 0, -95) } do
	local creak = part(zones, "Latte" .. i, Vector3.new(70, 0.4, 16), CFrame.new(pos.X, 0.2, pos.Z), Color3.fromRGB(160, 112, 70), Enum.Material.WoodPlanks, { CanCollide = false })
	CS:AddTag(creak, "Creak")
end
for i, x in { -316, 316 } do
	local hide = part(zones, "Cachette" .. i, Vector3.new(60, 20, 120), CFrame.new(x, 10, -10), white, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	CS:AddTag(hide, "HideZone")
end

-- Zones d'ombre du mini-jeu « Vite, dans l'ombre ! » (EventService) : disques invisibles poses sur le sol reel,
-- affiches en violet par le client pendant le compte a rebours. Repartis pour qu'on en atteigne un en ~5 s
-- (vitesse 14 studs/s) depuis presque partout : sous les meubles, derriere le berceau, pres des bases.
local shadowSpots = {
	{ -316, -10, 60 }, -- sous la commode gauche
	{ 316, -10, 60 }, -- sous la commode droite
	{ 0, -150, 75 }, -- sous le berceau
	{ -285, -240, 48 }, -- au pied de la bibliotheque
	{ 285, -240, 48 }, -- au pied du coffre a jouets
	{ -190, 150, 42 },
	{ 190, 150, 42 },
	{ 0, 250, 42 },
	{ -330, 235, 42 },
	{ 330, 235, 42 },
	{ -150, -70, 38 },
	{ 150, -70, 38 },
}
local groundParamsShadow = RaycastParams.new()
groundParamsShadow.FilterType = Enum.RaycastFilterType.Exclude
groundParamsShadow.FilterDescendantsInstances = { zones, decor }
for i, s in shadowSpots do
	local ground = workspace:Raycast(Vector3.new(s[1], 120, s[2]), Vector3.new(0, -240, 0), groundParamsShadow)
	local y = if ground then ground.Position.Y else 0
	local disc = part(
		zones,
		"Ombre" .. i,
		Vector3.new(0.6, s[3] * 2, s[3] * 2),
		CFrame.new(s[1], y + 0.35, s[2]) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(120, 70, 200),
		Enum.Material.Neon,
		{ Shape = Enum.PartType.Cylinder, Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	)
	disc:SetAttribute("Radius", s[3])
	CS:AddTag(disc, "ShadowZone")
end

-- Porte de la chambre (mini-jeu « Maman arrive ! ») sur le mur droit : charniere taguee MomDoor, lumiere du couloir
-- (eteinte, allumee quand la porte s'ouvre) et, des qu'il existe, le battant 3D (DecorModels.BedroomDoor).
local porte = Instance.new("Model")
porte.Name = "PorteChambre"
porte.Parent = structure
-- (DOOR_Z, DOOR_W, DOOR_H definis avec le mur droit)
local hinge =part(porte, "Charniere", Vector3.new(1, DOOR_H, 1), CFrame.new(W / 2 - 1, DOOR_H / 2, DOOR_Z + DOOR_W / 2), white, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
CS:AddTag(hinge, "MomDoor")
local corridor = part(porte, "LumiereCouloir", Vector3.new(1, 1, 1), CFrame.lookAt(Vector3.new(W / 2 - 4, DOOR_H * 0.8, DOOR_Z), Vector3.new(0, 0, DOOR_Z)), white, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
local corridorLight = Instance.new("SpotLight")
corridorLight.Face = Enum.NormalId.Front
corridorLight.Color = Color3.fromRGB(255, 214, 150)
corridorLight.Brightness = 6
corridorLight.Range = 60
corridorLight.Angle = 70
corridorLight.Shadows = true
corridorLight.Enabled = false
corridorLight.Parent = corridor
local doorSrc = SS.DecorModels:FindFirstChild("BedroomDoor")
if doorSrc then
	local leaf = doorSrc:Clone()
	leaf.Name = "Battant"
	local _, ds = leaf:GetBoundingBox()
	leaf:ScaleTo(leaf:GetScale() * (DOOR_H / ds.Y))
	local _, ds2 = leaf:GetBoundingBox()
	-- face vers la chambre (-X)
	leaf:PivotTo(CFrame.new(W / 2 + 4, ds2.Y / 2, DOOR_Z) * CFrame.Angles(0, math.rad(-90), 0))
	-- Encastree dans l'ouverture du mur : le modele fait 168 de large et 61 d'epaisseur (il ressortait de 30 studs
	-- dans la chambre). Chaque piece est etiree sur les axes du monde : largeur = ouverture, epaisseur = DOOR_THICK.
	local DOOR_THICK = 10
	local k = Vector3.new(DOOR_THICK / ds2.Z, 1, DOOR_W / ds2.X)
	local center = leaf:GetBoundingBox().Position
	for _, p in leaf:GetDescendants() do
		if p:IsA("BasePart") then
			local axes = { p.CFrame.RightVector, p.CFrame.UpVector, p.CFrame.LookVector }
			local f = {}
			for i, a in axes do
				f[i] = math.abs(a.X) * k.X + math.abs(a.Y) * k.Y + math.abs(a.Z) * k.Z
			end
			local rel = p.Position - center
			local rotation = p.CFrame.Rotation
			p.Size = Vector3.new(p.Size.X * f[1], p.Size.Y * f[2], p.Size.Z * f[3])
			p.CFrame = CFrame.new(center + rel * k) * rotation
		end
	end
	local bb, bs = leaf:GetBoundingBox()
	leaf:PivotTo(leaf:GetPivot() + (Vector3.new(W / 2 + 4, bs.Y / 2, DOOR_Z) - bb.Position))
	leaf.Parent = porte
	table.insert(out, string.format("porte 3D encastree %.0f x %.0f x %.0f", bs.X, bs.Y, bs.Z))
else
	table.insert(out, "porte 3D absente (DecorModels.BedroomDoor) : lumiere du couloir seule")
end
-- La maman (DecorModels.Mom) attend cachee sur le cote du couloir ; EventService la fait glisser devant la porte
-- ouverte (PoseVisible) puis repartir (PoseCachee). Lampe du telephone : SpotLight sur « LampeMaman ».
local momSrc = SS.DecorModels:FindFirstChild("Mom")
if momSrc then
	local MOM_H = DOOR_H - 20
	-- rotation pour que son visage regarde la chambre (-X), verifiee en capture de face (a -90 on la voyait de dos)
	local MOM_ROT = 90
	local mom = momSrc:Clone()
	mom.Name = "Maman"
	local _, ms = mom:GetBoundingBox()
	mom:ScaleTo(mom:GetScale() * (MOM_H / ms.Y))
	for _, p in mom:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	local momX = W / 2 + 8 + HALL_DEPTH / 2
	mom:PivotTo(CFrame.new(momX, 0, DOOR_Z) * CFrame.Angles(0, math.rad(MOM_ROT), 0))
	local mb, msz = mom:GetBoundingBox()
	-- pieds sur le sol du couloir, centree devant la porte
	mom:PivotTo(mom:GetPivot() + Vector3.new(momX - mb.Position.X, msz.Y / 2 - mb.Position.Y, DOOR_Z - mb.Position.Z))
	local visible = mom:GetPivot()
	local _, worldSize = mom:GetBoundingBox()
	local lamp = part(mom, "LampeMaman", Vector3.new(1, 1, 1), CFrame.lookAt(Vector3.new(momX - 45, MOM_H * 0.62, DOOR_Z), Vector3.new(0, 0, DOOR_Z)), white, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	local beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Front
	beam.Color = Color3.fromRGB(235, 242, 255)
	beam.Brightness = 10
	beam.Range = 60
	beam.Angle = 40
	beam.Shadows = true
	beam.Enabled = false
	beam.Parent = lamp
	local hidden = visible + Vector3.new(0, 0, DOOR_W / 2 + math.max(worldSize.X, worldSize.Z) / 2 + 40)
	mom:SetAttribute("PoseVisible", visible)
	mom:SetAttribute("PoseCachee", hidden)
	mom:PivotTo(hidden)
	mom.Parent = porte
	table.insert(out, string.format("maman posee (%.0f de haut), cachee dans le couloir", MOM_H))
else
	table.insert(out, "maman absente (DecorModels.Mom)")
end

-- Ombres de contact : Roblox ne dessine pas l'ombre douce qui se forme la ou un objet touche le sol, et sans elle
-- tout semble leviter. Une tache sombre degradee (image generee, assets/textures/ombre-contact) est posee sous chaque
-- objet dont le bas touche le parquet ou le tapis, a la taille de son empreinte.
local OMBRE = "rbxassetid://123681637407382"
local shadowFolder = Instance.new("Folder")
shadowFolder.Name = "OmbresContact"
shadowFolder.Parent = decor
local shadowParams = RaycastParams.new()
shadowParams.FilterType = Enum.RaycastFilterType.Exclude
shadowParams.FilterDescendantsInstances = { zones, shadowFolder }
local function contactShadow(model)
	local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local cf, s = p.CFrame, p.Size / 2
			for _, c in { Vector3.new(1, 1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, -1, -1) } do
				local w = cf:PointToWorldSpace(s * c)
				minV = Vector3.new(math.min(minV.X, w.X), math.min(minV.Y, w.Y), math.min(minV.Z, w.Z))
				maxV = Vector3.new(math.max(maxV.X, w.X), math.max(maxV.Y, w.Y), math.max(maxV.Z, w.Z))
			end
		end
	end
	if minV.Y == math.huge then
		return
	end
	local center = (minV + maxV) / 2
	local ground = workspace:Raycast(Vector3.new(center.X, minV.Y + 2, center.Z), Vector3.new(0, -12, 0), shadowParams)
	if not ground or minV.Y - ground.Position.Y > 6 then
		return -- objet pose en hauteur (lampe, etagere murale, mobile) : pas d'ombre au sol
	end
	local size = Vector3.new((maxV.X - minV.X) * 1.25, 0.2, (maxV.Z - minV.Z) * 1.25)
	local p = part(shadowFolder, "Ombre_" .. model.Name, size, CFrame.new(center.X, ground.Position.Y + 0.15, center.Z), white, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	local decal = Instance.new("Decal")
	decal.Texture = OMBRE
	decal.Face = Enum.NormalId.Top
	decal.Transparency = 0.35
	decal.Parent = p
end
for _, m in decor:GetChildren() do
	if m:IsA("Model") then
		contactShadow(m)
	end
end
table.insert(out, "ombres de contact " .. #shadowFolder:GetChildren())

-- Zone de la chambre (bruit, chasse)
local roomZone = part(zones, "ZoneChambre", Vector3.new(W, H, D), CFrame.new(0, H / 2, 0), white, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
CS:AddTag(roomZone, "GiantRoom")

-- Apparition des joueurs : au milieu des bases
local spawnLoc = Instance.new("SpawnLocation")
spawnLoc.Name = "ApparitionJoueurs"
spawnLoc.Anchored = true
spawnLoc.Size = Vector3.new(12, 1, 12)
spawnLoc.CFrame = CFrame.new(0, 0.5, 252)
spawnLoc.Transparency = 1
spawnLoc.CanCollide = false
spawnLoc.Parent = room

-- Eclairage de nuit
-- Nuit lisible : ambiance bleue assez claire pour voir jouets et bebe, la veilleuse chauffe les cotes.
-- Rendu realiste : ambiance sombre (le contraste vient de la), la lune entre en biais et les meubles projettent
-- des ombres douces. Murs et plafond ne bloquent pas la lune (sinon toute la piece serait dans l'ombre).
for _, p in structure:GetDescendants() do
	if p:IsA("BasePart") and p.Name ~= "Sol" then
		p.CastShadow = false
	end
end
-- Minuit, latitude -45 : la lune (direction 0, 0.37, -0.93) est pile dans l'axe de la fenetre vue depuis la chambre,
-- et sa lumiere entre par la fenetre (ombres des meubles projetees vers les bases). Calcule par GetMoonDirection.
Lighting.ClockTime = 0
Lighting.GeographicLatitude = -45
local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
sky.CelestialBodiesShown = true
sky.StarCount = 5000
-- Taille ou la lune tient entiere dans la fenetre, vue du sol comme d'en haut.
sky.MoonAngularSize = 11
sky.Parent = Lighting
Lighting.GlobalShadows = true
Lighting.Brightness = 3
Lighting.Ambient = Color3.fromRGB(62, 66, 92)
Lighting.OutdoorAmbient = Color3.fromRGB(54, 58, 84)
Lighting.ExposureCompensation = 0.7
Lighting.EnvironmentDiffuseScale = 0.5
Lighting.EnvironmentSpecularScale = 0.6
Lighting.ShadowSoftness = 0.3
pcall(function()
	Lighting.Technology = Enum.Technology.Future
end)
local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", Lighting)
-- Piece fermee de 800 studs : une brume legere, sinon elle noie le decor.
atmo.Density = 0.12
-- Offset 1 : la brume colore le ciel vu par la fenetre (degrade bleu nuit) sans voiler l'interieur.
atmo.Offset = 1
atmo.Color = Color3.fromRGB(34, 56, 120)
atmo.Decay = Color3.fromRGB(18, 28, 70)
atmo.Glare = 0
atmo.Haze = 0.6

-- Etalonnage : plus de contraste et de relief, un halo discret autour des lampes.
local grade = Lighting:FindFirstChild("Etalonnage") or Instance.new("ColorCorrectionEffect")
grade.Name = "Etalonnage"
grade.Contrast = 0.18
grade.Saturation = -0.05
grade.Brightness = 0.02
grade.TintColor = Color3.fromRGB(248, 246, 255)
grade.Parent = Lighting
local bloom = Lighting:FindFirstChild("Halo") or Instance.new("BloomEffect")
bloom.Name = "Halo"
bloom.Intensity = 0.35
bloom.Size = 24
bloom.Threshold = 1.6
bloom.Parent = Lighting

-- Les interieurs des bases (pantoufle, boite a mouchoirs) sont construits a y = -900. Par defaut Roblox detruit tout ce
-- qui passe sous -500 (FallenPartsDestroyHeight) : le joueur mourait des la porte et reapparaissait en boucle dans sa
-- base. On descend la limite bien en dessous des interieurs.
workspace.FallenPartsDestroyHeight = -3000
-- Streaming coupe : avec lui, Roblox dechargeait les grands murs, le plafond et les petites sources de lumiere des
-- lampes loin du joueur (murs qui disparaissent, veilleuses eteintes : retour utilisateur). La carte est petite.
workspace.StreamingEnabled = false

-- La Baseplate affleure le sol : sa texture de grille transparait sur le parquet. On la range.
local base = workspace:FindFirstChild("Baseplate")
if base then
	base.Parent = archive
end

-- Pieces verrouillees (Locked) : la chambre a ete decalee deux fois dans l'editeur Studio (sol a 240 studs de haut,
-- joueurs qui tombaient dans le vide en sortant des bases, 15/09) ; verrouillees, elles ne se selectionnent plus
-- ni ne se deplacent par un clic ou un glisser accidentel.
for _, root in { workspace:FindFirstChild("Chambre"), workspace:FindFirstChild("Zones"), workspace:FindFirstChild("Geant") } do
	for _, d in root and root:GetDescendants() or {} do
		if d:IsA("BasePart") then
			d.Locked = true
		end
	end
end
table.insert(out, "chambre ok")
table.insert(out, "decor " .. #decor:GetChildren() .. " | zones " .. #zones:GetChildren())
return table.concat(out, " | ")
