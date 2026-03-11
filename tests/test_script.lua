local ffi = require("ffi")
require("gen_wires")

function tick()
    local w = ffi.cast("test_ns_test_wire_t*", wire_test_wire)
    w.x = 1.0
    w.y = 2.0
    moontide.log("Test Node Ticked!")
    -- poke("test_event") -- We can test poke too
end
