local ffi = require("ffi")
require("gen_wires")

-- This node will intentionally enter an INFINITE LOOP
-- to prove the Execution Watchdog can kill stalled nodes.

function tick()
    print("[Stall Node] Tick... entering infinite loop now!")
    local i = 0
    while true do
        i = i + 1
        -- This will never end, but the Watchdog should kill it in 100ms
    end
end
