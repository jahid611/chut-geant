--[[
    build-cuisine — la cuisine, 2e piece du jeu, debloquee a la Nuit 3 (KitchenService, DogService, DogController).

    Une cuisine de nuit geante a l'echelle des petits joueurs (joueur ~5 studs, porte de la chambre 290 studs), loin
    de la chambre (ORIGIN). Carrelage qui resonne, murs, fenetre avec la lune, frigo entrouvert qui eclaire, four,
    evier, plan de travail, table et chaises, chaise haute, panier du chien (le gardien, endormi) et sa gamelle.
    Meubles et chien : Creator Store (gratuits, sans marque), ranges dans ServerStorage.KitchenModels, clones ici et
    mis a l'echelle.

    Jeu :
    - points ToySpawn (attribut Rarity : surtout Rare, Epic, Legendary ; le legendaire tout pres du chien) ;
    - ShadowZone (attribut Radius) et HideZone sous la table et la chaise haute ;
    - KitchenZone : le volume de la cuisine (attribut joueur Piece, jauge du chien) ;
    - trous de souris tagues KitchenDoor (Direction "in" dans le mur gauche de la chambre, "out" dans la cuisine,
      attribut Destination).
    L'ancienne cuisine part dans ServerStorage.Archive, sans ses tags. Tout est verrouille (Locked) a la fin.

        node tools/scene-run.mjs tools/scene/build-cuisine.luau
]]

local CS = game:GetService("CollectionService")
local SS = game:GetService("ServerStorage")

local ORIGIN = Vector3.new(0, 0, 3000)
local W, D, H = 900, 700, 360
local WALL_T = 8
local TILE = 50

-- Chambre (build-chambre.luau) : face interieure du mur gauche a x = -400, plinthe de 3 d'epaisseur devant.
local BEDROOM_HOLE = Vector3.new(-397, 0, -150)

local models = SS:FindFirstChild("KitchenModels")
assert(models, "ServerStorage.KitchenModels manquant")

local archive = SS:FindFirstChild("Archive") or Instance.new("Folder")
archive.Name = "Archive"
archive.Parent = SS
local old = workspace:FindFirstChild("Cuisine")
if old then
	for _, d in old:GetDescendants() do
		for _, t in CS:GetTags(d) do
			CS:RemoveTag(d, t)
		end
	end
	old.Name = "Cuisine_archive"
	old.Parent = archive
end

local room = Instance.new("Model")
room.Name = "Cuisine"
room.Parent = workspace

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local function piece(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for key, value in props do
			local target: any = p
			target[key] = value
		end
	end
	p.Parent = parent
	return p
end

local HIDDEN = { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local function marker(parent: Instance, name: string, size: Vector3, cframe: CFrame): Part
	return piece(parent, name, size, cframe, Color3.new(1, 1, 1), nil, HIDDEN)
end

-- Structure ------------------------------------------------------------------------------------------------------
local structure = Instance.new("Model")
structure.Name = "Structure"
structure.Parent = room

local GROUT = Color3.fromRGB(206, 204, 196)
local TILE_A = Color3.fromRGB(238, 233, 220)
local TILE_B = Color3.fromRGB(150, 174, 196)
local WALL = Color3.fromRGB(186, 206, 188)
local WHITE = Color3.fromRGB(242, 242, 236)
local WOOD = Color3.fromRGB(170, 118, 76)

piece(structure, "Sol", Vector3.new(W + WALL_T * 2, 4, D + WALL_T * 2), CFrame.new(at(0, -2, 0)), TILE_A, Enum.Material.SmoothPlastic, { Reflectance = 0.04 })
local tiles = Instance.new("Model")
tiles.Name = "Carrelage"
tiles.Parent = structure
local nx, nz = math.floor(W / TILE), math.floor(D / TILE)
for ix = 0, nx - 1 do
	for iz = 0, nz - 1 do
		local x = -W / 2 + TILE / 2 + ix * TILE
		local z = -D / 2 + TILE / 2 + iz * TILE
		local color = if (ix + iz) % 2 == 0 then TILE_B else TILE_A
		piece(tiles, "Carreau", Vector3.new(TILE - 2, 0.3, TILE - 2), CFrame.new(at(x, 0.15, z)), color, Enum.Material.SmoothPlastic, { CanCollide = false, CanQuery = false, CanTouch = false, Reflectance = 0.06 })
	end
end
-- joints du carrelage : une grille fine sous les carreaux
piece(structure, "Joints", Vector3.new(W, 0.1, D), CFrame.new(at(0, 0.05, 0)), GROUT, nil, { CanCollide = false, CanQuery = false, CanTouch = false })

-- Fenetre dans le mur du fond
local WIN_W, WIN_H, WIN_Y0 = 280, 180, 150
local zBack = -D / 2 - WALL_T / 2
local sideW = (W - WIN_W) / 2 + WALL_T
piece(structure, "MurFond", Vector3.new(sideW, H, WALL_T), CFrame.new(at(-(WIN_W / 2 + sideW / 2), H / 2, zBack)), WALL)
piece(structure, "MurFond", Vector3.new(sideW, H, WALL_T), CFrame.new(at(WIN_W / 2 + sideW / 2, H / 2, zBack)), WALL)
piece(structure, "MurFond", Vector3.new(WIN_W, WIN_Y0, WALL_T), CFrame.new(at(0, WIN_Y0 / 2, zBack)), WALL)
local winTop = WIN_Y0 + WIN_H
piece(structure, "MurFond", Vector3.new(WIN_W, H - winTop, WALL_T), CFrame.new(at(0, (H + winTop) / 2, zBack)), WALL)
piece(structure, "MurFace", Vector3.new(W + WALL_T * 2, H, WALL_T), CFrame.new(at(0, H / 2, D / 2 + WALL_T / 2)), WALL)
piece(structure, "MurGauche", Vector3.new(WALL_T, H, D), CFrame.new(at(-W / 2 - WALL_T / 2, H / 2, 0)), WALL)
piece(structure, "MurDroit", Vector3.new(WALL_T, H, D), CFrame.new(at(W / 2 + WALL_T / 2, H / 2, 0)), WALL)
piece(structure, "Plafond", Vector3.new(W + WALL_T * 2, 8, D + WALL_T * 2), CFrame.new(at(0, H + 4, 0)), Color3.fromRGB(214, 220, 214))
for _, spec in { { "PlintheFond", Vector3.new(W, 14, 3), Vector3.new(0, 7, -D / 2 + 1.5) }, { "PlintheFace", Vector3.new(W, 14, 3), Vector3.new(0, 7, D / 2 - 1.5) }, { "PlintheGauche", Vector3.new(3, 14, D), Vector3.new(-W / 2 + 1.5, 7, 0) }, { "PlintheDroite", Vector3.new(3, 14, D), Vector3.new(W / 2 - 1.5, 7, 0) } } do
	piece(structure, spec[1], spec[2], CFrame.new(at(spec[3].X, spec[3].Y, spec[3].Z)), WHITE)
end
-- Credence carrelee blanche au-dessus du plan de travail
piece(structure, "Credence", Vector3.new(W, 20, 1), CFrame.new(at(0, 140, -D / 2 + 0.5)), WHITE, nil, { CanCollide = false })

-- Cadre, croisillons et vitre
local frameColor = WHITE
local zWin = -D / 2 - WALL_T / 2
piece(structure, "CadreFenetre", Vector3.new(WIN_W + 20, 12, WALL_T + 6), CFrame.new(at(0, WIN_Y0 - 2, zWin)), frameColor)
piece(structure, "CadreFenetre", Vector3.new(WIN_W + 20, 10, WALL_T + 2), CFrame.new(at(0, winTop + 5, zWin)), frameColor)
for _, sx in { -1, 1 } do
	piece(structure, "CadreFenetre", Vector3.new(10, WIN_H + 20, WALL_T + 2), CFrame.new(at(sx * (WIN_W / 2 + 5), WIN_Y0 + WIN_H / 2, zWin)), frameColor)
end
piece(structure, "Croisillon", Vector3.new(6, WIN_H, 4), CFrame.new(at(0, WIN_Y0 + WIN_H / 2, zWin)), frameColor)
piece(structure, "Croisillon", Vector3.new(WIN_W, 6, 4), CFrame.new(at(0, WIN_Y0 + WIN_H / 2, zWin)), frameColor)
piece(structure, "Vitre", Vector3.new(WIN_W, WIN_H, 1), CFrame.new(at(0, WIN_Y0 + WIN_H / 2, zWin - 3)), Color3.fromRGB(170, 190, 230), Enum.Material.Glass, { Transparency = 0.8, CastShadow = false })

-- Ciel de nuit et lune derriere la fenetre
local sky = Instance.new("Model")
sky.Name = "CielNuit"
sky.Parent = room
local zSky = -D / 2 - 420
piece(sky, "Fond", Vector3.new(1600, 1000, 4), CFrame.new(at(0, 300, zSky)), Color3.fromRGB(16, 22, 58), nil, { CastShadow = false, CanCollide = false, CanQuery = false })
piece(sky, "Lune", Vector3.new(110, 110, 110), CFrame.new(at(60, 250, zSky + 60)), Color3.fromRGB(250, 244, 214), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CastShadow = false, CanCollide = false, CanQuery = false })
local starRandom = Random.new(3000)
for i = 1, 28 do
	local size = starRandom:NextNumber(3, 7)
	piece(sky, "Etoile" .. i, Vector3.new(size, size, size), CFrame.new(at(starRandom:NextNumber(-520, 520), starRandom:NextNumber(160, 620), zSky + 8)), Color3.fromRGB(235, 240, 255), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CastShadow = false, CanCollide = false, CanQuery = false })
end

-- Rai de lune sur le carrelage et lumiere froide qui tombe de la fenetre
piece(room, "RaiDeLune", Vector3.new(230, 0.1, 300), CFrame.new(at(20, 0.35, -150)) * CFrame.Angles(0, math.rad(8), 0), Color3.fromRGB(150, 170, 255), Enum.Material.Neon, { Transparency = 0.84, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
-- Le projecteur de la fenetre (portee 60) n'atteint pas le sol : deux lueurs froides posees dans le rai de lune
for i, pos in { Vector3.new(0, 40, -230), Vector3.new(40, 40, -100) } do
	local moonFloor = marker(room, "LueurLune" .. i, Vector3.new(1, 1, 1), CFrame.new(at(pos.X, pos.Y, pos.Z)))
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(160, 180, 255)
	l.Brightness = 1.4
	l.Range = 60
	l.Parent = moonFloor
end
local moonLight = marker(room, "LumiereLune", Vector3.new(1, 1, 1), CFrame.lookAt(at(0, WIN_Y0 + WIN_H - 10, -D / 2 + 6), at(0, 0, -D / 2 + 200)))
local moonSpot = Instance.new("SpotLight")
moonSpot.Color = Color3.fromRGB(150, 170, 255)
moonSpot.Brightness = 3
moonSpot.Range = 60
moonSpot.Angle = 80
moonSpot.Face = Enum.NormalId.Front
moonSpot.Parent = moonLight

-- Meubles ------------------------------------------------------------------------------------------------------
local furniture = Instance.new("Model")
furniture.Name = "Meubles"
furniture.Parent = room

local function worldBox(m: Model): (CFrame, Vector3)
	m.WorldPivot = CFrame.new(m:GetPivot().Position)
	return m:GetBoundingBox()
end

type PlaceOptions = { yaw: number?, height: number?, span: number?, x: number, z: number, y: number?, back: boolean? }

-- Clone un modele de KitchenModels, le tourne (yaw en degres), le met a l'echelle (hauteur `height`, ou plus grande
-- dimension au sol `span`) et pose le bas de son volume a `y` (sol par defaut), centre en x / z ; `back` colle
-- son dos au mur du fond.
local report = {}
local function place(name: string, newName: string, parent: Instance, opts: PlaceOptions): Model
	local source = models:FindFirstChild(name)
	assert(source, "modele manquant : " .. name)
	local m = source:Clone()
	m.Name = newName
	m.PrimaryPart = nil
	m.Parent = parent
	worldBox(m)
	m:PivotTo(m:GetPivot() * CFrame.Angles(0, math.rad(opts.yaw or 0), 0))
	local _, size = worldBox(m)
	local k = if opts.height then opts.height / size.Y else (opts.span :: number) / math.max(size.X, size.Z)
	m:ScaleTo(m:GetScale() * k)
	local box, scaled = worldBox(m)
	local z = if opts.back then -D / 2 + scaled.Z / 2 + 3 else opts.z
	local target = at(opts.x, (opts.y or 0) + scaled.Y / 2, z)
	m:PivotTo(m:GetPivot() + (target - box.Position))
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	table.insert(report, string.format("%s %.0fx%.0fx%.0f", newName, scaled.X, scaled.Y, scaled.Z))
	return m
end

local fridge = place("Fridge", "Frigo", furniture, { yaw = -90, height = 270, x = -345, z = 0, back = true })
local stove = place("Stove", "Four", furniture, { yaw = 180, height = 130, x = -150, z = 0, back = true })
local sink = place("CounterSink", "Evier", furniture, { yaw = 0, height = 130, x = 20, z = 0, back = true })

-- Plan de travail qui prolonge l'evier jusqu'au mur droit (meuble blanc, dessus en bois, poignees)
local _, sinkSize = sink:GetBoundingBox()
local sinkRight = sink:GetPivot().Position.X - ORIGIN.X + sinkSize.X / 2
local counterLeft, counterRight = sinkRight + 1, W / 2 - 2
local counterW = counterRight - counterLeft
local counterDepth = math.max(sinkSize.Z, 120)
local counterX = (counterLeft + counterRight) / 2
local counterZ = -D / 2 + counterDepth / 2 + 3
local counter = Instance.new("Model")
counter.Name = "PlanDeTravail"
counter.Parent = furniture
piece(counter, "Meuble", Vector3.new(counterW, 120, counterDepth - 6), CFrame.new(at(counterX, 60, counterZ - 3)), WHITE)
piece(counter, "Dessus", Vector3.new(counterW, 10, counterDepth + 4), CFrame.new(at(counterX, 125, counterZ)), WOOD, Enum.Material.Wood)
local doors = math.max(math.floor(counterW / 110), 1)
for i = 1, doors do
	local cx = counterLeft + (i - 0.5) * counterW / doors
	piece(counter, "Porte", Vector3.new(counterW / doors - 8, 100, 1.5), CFrame.new(at(cx, 58, counterZ + counterDepth / 2 - 5)), Color3.fromRGB(232, 234, 228))
	piece(counter, "Poignee", Vector3.new(24, 4, 3), CFrame.new(at(cx, 96, counterZ + counterDepth / 2 - 3)), Color3.fromRGB(90, 96, 110), Enum.Material.Metal)
end

place("TableChairs", "TableChaises", furniture, { yaw = 0, height = 150, x = 170, z = 70 })
place("HighChair", "ChaiseHaute", furniture, { yaw = 0, height = 170, x = 360, z = 230 })

-- Coin du chien : panier rond (Creator Store, coussin en boudin), chien endormi, gamelles, os a machouiller
local bed = place("DogBedRound", "Panier", room, { yaw = 0, span = 200, x = -130, z = 200 })
-- Boudin rouge chaud, fond creme : les couleurs sable d'origine sortaient grises la nuit
for _, d in bed:GetDescendants() do
	if d:IsA("BasePart") then
		d.Material = Enum.Material.Fabric
		local dark = d.Color.R < 0.6
		d.Color = if dark then Color3.fromRGB(196, 78, 66) else Color3.fromRGB(242, 222, 188)
		if d:IsA("UnionOperation") then
			d.UsePartColor = true
		end
	end
end
local bedBox, bedSize = bed:GetBoundingBox()
-- Le modele source a la tete vers -X (capture de dessus, docs/captures/k2-chien-dessus.png) : demi-tour pour qu'il
-- regarde la piece (+X, vers la table et le jouet legendaire) plutot que le mur.
-- Couche sur le coussin et plus grand que le trou du panier : vu du sol (joueurs de 5 studs), le boudin de 45 studs
-- cachait sa tete (capture k2-chien-face).
local dog = place("FamilyDog", "Chien", room, { yaw = 180, span = 175, x = -115, z = 200, y = bedBox.Position.Y - ORIGIN.Y - bedSize.Y / 2 + bedSize.Y * 0.38 })
-- Pivot du chien : au pied de son volume, regard (LookVector) vers sa tete (DogService anime autour de ce pivot).
local DOG_FACE = Vector3.new(1, 0, 0)
local dogBox, dogSize = dog:GetBoundingBox()
local dogFeet = dogBox.Position - Vector3.new(0, dogSize.Y / 2, 0)
dog.WorldPivot = CFrame.lookAt(dogFeet, dogFeet + DOG_FACE)
dog:SetAttribute("State", "Sleeping")
-- Veilleuse chaude au-dessus du panier : le gardien doit se lire de loin. Une PointLight porte a 60 studs au plus :
-- l'ancienne, 80 studs au-dessus avec une portee de 55, n'eclairait jamais le chien.
local dogLamp = marker(room, "VeilleuseChien", Vector3.new(1, 1, 1), CFrame.new(dogBox.Position + Vector3.new(dogSize.X * 0.45, 40, 0)))
local dogGlow = Instance.new("PointLight")
dogGlow.Color = Color3.fromRGB(255, 190, 120)
dogGlow.Brightness = 2.4
dogGlow.Range = 60
dogGlow.Shadows = true
dogGlow.Parent = dogLamp
-- Halo chaud au sol autour du panier
piece(room, "HaloVeilleuse", Vector3.new(0.1, 250, 250), CFrame.new(Vector3.new(bedBox.Position.X, ORIGIN.Y + 0.4, bedBox.Position.Z)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 186, 110), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, Transparency = 0.9, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
place("PetBowls", "Gamelle", room, { yaw = 90, span = 64, x = 0, z = 285 })
-- Les gamelles bleues sortaient noires : petite lueur chaude a cote
local bowlLamp = marker(room, "LueurGamelle", Vector3.new(1, 1, 1), CFrame.new(at(-5, 30, 260)))
local bowlLight = Instance.new("PointLight")
bowlLight.Color = Color3.fromRGB(255, 214, 170)
bowlLight.Brightness = 1.3
bowlLight.Range = 45
bowlLight.Parent = bowlLamp
place("Bone", "OsAMachouiller", room, { yaw = 35, span = 34, x = 15, z = 245 })

-- Lumiere du frigo entrouvert : froide, qui coule sur le carrelage
local fridgeBox, fridgeSize = fridge:GetBoundingBox()
local fridgeFront = fridgeBox.Position + Vector3.new(0, 0, fridgeSize.Z / 2)
local fridgeLight = marker(room, "LumiereFrigo", Vector3.new(1, 1, 1), CFrame.lookAt(fridgeFront + Vector3.new(0, -fridgeSize.Y * 0.1, 6), fridgeFront + Vector3.new(40, -fridgeSize.Y / 2, 200)))
local fridgeSpot = Instance.new("SpotLight")
fridgeSpot.Color = Color3.fromRGB(214, 236, 255)
fridgeSpot.Brightness = 5
fridgeSpot.Range = 60
fridgeSpot.Angle = 90
fridgeSpot.Face = Enum.NormalId.Front
fridgeSpot.Parent = fridgeLight
local fridgeGlow = Instance.new("PointLight")
fridgeGlow.Color = Color3.fromRGB(214, 236, 255)
fridgeGlow.Brightness = 2
fridgeGlow.Range = 60
fridgeGlow.Parent = fridgeLight
piece(room, "RaiFrigo", Vector3.new(110, 0.1, 170), CFrame.new(Vector3.new(fridgeFront.X + 30, ORIGIN.Y + 0.4, fridgeFront.Z + 85)) * CFrame.Angles(0, math.rad(-12), 0), Color3.fromRGB(220, 240, 255), Enum.Material.Neon, { Transparency = 0.8, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
-- Reflet froid du frigo sur le carrelage : une seconde lumiere pres du sol, la premiere est a mi-hauteur du frigo
local fridgeFloor = marker(room, "RefletFrigo", Vector3.new(1, 1, 1), CFrame.new(Vector3.new(fridgeFront.X + 30, ORIGIN.Y + 25, fridgeFront.Z + 70)))
local fridgeFloorLight = Instance.new("PointLight")
fridgeFloorLight.Color = Color3.fromRGB(200, 228, 255)
fridgeFloorLight.Brightness = 1.6
fridgeFloorLight.Range = 60
fridgeFloorLight.Parent = fridgeFloor

-- Veilleuse du four (petite lumiere verte d'horloge) et lueur douce au plafond pour lire la piece
local stoveBox, stoveSize = stove:GetBoundingBox()
local clock = piece(room, "HorlogeFour", Vector3.new(26, 9, 1), CFrame.lookAt(stoveBox.Position + Vector3.new(0, stoveSize.Y * 0.32, stoveSize.Z / 2 + 0.6), stoveBox.Position + Vector3.new(0, stoveSize.Y * 0.32, stoveSize.Z)), Color3.fromRGB(20, 26, 30), nil, { CanCollide = false, CastShadow = false })
local clockGui = Instance.new("SurfaceGui")
clockGui.Face = Enum.NormalId.Front
clockGui.LightInfluence = 0
clockGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
clockGui.PixelsPerStud = 20
clockGui.Parent = clock
local clockText = Instance.new("TextLabel")
clockText.BackgroundTransparency = 1
clockText.Size = UDim2.fromScale(1, 1)
clockText.Font = Enum.Font.Code
clockText.Text = "02:14"
clockText.TextScaled = true
clockText.TextColor3 = Color3.fromRGB(90, 255, 140)
clockText.Parent = clockGui
local clockLight = Instance.new("PointLight")
clockLight.Color = Color3.fromRGB(90, 255, 140)
clockLight.Brightness = 1
clockLight.Range = 22
clockLight.Parent = clock
-- Lueurs de nuit a hauteur de joueur (au plafond, a 330 studs, elles n'eclairaient que le plafond)
for i, pos in { Vector3.new(-280, 70, -120), Vector3.new(170, 70, 70), Vector3.new(330, 70, -200), Vector3.new(-300, 70, 220), Vector3.new(300, 70, 280), Vector3.new(-60, 70, -20) } do
	local glow = marker(room, "LueurNuit" .. i, Vector3.new(1, 1, 1), CFrame.new(at(pos.X, pos.Y, pos.Z)))
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(140, 150, 210)
	l.Brightness = 0.9
	l.Range = 60
	l.Parent = glow
end

-- Petit decor du plan de travail (Creator Store) : bocal a biscuits. (Le rouleau d'essuie-tout, ServerStorage
-- .KitchenModels.KitchenRoll, sortait penche et flottant : pas pose.)
place("CookieJar", "BocalBiscuits", furniture, { yaw = 0, height = 42, x = counterX - 70, z = counterZ, y = 130 })
local counterLamp = marker(room, "LueurPlanDeTravail", Vector3.new(1, 1, 1), CFrame.new(at(counterX, 175, counterZ + 40)))
local counterLight = Instance.new("PointLight")
counterLight.Color = Color3.fromRGB(255, 214, 170)
counterLight.Brightness = 1
counterLight.Range = 55
counterLight.Parent = counterLamp

-- Zones de jeu ---------------------------------------------------------------------------------------------------
local gameplay = Instance.new("Folder")
gameplay.Name = "Jeu"
gameplay.Parent = room

local zone = marker(gameplay, "ZoneCuisine", Vector3.new(W, H, D), CFrame.new(at(0, H / 2, 0)))
CS:AddTag(zone, "KitchenZone")

-- Jouets : surtout rares ; le legendaire juste devant le panier du chien
local SPAWNS = {
	{ "Legendary", -30, 120 },
	{ "Epic", 170, 70 },
	{ "Epic", 330, 170 },
	{ "Epic", -150, -200 },
	{ "Rare", -300, -150 },
	{ "Rare", 30, -225 },
	{ "Rare", 380, -230 },
	{ "Rare", -380, 110 },
	{ "Rare", 60, 290 },
	{ "Rare", 400, 300 },
	{ "Uncommon", -260, 300 },
}
for i, spec in SPAWNS do
	local p = marker(gameplay, "SpawnCuisine" .. i, Vector3.new(6, 1, 6), CFrame.new(at(spec[2], 1, spec[3])))
	p:SetAttribute("Rarity", spec[1])
	CS:AddTag(p, "ToySpawn")
end

for i, spec in { { 170, 70, 85 }, { -415, -60, 45 }, { 360, 230, 50 } } do
	local disc = marker(gameplay, "OmbreCuisine" .. i, Vector3.new(spec[3] * 2, 2, spec[3] * 2), CFrame.new(at(spec[1], 1, spec[2])))
	disc:SetAttribute("Radius", spec[3])
	CS:AddTag(disc, "ShadowZone")
end
for i, spec in { { 170, 70, Vector3.new(150, 70, 120) }, { 360, 230, Vector3.new(70, 60, 70) } } do
	local hide = marker(gameplay, "CachetteCuisine" .. i, spec[3], CFrame.new(at(spec[1], spec[3].Y / 2, spec[2])))
	CS:AddTag(hide, "HideZone")
end

-- Trous de souris --------------------------------------------------------------------------------------------------
local function mouseHole(parent: Instance, name: string, base: Vector3, inward: Vector3, direction: string, destination: CFrame, label: string): ()
	local holder = Instance.new("Model")
	holder.Name = name
	holder.Parent = parent
	local face = CFrame.lookAt(base, base + inward)
	local disc = CFrame.Angles(0, math.rad(90), 0)
	local noClip = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	piece(holder, "Bord", Vector3.new(0.6, 36, 36), (face + Vector3.new(0, 9, 0) + inward * 0.3) * disc, WOOD, Enum.Material.Wood, noClip)
	piece(holder, "Trou", Vector3.new(0.6, 29, 29), (face + Vector3.new(0, 9, 0) + inward * 0.8) * disc, Color3.fromRGB(16, 12, 18), nil, noClip).Shape = Enum.PartType.Cylinder
	for _, child in holder:GetChildren() do
		if child:IsA("Part") then
			child.Shape = Enum.PartType.Cylinder
		end
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 196, 130)
	glow.Brightness = 1.2
	glow.Range = 18
	glow.Parent = holder:FindFirstChild("Trou")
	local sign = piece(holder, "Panneau", Vector3.new(22, 8, 1), face + Vector3.new(0, 32, 0) + inward * 0.6, WOOD, Enum.Material.Wood, noClip)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.Parent = sign
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.Text = label
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 244, 220)
	text.Parent = gui
	local trigger = marker(holder, "Passage", Vector3.new(14, 26, 26), CFrame.new(base + inward * 5 + Vector3.new(0, 13, 0)))
	trigger:SetAttribute("Direction", direction)
	trigger:SetAttribute("Destination", destination)
	CS:AddTag(trigger, "KitchenDoor")
end

mouseHole(room, "TrouChambre", BEDROOM_HOLE, Vector3.new(1, 0, 0), "in", CFrame.lookAt(at(-418, 5, 250), at(0, 5, 250)), "CUISINE")
mouseHole(room, "TrouCuisine", at(-W / 2 + 3, 0, 250), Vector3.new(1, 0, 0), "out", CFrame.lookAt(Vector3.new(-372, 5, -150), Vector3.new(0, 5, -150)), "CHAMBRE")

local count = 0
for _, d in room:GetDescendants() do
	if d:IsA("BasePart") then
		d.Locked = true
		count += 1
	end
end
return string.format("Cuisine : %d pieces | %s", count, table.concat(report, " | "))
