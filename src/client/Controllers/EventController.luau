--!strict

--[[
    EventController
    Tout ce que le joueur voit et entend des mini-jeux et de l'etat du bebe, d'apres les maquettes
    (docs/mockups/higgsfield/evenements/) :
    - bandeaux « MAMAN ARRIVE ! », « VITE, DANS L'OMBRE ! », « Hmm ?.. », « JOUET PIÉGÉ ! » avec compte a rebours ;
    - zones d'ombre au sol pendant « Vite, dans l'ombre ! » : tache d'ombre douce, anneau argente qui pulse et
      poussiere d'etoiles, plus lumineuses pendant « IL REGARDE ! » ;
    - sons : pas dans l'escalier, porte qui grince, bebe qui pleure (volume baisse), « Chuuut » quand la jauge
      approche du reveil, bips et explosion du jouet piege ;
    - propulsion du joueur attrape (remote Caught), au lieu d'une teleportation ;
    - pastilles des bonus achetes (chaussons, bras) sous le compteur de tetines.
    - nouveaux evenements (nuit du 15-16/09) : orage (grondement, eclair, zones d'ombre), boite a musique (berceuse,
      notes), pluie de jouets (eternuement, pops), cauchemar (vignette rouge, gemissements), jouet dore geant
      (faisceau lumineux, gagnant), panne de veilleuse (lampes eteintes, lampe torche), papa qui ronfle (ZZZ geants),
      chat de la maison (miaulements). Bandeaux avec icone.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Tuning"))

local Screamer = require(script.Parent.Parent.Ui.Screamer)
local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

-- Sons : les deux premiers choisis par l'utilisateur, les autres crees par Roblox (Pro Sound Effects).
local SOUNDS = {
    -- boucles des nouveaux evenements (createurs verifies, gratuits) :
    -- « Music Box Lullaby (30s) » (APMOfficial) : boite a musique
    lullaby = { id = "rbxassetid://9047796475", volume = 0.35 },
    -- « Man Snoring » (BuddyGamour21) : papa ronfle
    snore = { id = "rbxassetid://9089200372", volume = 0.35 },
    -- « Baby Cry Uncomfortable Gurgles Whimpering 1 (SFX) » (ProSoundEffects) : cauchemar
    whimper = { id = "rbxassetid://9113235220", volume = 0.14 },
    -- Pleur choisi par l'utilisateur le 15/09/2026 (« Baby Crying Upset 6 Months Old 2 », Pro Sound Effects),
    -- « pas fort » : l'ancien cri (138470978418134) cassait les oreilles meme a 0,18.
    cry = { id = "rbxassetid://9113234666", volume = 0.12 },
    shh = { id = "rbxassetid://108800532919321", volume = 0.7 },
    stairs = { id = "rbxassetid://9113134898", volume = 1 },
    creak = { id = "rbxassetid://9120839010", volume = 1 },
    beep = { id = "rbxassetid://15675055424", volume = 0.6 },
    boom = { id = "rbxassetid://3149249837", volume = 0.5 },
}
local SHH_COOLDOWN = 8
local SHADOW_TAG = "ShadowZone"

local EventController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local sounds: { [string]: Sound } = {}
local banner: Frame? = nil
local bannerToken = 0

local function sound(name: string): Sound
    local existing = sounds[name]
    if existing then
        return existing
    end
    local def = (SOUNDS :: any)[name]
    local s = Instance.new("Sound")
    s.Name = "Son_" .. name
    s.SoundId = def.id
    s.Volume = def.volume
    s.Parent = SoundService
    sounds[name] = s
    return s
end

local function play(name: string): ()
    local s = sound(name)
    s.TimePosition = 0
    s:Play()
end

local function stop(name: string): ()
    local s = sounds[name]
    if s then
        s:Stop()
    end
end

local function clearBanner(): ()
    bannerToken += 1
    if banner then
        banner:Destroy()
        banner = nil
    end
end

-- Bandeau en haut au centre : titre, sous-titre, et compte a rebours jusqu'a endsAt (0 = pas de compteur). icon : cle
-- d'Assets posee a gauche du titre.
local function showBanner(title: string, subtitle: string, color: Color3, endsAt: number, icon: string?): ()
    clearBanner()
    -- dans la cuisine, les evenements du bebe ne concernent pas le joueur et recouvraient l'interface du chien
    if player:GetAttribute("Piece") == "Cuisine" then
        return
    end
    local token = bannerToken
    local holder = Instance.new("Frame")
    holder.Name = "BandeauEvenement"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(700, 200)
    -- sous la jauge « CHUT » (le bandeau la recouvrait)
    holder.Position = UDim2.new(0.5, 0, 0, 118)
    holder.AnchorPoint = Vector2.new(0.5, 0)
    holder.Parent = gui
    local scale = Theme.fit(holder, 0.8)
    local target = scale.Scale
    scale.Scale = target * 0.6
    TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = target }):Play()
    banner = holder

    -- Texte flottant, sans carte (retour utilisateur) : titre, sous-titre et compteur avec un contour epais.
    local function thick(label: TextLabel, thickness: number): ()
        local stroke = label:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Thickness = thickness
        end
    end
    local titleLabel =
        Theme.text(holder, "Titre", title, UDim2.new(1, 0, 0, 68), UDim2.fromScale(0.5, 0), color, Vector2.new(0.5, 0))
    thick(titleLabel, 4)
    if icon then
        -- titre en TextScaled sur 68 de haut : sa largeur suit a peu pres le nombre de lettres
        local width = math.min((utf8.len(title) or #title) * 38, 640)
        Theme.image(
            holder,
            "Icone",
            icon,
            UDim2.fromOffset(62, 62),
            UDim2.new(0.5, -width / 2 - 8, 0, 3),
            Vector2.new(1, 0)
        )
    end
    local subtitleLabel = Theme.text(
        holder,
        "SousTitre",
        subtitle,
        UDim2.new(0.85, 0, 0, 32),
        UDim2.new(0.5, 0, 0, 70),
        Theme.WHITE,
        Vector2.new(0.5, 0)
    )
    thick(subtitleLabel, 3)

    if endsAt > 0 then
        local number = Theme.text(
            holder,
            "Nombre",
            "",
            UDim2.fromOffset(120, 84),
            UDim2.new(0.5, 0, 0, 106),
            color,
            Vector2.new(0.5, 0)
        )
        thick(number, 4)
        task.spawn(function()
            while token == bannerToken do
                local left = endsAt - Workspace:GetServerTimeNow()
                if left <= 0 then
                    number.Visible = false
                    break
                end
                -- entier positif seulement : math.ceil d'une valeur a peine negative affichait « -0 »
                number.Text = string.format("%d", math.max(math.ceil(left), 1))
                task.wait(math.max(left - math.floor(left), 0.05))
            end
        end)
    end
end

--[[
    Zones d'ombre de « Vite, dans l'ombre ! » (15/09 : les plaques violettes etaient « moches »). La piece taguee
    ShadowZone reste invisible ; tout le rendu est local (seul ce joueur le voit), pose sur le sol reel sous chaque zone
    (rayon vers le bas) :
    - une tache d'ombre douce aux bords degrades (ombre de contact deja televersee), un peu plus large que le rayon ;
    - un anneau fin bleu nuit / argent qui pulse doucement sur le bord, avec un voile tres leger a l'interieur ;
    - de la poussiere d'etoiles lente qui monte dans la zone.
    Fondu a l'apparition et a la fin ; plus lumineux pendant « IL REGARDE ! » (setShadowZonesAlert).
]]
local SHADOW_TEXTURE = "rbxassetid://123681637407382"
local SHADOW_RING_COLOR = Color3.fromRGB(175, 200, 255)
local SHADOW_ALERT_COLOR = Color3.fromRGB(235, 242, 255)
local SHADOW_SPREAD = 1.15 -- tache et anneau un peu plus larges que le rayon de la zone (bords degrades)
local SHADOW_FADE = 0.6

type ShadowVisual = {
    decal: Decal,
    stroke: UIStroke,
    veil: Frame,
    emitter: ParticleEmitter,
    baseRate: number,
}

local shadowFolder: Folder? = nil
local shadowVisuals: { ShadowVisual } = {}

local function buildShadowVisual(folder: Folder, zone: BasePart, ignore: { Instance }): ShadowVisual
    local radiusAttribute = zone:GetAttribute("Radius")
    local radius = if typeof(radiusAttribute) == "number" then radiusAttribute else zone.Size.Z / 2
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    local hit = Workspace:Raycast(zone.Position + Vector3.new(0, 20, 0), Vector3.new(0, -120, 0), params)
    local groundY = if hit then hit.Position.Y else zone.Position.Y
    local width = radius * 2 * SHADOW_SPREAD
    local center = CFrame.new(zone.Position.X, groundY + 0.06, zone.Position.Z)

    local function flatPart(name: string, size: number): Part
        local part = Instance.new("Part")
        part.Name = name
        part.Size = Vector3.new(size, 0.05, size)
        part.CFrame = center
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CastShadow = false
        part.Transparency = 1
        part.Parent = folder
        return part
    end

    local disc = flatPart("OmbreZone", width)
    local decal = Instance.new("Decal")
    decal.Face = Enum.NormalId.Top
    decal.Texture = SHADOW_TEXTURE
    decal.Color3 = Color3.fromRGB(24, 28, 60)
    decal.Transparency = 1
    decal.Parent = disc

    local surface = Instance.new("SurfaceGui")
    surface.Face = Enum.NormalId.Top
    surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
    surface.CanvasSize = Vector2.new(512, 512)
    surface.LightInfluence = 0
    surface.Brightness = 1.6
    surface.Parent = disc
    local ringSize = 1 / SHADOW_SPREAD
    local veil = Instance.new("Frame")
    veil.Name = "Voile"
    veil.AnchorPoint = Vector2.new(0.5, 0.5)
    veil.Position = UDim2.fromScale(0.5, 0.5)
    veil.Size = UDim2.fromScale(ringSize, ringSize)
    veil.BackgroundColor3 = SHADOW_RING_COLOR
    veil.BackgroundTransparency = 1
    veil.BorderSizePixel = 0
    veil.Parent = surface
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)
    corner.Parent = veil
    local stroke = Instance.new("UIStroke")
    stroke.Color = SHADOW_RING_COLOR
    stroke.Thickness = 5
    stroke.Transparency = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = veil

    -- Poussiere d'etoiles : emise depuis un carre inscrit dans le cercle, pour rester dans la zone.
    local dust = flatPart("PoussiereZone", radius * 1.4)
    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Color = ColorSequence.new(SHADOW_RING_COLOR, Color3.new(1, 1, 1))
    emitter.LightEmission = 1
    emitter.LightInfluence = 0
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.05),
        NumberSequenceKeypoint.new(0.5, 0.35),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.3, 0.25),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(3, 5)
    emitter.Speed = NumberRange.new(0.4, 1.4)
    emitter.Acceleration = Vector3.new(0, 0.6, 0)
    emitter.Drag = 0.4
    emitter.RotSpeed = NumberRange.new(-40, 40)
    emitter.Shape = Enum.ParticleEmitterShape.Box
    emitter.EmissionDirection = Enum.NormalId.Top
    local rate = math.clamp(radius * 0.5, 3, 18)
    emitter.Rate = rate
    emitter.Enabled = false
    emitter.Parent = dust

    return { decal = decal, stroke = stroke, veil = veil, emitter = emitter, baseRate = rate }
end

local function setShadowZonesVisible(visible: boolean): ()
    local previous = shadowFolder
    local previousVisuals = shadowVisuals
    shadowFolder = nil
    shadowVisuals = {}
    if previous then
        local fade = TweenInfo.new(SHADOW_FADE, Enum.EasingStyle.Sine)
        for _, visual in previousVisuals do
            visual.emitter.Enabled = false
            TweenService:Create(visual.decal, fade, { Transparency = 1 }):Play()
            TweenService:Create(visual.stroke, fade, { Transparency = 1 }):Play()
            TweenService:Create(visual.veil, fade, { BackgroundTransparency = 1 }):Play()
        end
        -- la poussiere deja emise finit sa vie avant la suppression
        task.delay(if visible then SHADOW_FADE else 5, function()
            previous:Destroy()
        end)
    end
    if not visible then
        return
    end

    local zones: { BasePart } = {}
    local ignore: { Instance } = {}
    for _, zone in CollectionService:GetTagged(SHADOW_TAG) do
        if zone:IsA("BasePart") and zone:IsDescendantOf(Workspace) then
            -- changement local : la plaque reste invisible, le rendu est pose au sol
            zone.Transparency = 1
            table.insert(zones, zone)
            table.insert(ignore, zone)
        end
    end
    for _, other in Players:GetPlayers() do
        if other.Character then
            table.insert(ignore, other.Character)
        end
    end
    local folder = Instance.new("Folder")
    folder.Name = "OmbresVisuelles"
    folder.Parent = Workspace
    table.insert(ignore, folder)
    shadowFolder = folder

    local appear = TweenInfo.new(SHADOW_FADE, Enum.EasingStyle.Sine)
    local pulse = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    for _, zone in zones do
        local visual = buildShadowVisual(folder, zone, ignore)
        table.insert(shadowVisuals, visual)
        visual.emitter.Enabled = true
        TweenService:Create(visual.decal, appear, { Transparency = 0.12 }):Play()
        TweenService:Create(visual.veil, appear, { BackgroundTransparency = 0.93 }):Play()
        local strokeIn = TweenService:Create(visual.stroke, appear, { Transparency = 0.2 })
        strokeIn.Completed:Connect(function()
            if visual.stroke.Parent then
                TweenService:Create(visual.stroke, pulse, { Transparency = 0.65 }):Play()
            end
        end)
        strokeIn:Play()
    end
end

-- « IL REGARDE ! » : les zones sures brillent plus fort (anneau plus epais et plus clair, plus de poussiere).
local function setShadowZonesAlert(): ()
    local grow = TweenInfo.new(0.35, Enum.EasingStyle.Back)
    for _, visual in shadowVisuals do
        TweenService:Create(visual.stroke, grow, { Thickness = 10, Color = SHADOW_ALERT_COLOR }):Play()
        TweenService:Create(visual.veil, grow, { BackgroundTransparency = 0.82 }):Play()
        TweenService:Create(visual.decal, grow, { Transparency = 0 }):Play()
        visual.emitter.Rate = visual.baseRate * 2.5
    end
end

-- « Maman arrive ! » : a l'ouverture de la porte, la lune devient une lumiere chaude rasante qui entre par la porte
-- (Tuning.MOM_LIGHT_*) et dessine de vraies ombres de meubles au sol ; le serveur attrape ceux qui sont dans cette
-- lumiere. Remise de l'eclairage de nuit a la fin. Ignore dans les interieurs des bases (y tres bas), qui ont leur
-- propre ambiance (AmbianceController).
local savedLight: { clock: number, latitude: number, brightness: number, shift: Color3 }? = nil

local function setDoorLight(on: boolean): ()
    local Lighting = game:GetService("Lighting")
    if on then
        local character = player.Character
        local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
        if savedLight or root == nil or not root:IsA("BasePart") or root.Position.Y < -400 then
            return
        end
        savedLight = {
            clock = Lighting.ClockTime,
            latitude = Lighting.GeographicLatitude,
            brightness = Lighting.Brightness,
            shift = Lighting.ColorShift_Top,
        }
        Lighting.ClockTime = Tuning.MOM_LIGHT_CLOCK
        Lighting.GeographicLatitude = Tuning.MOM_LIGHT_LATITUDE
        Lighting.ColorShift_Top = Tuning.MOM_LIGHT_COLOR
        Lighting.Brightness = 0
        TweenService:Create(Lighting, TweenInfo.new(1.2, Enum.EasingStyle.Sine), {
            Brightness = Tuning.MOM_LIGHT_BRIGHTNESS,
        }):Play()
    else
        local saved = savedLight
        if saved == nil then
            return
        end
        savedLight = nil
        Lighting.ClockTime = saved.clock
        Lighting.GeographicLatitude = saved.latitude
        Lighting.ColorShift_Top = saved.shift
        Lighting.Brightness = saved.brightness
    end
end

-- Mini-cinematique a l'ouverture de la porte (demande utilisateur) : la camera de chaque joueur de la chambre file
-- vers la porte, montre la maman un instant, puis revient sur le personnage. Rien si une autre vue tient deja la
-- camera (vue d'un jouet, coffre) ou si le joueur est dans l'interieur d'une base.
local CINEMATIC_IN, CINEMATIC_HOLD, CINEMATIC_OUT = 0.5, 1.3, 0.45

local function momCinematic(): ()
    local camera = Workspace.CurrentCamera
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    if camera.CameraType ~= Enum.CameraType.Custom or root == nil or not root:IsA("BasePart") then
        return
    end
    if root.Position.Y < -400 then
        return
    end
    local target: Vector3? = nil
    for _, hinge in CollectionService:GetTagged("MomDoor") do
        local model = if hinge:IsDescendantOf(Workspace) then hinge.Parent else nil
        local mom = if model then model:FindFirstChild("Maman") else nil
        local pose = if mom then mom:GetAttribute("PoseVisible") else nil
        if typeof(pose) == "CFrame" and mom and mom:IsA("Model") then
            local _, size = mom:GetBoundingBox()
            target = pose.Position + Vector3.new(0, size.Y * 0.1, 0)
        end
    end
    if target == nil then
        return
    end
    -- Plan fixe face a la porte, un peu decale du cote oppose a la charniere : place du cote du joueur, la camera
    -- regardait le battant ouvert, qui cachait la maman (video du 14/09).
    local shot = CFrame.lookAt(target + Vector3.new(-230, -40, -40), target)
    local saved = camera.CFrame
    camera.CameraType = Enum.CameraType.Scriptable
    TweenService:Create(camera, TweenInfo.new(CINEMATIC_IN, Enum.EasingStyle.Sine), { CFrame = shot }):Play()
    task.delay(CINEMATIC_IN + CINEMATIC_HOLD, function()
        if camera.CameraType ~= Enum.CameraType.Scriptable then
            return
        end
        local back =
            TweenService:Create(camera, TweenInfo.new(CINEMATIC_OUT, Enum.EasingStyle.Sine), { CFrame = saved })
        back.Completed:Connect(function()
            camera.CameraType = Enum.CameraType.Custom
        end)
        back:Play()
    end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Nouveaux evenements (nuit du 15-16/09) : habillage local
-- ---------------------------------------------------------------------------------------------------------------

local GOLD = Color3.fromRGB(255, 205, 60)
-- Bonus du jouet dore geant, identique a EventService.GOLDEN_BONUS (serveur).
local GOLDEN_BONUS_TEXT = "25 000"

local effects: Folder? = nil

-- Dossier local des effets 3D de l'evenement en cours (detruit a la fin de l'evenement).
local function effectsFolder(): Folder
    local current = effects
    if current and current.Parent then
        return current
    end
    local folder = Instance.new("Folder")
    folder.Name = "EffetsEvenement"
    folder.Parent = Workspace
    effects = folder
    return folder
end

local function clearEffects(): ()
    if effects then
        effects:Destroy()
        effects = nil
    end
end

local function localRoot(): BasePart?
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    return if root and root:IsA("BasePart") then root else nil
end

-- Le joueur est dans la chambre (les interieurs des bases sont tres bas, avec leur propre ambiance).
local function inRoom(): boolean
    local root = localRoot()
    return root ~= nil and root.Position.Y > -400
end

local function anchorPart(name: string, cframe: CFrame, size: Vector3): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = cframe
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Transparency = 1
    part.Parent = effectsFolder()
    return part
end

local function loop(name: string): ()
    local s = sound(name)
    s.Looped = true
    if not s.IsPlaying then
        s.TimePosition = 0
        s:Play()
    end
end

-- Orage : eclair = flash blanc a l'ecran + exposition qui saute puis revient.
local stormExposure: number? = nil

local function stormBegin(): ()
    if inRoom() and stormExposure == nil then
        stormExposure = game:GetService("Lighting").ExposureCompensation
    end
end

local function stormEnd(): ()
    local base = stormExposure
    if base then
        game:GetService("Lighting").ExposureCompensation = base
        stormExposure = nil
    end
end

local function lightningFlash(): ()
    Sfx.play("lightning")
    local flash = Instance.new("Frame")
    flash.Name = "Eclair"
    flash.BackgroundColor3 = Color3.fromRGB(235, 242, 255)
    flash.BackgroundTransparency = 0.1
    flash.BorderSizePixel = 0
    flash.Size = UDim2.fromScale(1, 1)
    flash.ZIndex = 50
    flash.Parent = gui
    TweenService:Create(flash, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
    task.delay(0.75, function()
        flash:Destroy()
    end)
    local base = stormExposure
    if base then
        local Lighting = game:GetService("Lighting")
        Lighting.ExposureCompensation = base + 1.6
        TweenService:Create(Lighting, TweenInfo.new(0.55, Enum.EasingStyle.Quad), { ExposureCompensation = base })
            :Play()
    end
end

-- Boite a musique : poussiere pastel qui monte du berceau.
local function musicNotes(): ()
    -- centre du bebe (babyOrigin est defini plus bas, avec les animations d'attrape)
    local giant = Workspace:FindFirstChild("Geant")
    if giant == nil or not giant:IsA("Model") then
        return
    end
    local origin = (giant:GetBoundingBox()).Position
    local part = anchorPart("NotesBerceuse", CFrame.new(origin + Vector3.new(0, 40, 0)), Vector3.new(60, 4, 60))
    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 180, 220)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 220, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 170)),
    })
    emitter.LightEmission = 1
    emitter.LightInfluence = 0
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(0.5, 3),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.25, 0.1),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(3, 5)
    emitter.Speed = NumberRange.new(6, 12)
    emitter.SpreadAngle = Vector2.new(30, 30)
    emitter.RotSpeed = NumberRange.new(-60, 60)
    emitter.Rate = 10
    emitter.Parent = part
end

-- Cauchemar : vignette rouge sur les bords de l'ecran, qui pulse.
local function nightmareVignette(): ()
    local group = Instance.new("CanvasGroup")
    group.Name = "VignetteCauchemar"
    group.BackgroundTransparency = 1
    group.Size = UDim2.fromScale(1, 1)
    group.GroupTransparency = 1
    group.ZIndex = 40
    group.Parent = gui
    local sides: { { any } } = {
        { UDim2.fromScale(1, 0.24), UDim2.fromScale(0, 0), 90 },
        { UDim2.fromScale(1, 0.24), UDim2.fromScale(0, 0.76), -90 },
        { UDim2.fromScale(0.18, 1), UDim2.fromScale(0, 0), 0 },
        { UDim2.fromScale(0.18, 1), UDim2.fromScale(0.82, 0), 180 },
    }
    for i, side in sides do
        local frame = Instance.new("Frame")
        frame.Name = "Bord" .. i
        frame.BackgroundColor3 = Color3.fromRGB(150, 10, 30)
        frame.BorderSizePixel = 0
        frame.Size = side[1]
        frame.Position = side[2]
        frame.Parent = group
        local gradient = Instance.new("UIGradient")
        gradient.Transparency = NumberSequence.new(0, 1)
        gradient.Rotation = side[3]
        gradient.Parent = frame
    end
    TweenService:Create(group, TweenInfo.new(0.6), { GroupTransparency = 0.35 }):Play()
    task.delay(0.6, function()
        if group.Parent then
            TweenService:Create(
                group,
                TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                { GroupTransparency = 0.05 }
            ):Play()
        end
    end)
end

local function clearVignette(): ()
    local group = gui:FindFirstChild("VignetteCauchemar")
    if group and group:IsA("CanvasGroup") then
        TweenService:Create(group, TweenInfo.new(0.5), { GroupTransparency = 1 }):Play()
        task.delay(0.55, function()
            group:Destroy()
        end)
    end
end

-- Jouet dore geant : faisceau dore qui monte au ciel au-dessus du jouet et etoile visible de loin, qui suivent le jouet.
local function goldenBeacon(): ()
    task.spawn(function()
        local live = Workspace:WaitForChild("ToysLive", 5)
        if live == nil then
            return
        end
        local toy: Instance? = nil
        local started = os.clock()
        while toy == nil and os.clock() - started < 4 do
            for _, child in live:GetChildren() do
                if child:GetAttribute("EventDore") == true then
                    toy = child
                end
            end
            task.wait(0.2)
        end
        local found = toy
        if found == nil then
            return
        end
        local anchor = anchorPart("PhareDore", CFrame.new(), Vector3.new(1, 1, 1))
        local bottom = Instance.new("Attachment")
        bottom.Parent = anchor
        local top = Instance.new("Attachment")
        top.Position = Vector3.new(0, 420, 0)
        top.Parent = anchor
        local beam = Instance.new("Beam")
        beam.Attachment0 = bottom
        beam.Attachment1 = top
        beam.Color = ColorSequence.new(GOLD, Color3.fromRGB(255, 250, 210))
        beam.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.15),
            NumberSequenceKeypoint.new(1, 1),
        })
        beam.LightEmission = 1
        beam.LightInfluence = 0
        beam.Width0 = 7
        beam.Width1 = 2
        beam.FaceCamera = true
        beam.Parent = anchor
        local board = Instance.new("BillboardGui")
        board.Name = "EtoileDoree"
        board.Size = UDim2.fromOffset(64, 64)
        board.StudsOffsetWorldSpace = Vector3.new(0, 18, 0)
        board.AlwaysOnTop = true
        board.MaxDistance = 3000
        board.LightInfluence = 0
        board.Adornee = anchor
        board.Parent = anchor
        Theme.image(board, "Icone", "etoile", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
        while anchor.Parent and found.Parent do
            local position: Vector3? = nil
            if found:IsA("Model") then
                position = (found:GetBoundingBox()).Position
            elseif found:IsA("BasePart") then
                position = found.Position
            end
            if position then
                anchor.CFrame = CFrame.new(position)
            end
            task.wait()
        end
        anchor:Destroy()
    end)
end

-- Panne de veilleuse : lampes de la chambre eteintes, image plus sombre, lampe torche douce sur le joueur.
local outageLights: { Light } = {}
local outageExposure: number? = nil
local TORCH_NAME = "LampeTorchePanne"

local function outageBegin(): ()
    local root = localRoot()
    if root == nil or root.Position.Y < -400 or outageExposure ~= nil then
        return
    end
    local chambre = Workspace:FindFirstChild("Chambre")
    if chambre then
        for _, descendant in chambre:GetDescendants() do
            if descendant:IsA("Light") and descendant.Enabled then
                descendant.Enabled = false
                table.insert(outageLights, descendant)
            end
        end
    end
    local Lighting = game:GetService("Lighting")
    outageExposure = Lighting.ExposureCompensation
    TweenService:Create(Lighting, TweenInfo.new(0.6), { ExposureCompensation = Lighting.ExposureCompensation - 1.3 })
        :Play()
    local torch = Instance.new("PointLight")
    torch.Name = TORCH_NAME
    torch.Range = 26
    torch.Brightness = 1.4
    torch.Color = Color3.fromRGB(255, 225, 180)
    torch.Shadows = true
    torch.Parent = root
end

local function outageEnd(): ()
    for _, light in outageLights do
        if light.Parent then
            light.Enabled = true
        end
    end
    table.clear(outageLights)
    local base = outageExposure
    if base then
        game:GetService("Lighting").ExposureCompensation = base
        outageExposure = nil
    end
    local character = player.Character
    local torch = if character then character:FindFirstChild(TORCH_NAME, true) else nil
    if torch then
        torch:Destroy()
    end
end

-- Papa ronfle : de grands « Z » qui s'envolent devant la porte de la chambre.
local function snoreZzz(): ()
    local hinge: BasePart? = nil
    for _, candidate in CollectionService:GetTagged("MomDoor") do
        if candidate:IsA("BasePart") and candidate:IsDescendantOf(Workspace) then
            hinge = candidate
        end
    end
    if hinge == nil then
        return
    end
    local anchor = anchorPart("RonflementsPapa", CFrame.new(hinge.Position + Vector3.new(-30, 70, -65)), Vector3.one)
    local board = Instance.new("BillboardGui")
    board.Name = "Zzz"
    board.Size = UDim2.fromScale(60, 90)
    board.LightInfluence = 0
    board.MaxDistance = 1200
    board.Adornee = anchor
    board.Parent = anchor
    task.spawn(function()
        local index = 0
        while anchor.Parent do
            index += 1
            local x = 0.5 + math.sin(index * 1.7) * 0.18
            local label = Theme.text(
                board,
                "Z" .. index,
                "Z",
                UDim2.fromScale(0.34, 0.24),
                UDim2.fromScale(x, 0.95),
                Theme.WHITE,
                Vector2.new(0.5, 1)
            )
            label.Rotation = math.random(-25, 25)
            local stroke = label:FindFirstChildOfClass("UIStroke")
            local rise = TweenInfo.new(2.6, Enum.EasingStyle.Sine)
            TweenService:Create(label, rise, {
                Position = UDim2.fromScale(x + math.sin(index) * 0.2, 0.2),
                TextTransparency = 1,
            }):Play()
            if stroke then
                TweenService:Create(stroke, rise, { Transparency = 1 }):Play()
            end
            task.delay(2.7, function()
                label:Destroy()
            end)
            task.wait(0.85)
        end
    end)
end

-- Evenements ajoutes : un bloc par evenement, rien a faire si le nom n'est pas connu. Vrai si traite.
local function onNewRoomEvent(kind: string, phase: string, endsAt: number): boolean
    if kind == "Storm" then
        if phase == "warn" then
            stormBegin()
            setShadowZonesVisible(true)
            Sfx.play("thunder")
            showBanner(
                "ORAGE !",
                "À chaque éclair, cache-toi dans l'ombre !",
                Color3.fromRGB(150, 190, 255),
                endsAt,
                "lune"
            )
        elseif phase == "rumble" then
            Sfx.play("thunder", { volume = 0.35 })
        elseif phase == "flash" then
            lightningFlash()
        else
            stormEnd()
            setShadowZonesVisible(false)
            clearBanner()
        end
    elseif kind == "MusicBox" then
        if phase == "start" then
            loop("lullaby")
            musicNotes()
            showBanner(
                "BOÎTE À MUSIQUE",
                "Le bébé dort à poings fermés : vole sans bruit !",
                Theme.MINT,
                endsAt,
                "pouvoirBerceuse"
            )
        else
            stop("lullaby")
            clearEffects()
            clearBanner()
        end
    elseif kind == "ToyRain" then
        if phase == "warn" then
            Sfx.play("sneeze")
            showBanner("ATCHOUM !", "L'étagère éternue des jouets !", Theme.YELLOW, 0, "boutonMesJouets")
        elseif phase == "start" then
            task.spawn(function()
                for _ = 1, 8 do
                    Sfx.play("toyPop")
                    task.wait(0.3)
                end
            end)
        else
            clearBanner()
        end
    elseif kind == "Nightmare" then
        if phase == "start" then
            loop("whimper")
            nightmareVignette()
            showBanner("CAUCHEMAR !", "Le bébé est agité : le bruit compte double !", Theme.RED, endsAt, "bebeDort")
        else
            stop("whimper")
            clearVignette()
            clearBanner()
        end
    elseif kind == "GoldenToy" then
        if phase == "start" then
            Sfx.play("chime")
            goldenBeacon()
            showBanner(
                "JOUET DORÉ !",
                "Le premier qui le ramène gagne " .. GOLDEN_BONUS_TEXT .. " tétines !",
                GOLD,
                0,
                "etoile"
            )
        elseif phase == "won" then
            local winner = Workspace:GetAttribute("EventGagnant")
            Sfx.play("fanfare")
            showBanner(
                "GAGNÉ !",
                (if typeof(winner) == "string" then winner else "Quelqu'un") .. " a ramené le jouet doré !",
                GOLD,
                0,
                "tetine"
            )
        else
            clearEffects()
            clearBanner()
        end
    elseif kind == "PowerOutage" then
        if phase == "start" then
            Sfx.play("powerDown")
            outageBegin()
            showBanner(
                "PANNE DE VEILLEUSE !",
                "Il fait noir... le bébé entend mieux !",
                Color3.fromRGB(190, 140, 255),
                endsAt,
                "lune"
            )
        else
            outageEnd()
            clearBanner()
        end
    elseif kind == "DadSnores" then
        if phase == "start" then
            loop("snore")
            snoreZzz()
            showBanner("PAPA RONFLE", "Ses ronflements couvrent tes pas !", Theme.BLUE, endsAt, "bebeDort")
        else
            stop("snore")
            clearEffects()
            clearBanner()
        end
    elseif kind == "HouseCat" then
        if phase == "start" then
            Sfx.play("meow", { volume = 0.3 })
            showBanner("LE CHAT !", "Évite-le : il te fait tout lâcher !", Theme.YELLOW, endsAt, "etoile")
        elseif phase == "meow" then
            Sfx.play("meow")
        else
            clearBanner()
        end
    elseif kind == "BabyChest" then
        if phase == "start" then
            Sfx.play("chime")
            showBanner(
                "LE COFFRE S'OUVRE !",
                "Un jouet légendaire est dedans : cours !",
                GOLD,
                endsAt,
                "articleCoffre"
            )
        elseif phase == "taken" then
            local winner = Workspace:GetAttribute("EventGagnant")
            Sfx.play("fanfare")
            showBanner(
                "ATTRAPÉ !",
                (if typeof(winner) == "string" then winner else "Quelqu'un") .. " a pris le jouet du coffre !",
                GOLD,
                0,
                "coffreDore"
            )
        else
            clearBanner()
        end
    elseif kind == "LivingToy" then
        -- envoye au seul joueur qui a depose un jouet vivant (LivingToyService)
        if phase == "won" then
            local bonus = Players.LocalPlayer:GetAttribute("BonusVivant")
            Sfx.play("livingToy")
            Sfx.play("fanfare")
            showBanner(
                "JOUET VIVANT ATTRAPÉ !",
                "Bonus : +" .. (if typeof(bonus) == "number" then tostring(bonus) else "?") .. " tétines",
                GOLD,
                0,
                "etoile"
            )
            local token = bannerToken
            task.delay(4, function()
                if token == bannerToken then
                    clearBanner()
                end
            end)
        end
    else
        return false
    end
    return true
end

local function onRoomEvent(kind: string, phase: string, endsAt: number): ()
    if onNewRoomEvent(kind, phase, endsAt) then
        return
    end
    -- Oreille fine (amelioration) : indice avant l'alerte, envoye seulement a ce joueur.
    if phase == "hint" then
        if kind == "MomComing" then
            showBanner("Chut...", "Tu entends des pas dans l'escalier...", Theme.SOFT_TEXT, 0)
        elseif kind == "SurpriseWake" then
            showBanner("Chut...", "Le bébé remue dans son sommeil...", Theme.SOFT_TEXT, 0)
        end
        return
    end
    if kind == "SurpriseWake" then
        if phase == "warn" then
            showBanner("Hmm ?..", "Le bébé gigote... Ne bouge plus !", Theme.YELLOW, endsAt)
            play("shh")
        else
            clearBanner()
        end
    elseif kind == "ShadowRun" then
        if phase == "warn" then
            setShadowZonesVisible(true)
            showBanner("VITE, DANS L'OMBRE !", "Le bébé va ouvrir les yeux !", Color3.fromRGB(190, 140, 255), endsAt)
        elseif phase == "open" then
            setShadowZonesAlert()
            showBanner("IL REGARDE !", "Reste dans l'ombre...", Theme.RED, 0)
        else
            setShadowZonesVisible(false)
            clearBanner()
        end
    elseif kind == "MomComing" then
        if phase == "warn" then
            play("stairs")
            showBanner("MAMAN ARRIVE !", "Cache-toi dans l'ombre des meubles !", Theme.PINK, endsAt)
        elseif phase == "open" then
            stop("stairs")
            play("creak")
            setDoorLight(true)
            task.spawn(momCinematic)
            showBanner("CHUT !", "Sors de la lumière de la porte !", Theme.RED, 0)
        else
            setDoorLight(false)
            clearBanner()
        end
    end
end

local function onTrapArmed(seconds: number): ()
    local token = bannerToken + 1
    showBanner("JOUET PIÉGÉ !", "Il va exploser !", Theme.RED, Workspace:GetServerTimeNow() + seconds)
    token = bannerToken
    task.spawn(function()
        local start = os.clock()
        local beepSound = sound("beep")
        while os.clock() - start < seconds do
            beepSound.PlaybackSpeed = 1 + (os.clock() - start) / seconds
            beepSound.TimePosition = 0
            beepSound:Play()
            task.wait(math.max(0.45 - (os.clock() - start) * 0.12, 0.12))
        end
        if token == bannerToken then
            clearBanner()
        end
    end)
end

--[[
    Animations d'attrape (retour utilisateur du 15/09 : « se faire propulser c'est pas ouf »). La vitesse de
    propulsion vient du serveur (launch) ; tout l'habillage est local :
    - bebe (moved, jumped, seen) : onde du cri qui part du bebe vers le joueur, bulle « OUIIIN ! », propulsion en
      tonneau, etoiles d'etourdissement a l'atterrissage ;
    - maman (mom) : un chausson geant part de la porte, frappe le joueur (« BONK ! »), vol plane en tournant, etoiles ;
    - jouet lance (hit) : propulsion et etoiles.
]]
local WAVE_SECONDS = 0.3
local SLIPPER_SECONDS = 0.4

local function shakeCamera(strength: number): ()
    local camera = Workspace.CurrentCamera
    task.spawn(function()
        for i = 1, 10 do
            camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, math.rad((if i % 2 == 0 then 1 else -1) * strength))
            task.wait(0.03)
        end
    end)
end

-- Texte qui saute au-dessus de la tete (« OUIIIN ! », « BONK ! »).
local function shout(character: Model, text: string, color: Color3, seconds: number): ()
    local head = character:FindFirstChild("Head")
    if head == nil or not head:IsA("BasePart") then
        return
    end
    local board = Instance.new("BillboardGui")
    board.Name = "Cri"
    board.Size = UDim2.fromScale(7, 2)
    board.StudsOffset = Vector3.new(0, 3.4, 0)
    board.LightInfluence = 0
    board.AlwaysOnTop = true
    board.Adornee = head
    board.Parent = head
    local label =
        Theme.text(board, "Texte", text, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), color, Vector2.new(0.5, 0.5))
    label.TextScaled = true
    local scale = Instance.new("UIScale")
    scale.Scale = 0.2
    scale.Parent = label
    TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
    task.delay(seconds, function()
        TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
        task.delay(0.35, function()
            board:Destroy()
        end)
    end)
end

-- Etoiles qui tournent autour de la tete (etourdi).
local function stunStars(character: Model, seconds: number): ()
    local head = character:FindFirstChild("Head")
    if head == nil or not head:IsA("BasePart") then
        return
    end
    local board = Instance.new("BillboardGui")
    board.Name = "Etourdi"
    board.Size = UDim2.fromScale(4.5, 2)
    board.StudsOffset = Vector3.new(0, 1.5, 0)
    board.LightInfluence = 0
    board.Adornee = head
    board.Parent = head
    local stars: { GuiObject } = {}
    for i = 1, 5 do
        table.insert(
            stars,
            Theme.image(
                board,
                "Etoile" .. i,
                "etoile",
                UDim2.fromScale(0.2, 0.45),
                UDim2.fromScale(0.5, 0.5),
                Vector2.new(0.5, 0.5)
            )
        )
    end
    task.spawn(function()
        local started = os.clock()
        while board.Parent and os.clock() - started < seconds do
            local t = os.clock() - started
            for i, star in stars do
                local angle = t * 4 + i * (math.pi * 2 / #stars)
                local depth = (math.sin(angle) + 1) / 2
                star.Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.38, 0.5 + math.sin(angle) * 0.22)
                star.Size = UDim2.fromScale(0.14 + 0.08 * depth, 0.32 + 0.18 * depth)
                star.ZIndex = if depth > 0.5 then 2 else 1
            end
            task.wait()
        end
        board:Destroy()
    end)
end

-- Position du bebe (centre du modele qui pleure, sinon du geant).
local function babyOrigin(): Vector3?
    local giant = Workspace:FindFirstChild("Geant")
    if giant == nil then
        return nil
    end
    local crying = giant:FindFirstChild("Pleure")
    local model = if crying and crying:IsA("Model") then crying else giant
    if model:IsA("Model") then
        return (model:GetBoundingBox()).Position
    end
    return nil
end

-- Onde du cri : anneau translucide qui part du bebe et file vers le joueur en grossissant.
local function cryWave(from: Vector3, to: Vector3): ()
    local ring = Instance.new("Part")
    ring.Name = "OndeCri"
    ring.Shape = Enum.PartType.Cylinder
    ring.Material = Enum.Material.Neon
    ring.Color = Color3.fromRGB(255, 170, 205)
    ring.Transparency = 0.35
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.CanTouch = false
    ring.CastShadow = false
    ring.Size = Vector3.new(0.8, 8, 8)
    -- l'axe du cylindre (X) dans la direction du trajet : un disque qui fait face au joueur
    local facing = CFrame.lookAt(from, to) * CFrame.Angles(0, math.rad(90), 0)
    ring.CFrame = facing
    ring.Parent = Workspace
    TweenService:Create(ring, TweenInfo.new(WAVE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        CFrame = facing.Rotation + to,
        Size = Vector3.new(0.8, 36, 36),
        Transparency = 0.85,
    }):Play()
    task.delay(WAVE_SECONDS + 0.05, function()
        ring:Destroy()
    end)
end

-- Point de lancer du chausson : main de la maman devant la porte, sinon la charniere de la porte.
local function momOrigin(): Vector3?
    for _, hinge in CollectionService:GetTagged("MomDoor") do
        if not hinge:IsDescendantOf(Workspace) or not hinge:IsA("BasePart") then
            continue
        end
        local model = hinge.Parent
        local mom = if model then model:FindFirstChild("Maman") else nil
        local pose = if mom then mom:GetAttribute("PoseVisible") else nil
        if typeof(pose) == "CFrame" then
            return pose.Position + Vector3.new(-40, 30, 0)
        end
        return hinge.Position
    end
    return nil
end

-- Chausson geant en quelques pieces arrondies (projectile furtif, visible par ce joueur seulement).
local function buildSlipper(): Model
    local model = Instance.new("Model")
    model.Name = "ChaussonMaman"
    local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, ball: boolean): BasePart
        local part = Instance.new("Part")
        part.Name = name
        part.Size = size
        part.Color = color
        part.Material = Enum.Material.SmoothPlastic
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CastShadow = false
        part.CFrame = offset
        if ball then
            local mesh = Instance.new("SpecialMesh")
            mesh.MeshType = Enum.MeshType.Sphere
            mesh.Parent = part
        end
        part.Parent = model
        return part
    end
    local sole = piece("Semelle", Vector3.new(5, 1.4, 11), CFrame.new(), Color3.fromRGB(225, 110, 150), true)
    piece("Dessus", Vector3.new(4.6, 3, 8), CFrame.new(0, 1.3, 1.4), Color3.fromRGB(255, 175, 205), true)
    piece("Pompon", Vector3.new(2.4, 2.4, 2.4), CFrame.new(0, 2.9, -3.2), Color3.fromRGB(255, 250, 250), true)
    model.PrimaryPart = sole
    return model
end

local function throwSlipper(from: Vector3, root: BasePart): ()
    local slipper = buildSlipper()
    slipper.Parent = Workspace
    local started = os.clock()
    local connection: RBXScriptConnection? = nil
    connection = game:GetService("RunService").RenderStepped:Connect(function()
        local a = math.clamp((os.clock() - started) / SLIPPER_SECONDS, 0, 1)
        local target = root.Position
        local position = from:Lerp(target, a) + Vector3.new(0, math.sin(a * math.pi) * 18, 0)
        slipper:PivotTo(CFrame.lookAt(position, target) * CFrame.Angles(a * math.pi * 6, 0, 0))
        if a >= 1 and connection then
            connection:Disconnect()
            -- le chausson rebondit et disparait
            TweenService:Create(slipper.PrimaryPart :: BasePart, TweenInfo.new(0.4), { Transparency = 1 }):Play()
            task.delay(0.45, function()
                slipper:Destroy()
            end)
        end
    end)
end

local function launchPlayer(humanoid: Humanoid, root: BasePart, launch: Vector3, spin: Vector3): ()
    humanoid.PlatformStand = true
    root.AssemblyLinearVelocity = launch
    root.AssemblyAngularVelocity = spin
    task.delay(Tuning.CATCH_STUN_SECONDS, function()
        if humanoid.Parent then
            humanoid.PlatformStand = false
            root.AssemblyAngularVelocity = Vector3.zero
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end)
end

-- Attrape : habillage selon la cause, puis propulsion du personnage (simule chez ce client) et relevage.
local function onCaught(reason: string, launch: Vector3): ()
    local character = player.Character
    local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    if
        character == nil
        or humanoid == nil
        or root == nil
        or not root:IsA("BasePart")
        or typeof(launch) ~= "Vector3"
    then
        return
    end
    local stun = Tuning.CATCH_STUN_SECONDS
    if reason == "mom" then
        local from = momOrigin()
        local delay = if from then SLIPPER_SECONDS else 0
        if from then
            throwSlipper(from, root)
        end
        task.delay(delay, function()
            shout(character, "BONK !", Theme.YELLOW, 1.2)
            shakeCamera(3)
            -- vol plane en tournant sur soi-meme
            launchPlayer(humanoid, root, launch, Vector3.new(0, 16, 0))
            task.delay(stun * 0.5, function()
                stunStars(character, stun + 1.2)
            end)
        end)
    elseif reason == "dog" then
        -- chien de la cuisine : pas de cri du bebe ; le « OUAF ! » a l'ecran vient de DogController (un second au-dessus
        -- du joueur s'empilait avec lui et avec « ATTRAPÉ ! »)
        shakeCamera(2)
        launchPlayer(humanoid, root, launch, Vector3.new(math.random(-8, 8), math.random(-3, 3), math.random(-8, 8)))
        task.delay(stun * 0.5, function()
            stunStars(character, stun + 0.8)
        end)
    elseif reason == "hit" then
        shakeCamera(1.5)
        launchPlayer(humanoid, root, launch, Vector3.new(math.random(-6, 6), math.random(-3, 3), math.random(-6, 6)))
        task.delay(stun * 0.5, function()
            stunStars(character, stun + 0.8)
        end)
    else
        -- screamer (tete du bebe qui fonce sur l'ecran, rire) : seulement pour les captures du bebe
        if Screamer.isBabyReason(reason) then
            Screamer.play()
        end
        local from = babyOrigin()
        if from then
            cryWave(from, root.Position)
        end
        shout(character, "OUIIIN !", Theme.PINK, 1.4)
        task.delay(if from then WAVE_SECONDS * 0.85 else 0, function()
            shakeCamera(2.5)
            -- emporte en tonneau
            local side = if math.random() < 0.5 then -1 else 1
            launchPlayer(humanoid, root, launch, Vector3.new(14 * side, math.random(-4, 4), 10 * side))
            task.delay(stun * 0.6, function()
                stunStars(character, stun + 1)
            end)
        end)
    end
end

-- (Les pastilles des bonus achetes sous le compteur de tetines ont ete retirees : elles passaient par-dessus la
-- barre d'XP de LevelController ; les ameliorations restent visibles dans la boutique.)

function EventController:Init(): () end

function EventController:Start(): ()
    gui = Instance.new("ScreenGui")
    gui.Name = "Evenements"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 8
    gui.Parent = player:WaitForChild("PlayerGui")

    for _, name in { "cry", "shh", "stairs", "creak", "beep", "boom" } do
        sound(name)
    end

    local roomEvent = Remotes.Get("RoomEvent") :: RemoteEvent
    local trapArmed = Remotes.Get("TrapArmed") :: RemoteEvent
    local trapExploded = Remotes.Get("TrapExploded") :: RemoteEvent
    local caught = Remotes.Get("Caught") :: RemoteEvent
    local giantState = Remotes.Get("GiantState") :: RemoteEvent
    local noiseState = Remotes.Get("NoiseState") :: RemoteEvent

    roomEvent.OnClientEvent:Connect(onRoomEvent)
    trapArmed.OnClientEvent:Connect(onTrapArmed)
    trapExploded.OnClientEvent:Connect(function()
        clearBanner()
        showBanner("BOUM !", "Le bébé se réveille !", Theme.RED, 0)
        task.delay(2, clearBanner)
    end)
    caught.OnClientEvent:Connect(onCaught)
    player:GetAttributeChangedSignal("Piece"):Connect(function()
        if player:GetAttribute("Piece") == "Cuisine" then
            clearBanner()
        end
    end)

    giantState.OnClientEvent:Connect(function(state: string)
        if state == "Waking" or state == "Hunting" then
            local cry = sound("cry")
            if not cry.IsPlaying then
                cry.Looped = true
                cry:Play()
            end
        else
            stop("cry")
        end
    end)

    local lastShh = -math.huge
    local wasNear = false
    noiseState.OnClientEvent:Connect(function(value: number, max: number)
        local near = value / math.max(max, 1) >= Tuning.NEAR_WAKE_FRACTION
        if near and not wasNear and os.clock() - lastShh > SHH_COOLDOWN then
            lastShh = os.clock()
            play("shh")
        end
        wasNear = near
    end)

    -- Reveil en douceur (BabyVisualService, attribut Remue de workspace.Geant) : le bebe se retourne et une bulle
    -- « Mmh... » flotte au-dessus du berceau, derniere chance pour s'immobiliser.
    task.spawn(function()
        local giant = workspace:WaitForChild("Geant", 30)
        local sleeper = if giant then giant:FindFirstChild("Dort") else nil
        local anchor = if sleeper then sleeper:FindFirstChildWhichIsA("BasePart", true) else nil
        if giant == nil or anchor == nil then
            return
        end
        local bubble = Instance.new("BillboardGui")
        bubble.Name = "BulleRemue"
        bubble.Adornee = anchor
        bubble.Size = UDim2.fromOffset(170, 70)
        bubble.StudsOffsetWorldSpace = Vector3.new(0, 45, 0)
        bubble.AlwaysOnTop = true
        bubble.MaxDistance = 1200
        bubble.LightInfluence = 0
        bubble.Enabled = false
        bubble.Parent = player:WaitForChild("PlayerGui")
        local card = Theme.panel(bubble, "Carte", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.zero)
        local cardStroke = card:FindFirstChildOfClass("UIStroke")
        if cardStroke then
            cardStroke.Color = Theme.YELLOW
        end
        Theme.text(
            card,
            "Texte",
            "Mmh...",
            UDim2.new(1, -24, 1, -16),
            UDim2.fromScale(0.5, 0.5),
            Theme.YELLOW,
            Vector2.new(0.5, 0.5)
        )
        local scale = Instance.new("UIScale")
        scale.Parent = card
        local function refresh(): ()
            local stirring = giant:GetAttribute("Remue") == true and player:GetAttribute("Piece") ~= "Cuisine"
            bubble.Enabled = stirring
            if stirring then
                scale.Scale = 0.6
                TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
            end
        end
        giant:GetAttributeChangedSignal("Remue"):Connect(refresh)
        refresh()
    end)
end

return EventController
