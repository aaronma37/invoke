local ffi = require("ffi")
require("gen_wires")

function tick()
    -- wire_test_wire is now a TABLE of pointers (SOA View)
    -- provided by the luajit extension.
    wire_test_wire.x[0] = 1.0
    wire_test_wire.y[0] = 2.0
    moontide.log("Test Node Ticked!")
end
