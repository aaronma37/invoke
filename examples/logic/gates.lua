local ffi = require("ffi")

ffi.cdef[[
    typedef struct { int32_t val; } Bit;
]]

function tick()
    -- Dynamically find bound wires
    local inputs = {}
    local output = nil
    
    for k, v in pairs(_G) do
        if k:match("wire_in") then
            table.insert(inputs, ffi.cast("Bit*", v))
        elseif k:match("wire_out") then
            output = ffi.cast("Bit*", v)
        end
    end

    if not output or #inputs == 0 then return end

    -- Logic determined by node name
    local name = "unknown"
    -- Note: In a future ABI version, we'll pass node context directly.
    -- For now, we assume the topology defines the behavior.
    
    -- We'll use a simple global trick or naming convention
    -- But since all gates run in the same VM state per node, 
    -- we can actually just have separate scripts for simplicity.
end
