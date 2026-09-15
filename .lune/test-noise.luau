--!strict

-- `lune run test-noise` : mêmes fonctions et réglages que le serveur, sans simuler Humanoid:Move.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local NoiseMath = require("../src/shared/NoiseMath")
local tuning = luau.load(fs.readFile("src/shared/Tuning.luau"), {
    environment = { Vector3 = roblox.Vector3, Color3 = roblox.Color3 },
})()

local function near(actual: number, expected: number): ()
    assert(math.abs(actual - expected) < 0.00001, string.format("%.8f attendu, %.8f obtenu", expected, actual))
end

local function runner(speed: number?, duration: number?): NoiseMath.Runner
    return { speed = speed or 17, carriers = 1, quiet = 1, fury = 1, runSeconds = duration or 0 }
end

near(NoiseMath.Movement({ runner() }, 3, tuning, 1), 24)
near(NoiseMath.Movement({ runner() }, 8, tuning, 1), 76.5)
near(NoiseMath.Movement({ runner(17, 8) }, 1, tuning, 1), 13)
near(NoiseMath.Movement({ runner(9.5) }, 3, tuning, 1), 0)
near(NoiseMath.Movement({ runner(13.25) }, 3, tuning, 1), 12)
near(NoiseMath.Movement({ runner(), runner(), runner() }, 3, tuning, 1), 48)
near(NoiseMath.Movement({ runner(), runner(), runner() }, 3, tuning, 2), 96)
near(NoiseMath.Movement({ runner(), runner(), runner() }, 3, tuning, 0), 0)

local fury = runner(44)
fury.fury = tuning.FURY_NOISE_MULTIPLIER
near(NoiseMath.Movement({ fury }, 3, tuning, 1), 43.2)
local heavy = runner()
heavy.carriers, heavy.quiet = 3, 0.5
near(NoiseMath.Movement({ heavy }, 3, tuning, 1), 36)
-- La plus forte contribution est entière, même si elle arrive en dernier.
near(NoiseMath.Movement({ runner(), heavy }, 3, tuning, 1), 48)
near(NoiseMath.Movement({ heavy, runner() }, 3, tuning, 1), 48)

local _, recovered = NoiseMath.Movement({ runner(0, 8) }, 0.1, tuning, 1)
near(recovered[1], 7.8)
local gainAfterPause = NoiseMath.Movement({ runner(17, recovered[1]) }, 0.1, tuning, 1)
assert(gainAfterPause > 1.28, "Un micro-arrêt ne doit pas remettre la rampe à zéro")
local _, rested = NoiseMath.Movement({ runner(0, 8) }, 4, tuning, 1)
near(rested[1], 0)
near(heavy.runSeconds, 0) -- le calcul ne modifie pas les entrées

local function integrate(step: number): number
    local sample = runner()
    local sum = 0
    for _ = 1, math.round(10 / step) do
        local gain, durations = NoiseMath.Movement({ sample }, step, tuning, 1)
        sum += gain
        sample.runSeconds = durations[1]
    end
    return sum
end
near(integrate(1 / 60), 102.5)
near(integrate(0.1), 102.5)
near(integrate(1), 102.5)

-- Mesures comparables : pleine vitesse sans équipement ni événement ; ancienne décroissance au calme = 5/s.
local function measure(count: number, old: boolean, burst: boolean): (number, number)
    local samples: { NoiseMath.Runner } = {}
    for _ = 1, count do
        table.insert(samples, runner())
    end
    local level, peak, firstFull = 0, 0, 0
    local dt = 0.01
    for tick = 1, 1200 do
        local moving = not burst or (tick - 1) % 600 < 300
        for _, sample in samples do
            sample.speed = if moving then 17 else 0
        end
        local gain, durations = NoiseMath.Movement(samples, dt, tuning, 1)
        for i, sample in samples do
            sample.runSeconds = durations[i]
        end
        if old then
            gain = if moving then 13 * count * dt else 0
        end
        local decay = if old then 5 else tuning.NOISE_DECAY_PER_SECOND
        level = math.clamp(level + (if gain > 0 then gain else -decay * dt), 0, 100)
        peak = math.max(peak, level)
        if level >= 100 and firstFull == 0 then
            firstFull = tick * dt
        end
    end
    return peak, firstFull
end

for _, count in { 1, 3 } do
    for _, old in { true, false } do
        local peak, full = measure(count, old, false)
        print(
            string.format(
                "%d joueur(s), %s, course continue : pic %.1f, plein à %.2f s",
                count,
                if old then "avant" else "après",
                peak,
                full
            )
        )
        local burstPeak = measure(count, old, true)
        print(
            string.format(
                "%d joueur(s), %s, 3 s marche / 3 s calme sur 12 s : pic %.1f",
                count,
                if old then "avant" else "après",
                burstPeak
            )
        )
    end
end

assert(tuning.RESPAWN_SECONDS == 8 and tuning.KITCHEN_RESPAWN_SECONDS == 20)
assert(tuning.WELCOME_RESPAWN_SECONDS == 25)
assert(tuning.DOG_NOISE_MOVE_PER_SECOND == 13)
assert(tuning.FURY_SECONDS == 3 and tuning.FURY_COOLDOWN == 20 and tuning.FURY_PRICE == 750)
print(
    "Bruit : assertions réussies (rampe, récupération, agrégation, équipement, Furie, événements, pas de temps)."
)
