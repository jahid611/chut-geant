--[[
    _prelude — les briques communes aux recettes de scene.

    Colle en tete de chaque recette par tools/scene-run.mjs. Tout ce qui est
    defini ici est disponible dans la recette sans rien declarer. La palette
    est celle de docs/CHARTE.md : arenes claires, un seul accent lumineux, du
    SmoothPlastic partout — la matiere vient de la lumiere et de la couleur.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Workspace = game:GetService("Workspace")

-- L'accent : Photon. "FF7A1A" pour la direction B, "A855F7" pour la A.
local ACCENT = Color3.fromHex("2DD4FF")
local FLOOR = Color3.fromHex("E4E7EE")
local FLOOR_ALT = Color3.fromHex("DADEE7")
local WALL = Color3.fromHex("C9CED9")
local PANEL = Color3.fromHex("D8DCE5")
local BLOCK = Color3.fromHex("BFC5D2")
local BLOCK_DARK = Color3.fromHex("9AA3B8")
local DARK = Color3.fromHex("1A2142")
local VOID = Color3.fromHex("0B0F1F")
local WHITE = Color3.fromHex("F4F6FF")
local TARGET = Color3.fromHex("F03A3A")

local function part(
    name: string,
    size: Vector3,
    cframe: CFrame,
    color: Color3,
    parent: Instance,
    material: Enum.Material?
): Part
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.CFrame = cframe
    p.Color = color
    p.Material = material or Enum.Material.SmoothPlastic
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Parent = parent
    return p
end

local function neon(name: string, size: Vector3, cframe: CFrame, parent: Instance, color: Color3?): Part
    local p = part(name, size, cframe, color or ACCENT, parent, Enum.Material.Neon)
    p.CanCollide = false
    p.CastShadow = false
    return p
end

--[[ Une zone invisible et traversable : spawn, file, declencheur. ]]
local function zone(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
    local p = part(name, size, cframe, ACCENT, parent)
    p.Transparency = 1
    p.CanCollide = false
    p.CanQuery = false
    return p
end

local function light(parent: BasePart, range: number, brightness: number, color: Color3?): PointLight
    local l = Instance.new("PointLight")
    l.Color = color or ACCENT
    l.Range = range
    l.Brightness = brightness
    l.Shadows = false
    l.Parent = parent
    return l
end

--[[ Une enseigne : un bloc sombre avec un mot en gros. ]]
local function sign(
    text: string,
    size: Vector3,
    cframe: CFrame,
    parent: Instance,
    textColor: Color3?,
    face: Enum.NormalId?
): Part
    local p = part("Sign_" .. text, size, cframe, DARK, parent)
    local gui = Instance.new("SurfaceGui")
    gui.Face = face or Enum.NormalId.Front
    gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.PixelsPerStud = 40
    gui.LightInfluence = 0
    gui.Parent = p
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBlack
    label.Text = text
    label.TextColor3 = textColor or WHITE
    label.TextScaled = true
    label.Parent = gui
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0.08, 0)
    pad.PaddingRight = UDim.new(0.08, 0)
    pad.PaddingTop = UDim.new(0.15, 0)
    pad.PaddingBottom = UDim.new(0.15, 0)
    pad.Parent = label
    return p
end

--[[
    Une arene fermee : sol, damier discret, quatre murs, bandeaux neon au pied
    et au sommet, couvercle invisible. Rend le dossier Structure. Les murs
    sont assez hauts pour qu'aucun saut ne les passe ; le couvercle finit le
    travail. L'exterieur n'existe pas.
]]
local function enclosure(parent: Instance, center: Vector3, width: number, depth: number, height: number): Model
    local structure = Instance.new("Model")
    structure.Name = "Structure"
    structure.Parent = parent
    local function at(x: number, y: number, z: number): CFrame
        return CFrame.new(center + Vector3.new(x, y, z))
    end
    part("Floor", Vector3.new(width, 2, depth), at(0, -1, 0), FLOOR, structure)
    local tile = 16
    local nx, nz = math.floor(width / tile), math.floor(depth / tile)
    for ix = 0, nx - 1 do
        for iz = 0, nz - 1 do
            if (ix + iz) % 2 == 0 then
                local x = -width / 2 + tile / 2 + ix * tile + (width - nx * tile) / 2
                local z = -depth / 2 + tile / 2 + iz * tile + (depth - nz * tile) / 2
                local t = part("Tile", Vector3.new(tile - 0.4, 0.1, tile - 0.4), at(x, 0.05, z), FLOOR_ALT, structure)
                t.CanCollide = false
            end
        end
    end
    local t = 2
    local h = height / 2
    part("WallNorth", Vector3.new(width + t * 2, height, t), at(0, h, -depth / 2 - t / 2), WALL, structure)
    part("WallSouth", Vector3.new(width + t * 2, height, t), at(0, h, depth / 2 + t / 2), WALL, structure)
    part("WallWest", Vector3.new(t, height, depth), at(-width / 2 - t / 2, h, 0), WALL, structure)
    part("WallEast", Vector3.new(t, height, depth), at(width / 2 + t / 2, h, 0), WALL, structure)
    for _, y in { 0.3, height + 0.25 } do
        neon("Strip", Vector3.new(width, 0.5, 0.5), at(0, y, -depth / 2 + 0.25), structure)
        neon("Strip", Vector3.new(width, 0.5, 0.5), at(0, y, depth / 2 - 0.25), structure)
        neon("Strip", Vector3.new(0.5, 0.5, depth), at(-width / 2 + 0.25, y, 0), structure)
        neon("Strip", Vector3.new(0.5, 0.5, depth), at(width / 2 - 0.25, y, 0), structure)
    end
    local lid = part("Lid", Vector3.new(width + 4, 1, depth + 4), at(0, height + 1, 0), WALL, structure)
    lid.Transparency = 1
    return structure
end

--[[
    Un bloc de couverture, pose au sol. `y` vaut la hauteur du bloc : il repose
    sur le sol et non a mi-hauteur, ce qui evite de recalculer a chaque fois.
]]
local function block(name: string, parent: Instance, center: Vector3, x: number, z: number, sx: number, sy: number, sz: number, color: Color3?): Part
    return part(name, Vector3.new(sx, sy, sz), CFrame.new(center + Vector3.new(x, sy / 2, z)), color or BLOCK, parent)
end

--[[
    Une rampe : un bloc incline, du sol vers `sy` de haut, oriente par `yaw`.

    Convention, mesuree dans Studio : la face verticale d'un WedgePart est sa
    face arriere, donc il MONTE VERS SON +Z LOCAL. Avec yaw 0 le haut est vers
    +Z (le sud), avec yaw 180 vers -Z (le nord), avec yaw 90 vers +X (l'est),
    avec -90 vers -X (l'ouest). Pour qu'une rampe monte vers une dalle, son
    haut doit pointer vers la dalle.
]]
local function ramp(name: string, parent: Instance, center: Vector3, x: number, z: number, length: number, width: number, sy: number, yaw: number): WedgePart
    local w = Instance.new("WedgePart")
    w.Name = name
    w.Size = Vector3.new(width, sy, length)
    w.CFrame = CFrame.new(center + Vector3.new(x, sy / 2, z)) * CFrame.Angles(0, math.rad(yaw), 0)
    w.Color = BLOCK
    w.Material = Enum.Material.SmoothPlastic
    w.Anchored = true
    w.TopSurface = Enum.SurfaceType.Smooth
    w.BottomSurface = Enum.SurfaceType.Smooth
    w.Parent = parent
    return w
end

--[[
    Le contrat d'une carte pour MatchService : Spawns.A, Spawns.B, Lobby.Spawn,
    et les attributs d'eclairage. `a` et `b` sont des positions relatives au
    centre ; `look` dit vers ou chaque duelliste regarde en apparaissant.
]]
local function mapContract(map: Model, center: Vector3, a: Vector3, b: Vector3, displayName: string): ()
    local spawns = Instance.new("Folder")
    spawns.Name = "Spawns"
    spawns.Parent = map
    local sa = zone("A", Vector3.new(6, 1, 6), CFrame.lookAt(center + a, center + b), spawns)
    local sb = zone("B", Vector3.new(6, 1, 6), CFrame.lookAt(center + b, center + a), spawns)
    neon("PadA", Vector3.new(6, 0.2, 6), CFrame.new(center + a - Vector3.new(0, 0.4, 0)), map, WHITE)
    neon("PadB", Vector3.new(6, 0.2, 6), CFrame.new(center + b - Vector3.new(0, 0.4, 0)), map, WHITE)
    sa.CanCollide = false
    sb.CanCollide = false
    local lobby = Instance.new("Folder")
    lobby.Name = "Lobby"
    lobby.Parent = map
    zone("Spawn", Vector3.new(6, 1, 6), CFrame.new(center + Vector3.new(0, 40, 0)), lobby)
    map:SetAttribute("DisplayName", displayName)
    map:SetAttribute("ClockTime", 14)
    map:SetAttribute("Brightness", 1.7)
    map:SetAttribute("Ambient", Color3.fromRGB(165, 170, 190))
    map:SetAttribute("OutdoorAmbient", Color3.fromRGB(150, 158, 185))
    map:SetAttribute("AtmosphereDensity", 0.15)
    map:SetAttribute("AtmosphereHaze", 0)
end

--[[ Remplace une carte du meme nom dans Workspace.Maps et rend le modele neuf. ]]
local function freshMap(name: string): Model
    local maps = Workspace:FindFirstChild("Maps") or Instance.new("Folder")
    maps.Name = "Maps"
    maps.Parent = Workspace
    local old = maps:FindFirstChild(name)
    if old then
        old:Destroy()
    end
    local map = Instance.new("Model")
    map.Name = name
    map.Parent = maps
    return map
end

local function countOf(inst: Instance): number
    local n = 0
    for _ in inst:GetDescendants() do
        n += 1
    end
    return n
end
