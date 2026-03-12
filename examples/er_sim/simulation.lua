local ffi = require("ffi")
require("gen_wires")

local initialized = false

function add_event(q, time, type)
    if q.count >= 100 then return end
    q.times[q.count] = time
    q.types[q.count] = type
    q.count = q.count + 1
end

function tick()
    local q = ffi.cast("er_queue_t*", wire_queue)
    local c = ffi.cast("er_clock_t*", wire_clock)

    if not initialized then
        -- Schedule the first patient arrival
        add_event(q, 10.0, 1) -- Arrival at T=10
        initialized = true
        return
    end

    -- Process all events happening at 'now'
    local i = 0
    while i < q.count do
        if q.times[i] <= c.now then
            local event_type = q.types[i]
            
            -- REMOVE EVENT (Swap with last)
            q.times[i] = q.times[q.count-1]
            q.types[i] = q.types[q.count-1]
            q.count = q.count - 1
            
            c.events_processed = c.events_processed + 1

            if event_type == 1 then
                moontide.log("[T=" .. c.now .. "] Patient ARRIVED. Scheduling Triage...")
                add_event(q, c.now + 5.0, 2) -- Triage takes 5 mins
                
                -- Schedule NEXT patient arrival randomly
                add_event(q, c.now + (math.random() * 30.0), 1)
            elseif event_type == 2 then
                moontide.log("[T=" .. c.now .. "] Triage FINISHED. Scheduling Doctor...")
                add_event(q, c.now + 20.0, 3) -- Doctor takes 20 mins
            elseif event_type == 3 then
                moontide.log("[T=" .. c.now .. "] Patient DISCHARGED. Bed is free.")
            end
        else
            i = i + 1
        end
    end
end
