--!strict

-- Règles pures, communes au serveur et aux tests Lune. Aucun accès au client ni à une sauvegarde.
export type Settings = {
    ROUND_SOLO_GOAL: number,
    ROUND_EXTRA_PLAYER_GOAL: number,
    ROUND_REWARD_CAP: number,
    ROUND_FAILURE_CASH: number,
    ROUND_FAILURE_XP: number,
    ROUND_SUCCESS_CASH: number,
    ROUND_SUCCESS_XP: number,
    ROUND_SUCCESS_CASH_BONUS: number,
    ROUND_SUCCESS_XP_BONUS: number,
}

export type Entry = { userId: number, name: string, count: number, cash: number, xp: number, paid: boolean }
export type State = {
    id: number,
    startsAt: number,
    endsAt: number,
    goal: number,
    total: number,
    closed: boolean,
    won: boolean,
    entries: { [number]: Entry },
}

local RoundRules = {}

function RoundRules.Goal(players: number, tuning: Settings): number
    return tuning.ROUND_SOLO_GOAL + math.max(math.floor(players) - 1, 0) * tuning.ROUND_EXTRA_PLAYER_GOAL
end

function RoundRules.New(id: number, now: number, seconds: number, players: number, tuning: Settings): State
    return {
        id = id,
        startsAt = now,
        endsAt = now + seconds,
        goal = RoundRules.Goal(players, tuning),
        total = 0,
        closed = false,
        won = false,
        entries = {},
    }
end

-- Un signal correspond à un dépôt accepté. Les appels de test sont exclusivement serveur.
function RoundRules.Deposit(
    state: State,
    id: number,
    now: number,
    userId: number,
    name: string,
    source: string?
): boolean
    if state.id ~= id or state.closed or now < state.startsAt or now >= state.endsAt or source ~= "room" then
        return false
    end
    local entry = state.entries[userId]
    if entry == nil then
        entry = { userId = userId, name = name, count = 0, cash = 0, xp = 0, paid = false }
        state.entries[userId] = entry
    end
    entry.name = name
    entry.count += 1
    state.total += 1
    return true
end

function RoundRules.Close(state: State, id: number, now: number): boolean
    if state.id ~= id or state.closed or now < state.endsAt then
        return false
    end
    state.closed = true
    state.won = state.total >= state.goal
    return true
end

function RoundRules.Rank(state: State): { Entry }
    local rows: { Entry } = {}
    for _, entry in state.entries do
        table.insert(rows, entry)
    end
    table.sort(rows, function(a: Entry, b: Entry): boolean
        return if a.count == b.count then a.userId < b.userId else a.count > b.count
    end)
    return rows
end

function RoundRules.Reward(count: number, won: boolean, tuning: Settings): (number, number)
    local c = math.clamp(math.floor(count), 0, tuning.ROUND_REWARD_CAP)
    if c == 0 then
        return 0, 0
    end
    if won then
        return c * tuning.ROUND_SUCCESS_CASH + tuning.ROUND_SUCCESS_CASH_BONUS,
            c * tuning.ROUND_SUCCESS_XP + tuning.ROUND_SUCCESS_XP_BONUS
    end
    return c * tuning.ROUND_FAILURE_CASH, c * tuning.ROUND_FAILURE_XP
end

return table.freeze(RoundRules)
