local ffi = require("ffi")
require("gen_wires")

-- Initialize state on the first tick
local initialized = false

function tick()
    -- Map our local stats wire (the kernel handles the namespace mapping)
    local s = ffi.cast("sim_1_stats_t*", wire_stats) -- Use any sim_t, they are identical
    
    if not initialized then
        s.player_hp = 100.0
        s.boss_hp = 500.0
        s.ticks = 0
        initialized = true
    end

    if s.player_hp <= 0 or s.boss_hp <= 0 then return end

    -- MONTE CARLO ROLLOUT LOGIC
    -- 1. Boss attacks player
    s.player_hp = s.player_hp - (math.random() * 10.0)
    
    -- 2. Player chooses random action (Light vs Heavy attack)
    if math.random() > 0.5 then
        -- Light Attack (Consistent)
        s.boss_hp = s.boss_hp - 15.0
    else
        -- Heavy Attack (High variance)
        s.boss_hp = s.boss_hp - (math.random() * 40.0)
    end

    s.ticks = s.ticks + 1

    -- Use Moontide telemetry to see the parallel worlds
    if s.boss_hp <= 0 then
        moontide.log("VICTORY! Boss down in " .. s.ticks .. " ticks.")
    elseif s.player_hp <= 0 then
        moontide.log("DEFEAT. Player died at tick " .. s.ticks)
    end
end
