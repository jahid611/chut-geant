--!strict

-- Calcul pur du bruit de déplacement. Aucun joueur ni état Roblox : utilisable avec des joueurs simulés.
local NoiseMath = {}

export type Rules = {
    SNEAK_SPEED: number,
    WALK_SPEED: number,
    NOISE_MOVE_INITIAL: number,
    NOISE_MOVE_PER_SECOND: number,
    NOISE_RAMP_START_SECONDS: number,
    NOISE_RAMP_END_SECONDS: number,
    NOISE_RUN_RECOVERY: number,
    NOISE_OTHER_PLAYERS_FACTOR: number,
}

export type Runner = {
    speed: number,
    carriers: number,
    quiet: number,
    fury: number,
    runSeconds: number,
}

-- Primitive de la rampe : le résultat ne dépend pas de la fréquence des Heartbeat.
local function integral(seconds: number, rules: Rules): number
    local rampLength = rules.NOISE_RAMP_END_SECONDS - rules.NOISE_RAMP_START_SECONDS
    local rampTime = math.clamp(seconds - rules.NOISE_RAMP_START_SECONDS, 0, rampLength)
    local plateauTime = math.max(seconds - rules.NOISE_RAMP_END_SECONDS, 0)
    return rules.NOISE_MOVE_INITIAL * seconds
        + (rules.NOISE_MOVE_PER_SECOND - rules.NOISE_MOVE_INITIAL)
            * (rampTime * rampTime / (2 * rampLength) + plateauTime)
end

-- Gain sur dt et durées suivantes, dans l'ordre des entrées ; les entrées ne sont jamais modifiées.
-- Le multiplicateur d'événement s'applique une seule fois, après l'agrégation.
function NoiseMath.Movement(runners: { Runner }, dt: number, rules: Rules, factor: number): (number, { number })
    local total, strongest = 0, 0
    local durations: { number } = {}
    for i, runner in runners do
        local duration = math.clamp(runner.runSeconds, 0, rules.NOISE_RAMP_END_SECONDS)
        local gain = 0
        if runner.speed > rules.SNEAK_SPEED then
            local fraction = math.clamp(
                (runner.speed - rules.SNEAK_SPEED) / math.max(rules.WALK_SPEED - rules.SNEAK_SPEED, 1),
                0,
                1.5
            )
            gain = (integral(duration + dt, rules) - integral(duration, rules))
                * fraction
                * runner.carriers
                * runner.quiet
                * runner.fury
            durations[i] = math.min(duration + dt, rules.NOISE_RAMP_END_SECONDS)
        else
            durations[i] = math.max(duration - dt * rules.NOISE_RUN_RECOVERY, 0)
        end
        total += gain
        strongest = math.max(strongest, gain)
    end
    return (strongest + (total - strongest) * rules.NOISE_OTHER_PLAYERS_FACTOR) * factor, durations
end

return table.freeze(NoiseMath)
