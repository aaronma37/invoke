local ffi = require("ffi")
require("examples/factory/common")

local first_tick = true
local rate = 0.5 -- Base mining speed

function tick()
    if not wire_output then return end
    local belt = ffi.cast("Belt*", wire_output)
    
    if first_tick then
        belt.capacity = 100
        first_tick = false
    end

    if belt.count < belt.capacity then
        belt.count = belt.count + 1
        belt.in_rate = rate
    else
        belt.in_rate = 0
    end
end
