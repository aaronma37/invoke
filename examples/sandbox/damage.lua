local ffi = require("ffi")
require("gen_wires")

local stats = ffi.cast("player_stats_t*", wire_stats)

print("[Damage Node] Triggered! Checking for memory violations...")

function tick()
    stats.health = stats.health - 10
    
    -- CRASH TEST (Uncomment to test Indestructible Host):
    -- This write is out-of-bounds and should be caught by the Silicon Gate.
    -- stats[1000].health = 999 
end
