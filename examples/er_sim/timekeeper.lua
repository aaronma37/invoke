local ffi = require("ffi")
require("gen_wires")

local initialized = false

function tick()
    local q = ffi.cast("er_queue_t*", wire_queue)
    local c = ffi.cast("er_clock_t*", wire_clock)

    if not initialized then
        c.now = 0.0
        c.events_processed = 0
        initialized = true
    end

    if q.count == 0 then return end

    -- Find the soonest event
    local min_time = 9999999999.0
    local min_idx = -1

    for i = 0, q.count - 1 do
        if q.times[i] < min_time then
            min_time = q.times[i]
            min_idx = i
        end
    end

    if min_idx ~= -1 then
        -- TIME JUMP!
        local delta = min_time - c.now
        c.now = min_time
        
        -- We'll let the simulation node know which event to process 
        -- by setting a global or just knowing the current time matches.
    end
end
