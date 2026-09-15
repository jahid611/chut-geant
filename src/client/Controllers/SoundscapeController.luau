--!strict

--[[
    SoundscapeController
    L'ambiance sonore de la chambre, jouee chez ce joueur seulement :
    - musique de fond (berceuse boite a musique) en boucle, baissee pendant les evenements (RoomEvent warn/open)
      et quand le bebe est reveille (GiantState Waking/Hunting), remise ensuite ;
    - tic-tac angoissant pendant tout compte a rebours (RoomEvent phase warn, jouet piege TrapArmed, reveil du
      bebe GiantState Waking) : il accelere et monte sur les dernieres secondes, s'arrete a zero ou quand
      l'evenement passe a open/end ;
    - jauge de bruit (NoiseState) : battement de coeur doux (demande utilisateur du 15/09 : l'ancien son de moteur
      etait « horrible »), seulement quand la jauge monte au-dessus de HEART_START ; plus fort et plus rapide plus
      elle est haute, coupe en HEART_FADE secondes des qu'elle redescend ou ne bouge plus.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Sfx = require(script.Parent.Parent.Ui.Sfx)

-- Sons de la bibliotheque Roblox (faciles a remplacer ici).
local SOUNDS = {
    -- « Music Box Lullaby (30s) » : musique de fond en boucle
    music = "rbxassetid://9047796475",
    -- « TICK TOCK 06 120BPM » (Pro Sound Effects) : comptes a rebours
    tick = "rbxassetid://9043366464",
    -- « HEARTBEAT 02 96BPM » (Pro Sound Effects, Epic Score) : battement de coeur quand la jauge monte
    gauge = "rbxassetid://9043365842",
}

local MUSIC_VOLUME = 0.25
local MUSIC_DUCKED = 0.07
-- Tic-tac : vitesse et volume de base, puis acceleration sur les TICK_RUSH dernieres secondes.
local TICK_VOLUME = 0.35
local TICK_VOLUME_END = 0.75
local TICK_SPEED_END = 1.5
local TICK_RUSH = 3
-- Jauge : variation minimale (fraction) comptee comme un mouvement, et duree pendant laquelle le son continue
-- apres le dernier mouvement (les mises a jour arrivent environ 10 fois par seconde).
local GAUGE_MIN_STEP = 0.004
local GAUGE_HOLD = 0.35
-- Battement de coeur : jauge minimale, volume et vitesse de lecture de HEART_START a la jauge pleine.
local HEART_START = 0.35
local HEART_VOLUME_MIN = 0.12
local HEART_VOLUME_MAX = 0.4
local HEART_SPEED_MIN = 0.9
local HEART_SPEED_MAX = 1.35
local HEART_FADE = 0.15

local SoundscapeController = {}

local music: Sound
local tick: Sound
local gauge: Sound

-- Evenements en cours (pour baisser la musique) et fins de compte a rebours, en temps serveur.
local activeEvents: { [string]: boolean } = {}
local eventEnds: { [string]: number } = {}
local trapEndsAt = 0
local wakeEndsAt = 0
local babyAwake = false

local gaugeFraction = 0
local gaugeDirection = 0
local gaugeMovedAt = -math.huge

-- groupName : groupe de sons regle dans le menu Parametres (« Musique » ou « Effets »).
local function makeSound(name: string, id: string, looped: boolean, groupName: string): Sound
    local s = Instance.new("Sound")
    s.Name = "Ambiance_" .. name
    s.SoundId = id
    s.Looped = looped
    s.Volume = 0
    s.SoundGroup = Sfx.group(groupName)
    s.Parent = SoundService
    return s
end

local ducked = false
local function updateMusic(): ()
    local shouldDuck = babyAwake or next(activeEvents) ~= nil
    if shouldDuck == ducked then
        return
    end
    ducked = shouldDuck
    TweenService:Create(music, TweenInfo.new(if shouldDuck then 0.6 else 2), {
        Volume = if shouldDuck then MUSIC_DUCKED else MUSIC_VOLUME,
    }):Play()
end

local function onRoomEvent(kind: string, phase: string, endsAt: number): ()
    if phase == "warn" or phase == "open" then
        activeEvents[kind] = true
    else
        activeEvents[kind] = nil
    end
    if phase == "warn" and endsAt > Workspace:GetServerTimeNow() then
        eventEnds[kind] = endsAt
    else
        eventEnds[kind] = nil
    end
    updateMusic()
end

local function onGiantState(state: string, endsAt: number?): ()
    babyAwake = state == "Waking" or state == "Hunting"
    wakeEndsAt = if state == "Waking" and typeof(endsAt) == "number" then endsAt else 0
    updateMusic()
end

local function onNoise(value: number, max: number): ()
    local fraction = math.clamp(value / math.max(max, 1), 0, 1)
    local delta = fraction - gaugeFraction
    gaugeFraction = fraction
    if math.abs(delta) >= GAUGE_MIN_STEP then
        gaugeDirection = if delta > 0 then 1 else -1
        gaugeMovedAt = os.clock()
    end
end

-- Fin de compte a rebours la plus proche encore a venir, ou nil.
local function nextCountdown(now: number): number?
    local best: number? = nil
    local function consider(t: number): ()
        if t > now and (best == nil or t < (best :: number)) then
            best = t
        end
    end
    for _, t in eventEnds do
        consider(t)
    end
    consider(trapEndsAt)
    consider(wakeEndsAt)
    return best
end

local function step(dt: number): ()
    -- Tic-tac
    local now = Workspace:GetServerTimeNow()
    local ends = nextCountdown(now)
    if ends then
        local rush = math.clamp((TICK_RUSH - (ends - now)) / TICK_RUSH, 0, 1)
        tick.PlaybackSpeed = 1 + (TICK_SPEED_END - 1) * rush
        tick.Volume = TICK_VOLUME + (TICK_VOLUME_END - TICK_VOLUME) * rush
        if not tick.IsPlaying then
            tick.TimePosition = 0
            tick:Play()
        end
    elseif tick.IsPlaying then
        tick.Volume = math.max(tick.Volume - dt * 4, 0)
        if tick.Volume <= 0 then
            tick:Stop()
        end
    end

    -- Jauge : battement de coeur quand elle monte au-dessus de HEART_START, volume et vitesse lisses vers la cible ;
    -- montee rapide, fondu lent.
    local rising = os.clock() - gaugeMovedAt < GAUGE_HOLD and gaugeDirection > 0
    local level = math.clamp((gaugeFraction - HEART_START) / (1 - HEART_START), 0, 1)
    local targetVolume = if rising and gaugeFraction >= HEART_START
        then HEART_VOLUME_MIN + (HEART_VOLUME_MAX - HEART_VOLUME_MIN) * level
        else 0
    local targetSpeed = HEART_SPEED_MIN + (HEART_SPEED_MAX - HEART_SPEED_MIN) * level
    if targetVolume > gauge.Volume then
        gauge.Volume += (targetVolume - gauge.Volume) * math.clamp(dt * 6, 0, 1)
    else
        -- extinction courte et bornee (au plus HEART_FADE s) des que la jauge ne monte plus ou passe sous HEART_START
        gauge.Volume = math.max(gauge.Volume - dt * HEART_VOLUME_MAX / HEART_FADE, targetVolume)
    end
    gauge.PlaybackSpeed += (targetSpeed - gauge.PlaybackSpeed) * math.clamp(dt * 3, 0, 1)
    if gauge.Volume > 0.01 then
        if not gauge.IsPlaying then
            gauge:Play()
        end
    elseif gauge.IsPlaying then
        gauge:Stop()
    end
end

function SoundscapeController:Init(): () end

function SoundscapeController:Start(): ()
    music = makeSound("Musique", SOUNDS.music, true, "Musique")
    tick = makeSound("CompteARebours", SOUNDS.tick, true, "Effets")
    gauge = makeSound("Jauge", SOUNDS.gauge, true, "Effets")
    music:Play()
    TweenService:Create(music, TweenInfo.new(3), { Volume = MUSIC_VOLUME }):Play()

    local roomEvent = Remotes.Get("RoomEvent") :: RemoteEvent
    local trapArmed = Remotes.Get("TrapArmed") :: RemoteEvent
    local giantState = Remotes.Get("GiantState") :: RemoteEvent
    local noiseState = Remotes.Get("NoiseState") :: RemoteEvent

    roomEvent.OnClientEvent:Connect(onRoomEvent)
    trapArmed.OnClientEvent:Connect(function(seconds: number)
        trapEndsAt = Workspace:GetServerTimeNow() + seconds
    end)
    giantState.OnClientEvent:Connect(onGiantState)
    noiseState.OnClientEvent:Connect(onNoise)
    RunService.Heartbeat:Connect(step)

    Players.LocalPlayer.CharacterAdded:Connect(function()
        trapEndsAt = 0
    end)
end

return SoundscapeController
