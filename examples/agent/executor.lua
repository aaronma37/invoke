local ffi = require("ffi")
require("gen_wires")

function tick()
    if not wire_mailbox or not wire_thought or not wire_outcome then return end

    local mailbox = ffi.cast("agent_mailbox_t*", wire_mailbox)
    local thought = ffi.cast("agent_thought_t*", wire_thought)
    local outcome = ffi.cast("agent_outcome_t*", wire_outcome)

    -- Wait for Planned task (State 1)
    if mailbox.state == 1 then
        if thought.action == 1 then
            -- 1. SUCCESSFUL COMPUTE
            outcome.result = thought.value * 2
            mailbox.state = 2
            moontide.log("Executor: Task " .. mailbox.task_id .. " finished. Result: " .. outcome.result)
        elseif thought.action == 2 then
            -- 2. CHAOS: INTENTIONAL SEGFAULT
            moontide.log("Executor: Task " .. mailbox.task_id .. " triggers CRASH...")
            
            -- Dereference NULL to trigger Hardware Fault
            local crash_ptr = ffi.cast("int*", 0)
            local _ = crash_ptr[0] 
        end
    end
    
    moontide.sleep(100)
end
