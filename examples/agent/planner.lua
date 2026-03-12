local ffi = require("ffi")
require("gen_wires")

function tick()
    if not wire_mailbox or not wire_thought or not wire_outcome then return end

    local mailbox = ffi.cast("agent_mailbox_t*", wire_mailbox)
    local thought = ffi.cast("agent_thought_t*", wire_thought)
    
    -- 1. If mailbox is empty (state 2 or 0 with ID 0), create a new task
    if mailbox.state == 2 or (mailbox.task_id == 0) then
        mailbox.task_id = mailbox.task_id + 1
        mailbox.state = 0
        
        -- Randomly decide to be "Dangerous"
        if math.random() > 0.7 then
            ffi.copy(mailbox.cmd, "CHAOS_CRASH")
            moontide.log("Planner: Sent dangerous task CHAOS_CRASH")
        else
            ffi.copy(mailbox.cmd, "COMPUTE_STUFF")
            moontide.log("Planner: Sent safe task COMPUTE_STUFF")
        end
    end

    -- 2. Process NEW tasks (State 0 -> 1)
    if mailbox.state == 0 then
        local cmd = ffi.string(mailbox.cmd)
        if cmd == "CHAOS_CRASH" then
            thought.action = 2 -- Chaos
            thought.value = 999
        else
            thought.action = 1 -- Compute
            thought.value = math.random(1, 100)
        end
        mailbox.state = 1
        moontide.log("Planner: Task " .. mailbox.task_id .. " planned.")
    end
    
    moontide.sleep(500) -- Slower for visibility
end
