--!strict

--[[
    check
    Verification complete du depot, hors Studio. `lune run check`

    Enchaine sourcemap, linter, format et analyse de types, et s'arrete
    au premier echec avec le bon code de sortie (utilisable en CI).
]]

local process = require("@lune/process")
local stdio = require("@lune/stdio")

type Step = {
    name: string,
    program: string,
    args: { string },
}

local STEPS: { Step } = {
    {
        name = "sourcemap",
        program = "rojo",
        args = { "sourcemap", "default.project.json", "-o", "sourcemap.json" },
    },
    {
        name = "selene",
        program = "selene",
        args = { "src" },
    },
    {
        name = "stylua",
        program = "stylua",
        args = { "--check", "src", ".lune" },
    },
    {
        name = "luau-lsp",
        program = "luau-lsp",
        args = {
            "analyze",
            "--sourcemap=sourcemap.json",
            "--definitions=globalTypes.d.luau",
            "--base-luaurc=.luaurc",
            "--settings=.luau-analyze.json",
            "--ignore=**/_Index/**",
            -- Code tiers vendore : on ne le corrige pas, on ne l analyse pas.
            "--ignore=**/Vendor/**",
            "src",
        },
    },
}

local function run(step: Step): boolean
    stdio.write(string.format("%s %s ... ", stdio.color("blue"), step.name))
    stdio.write(stdio.color("reset"))

    local result = process.exec(step.program, step.args, { stdio = "default" })
    if result.ok then
        stdio.write(stdio.color("green") .. "ok\n" .. stdio.color("reset"))
        return true
    end

    stdio.write(stdio.color("red") .. "echec\n" .. stdio.color("reset"))
    if #result.stdout > 0 then
        stdio.write(result.stdout)
    end
    if #result.stderr > 0 then
        stdio.write(result.stderr)
    end
    return false
end

for _, step in STEPS do
    if not run(step) then
        process.exit(1)
    end
end

stdio.write(stdio.color("green") .. "\nTout est vert.\n" .. stdio.color("reset"))
