local ffi = require("ffi")
require("gen_wires")

-- This node will intentionally crash by writing to a NULL pointer
-- to prove the Strike System (Jailing) works.

function tick()
    print("[Crash Node] Tick... about to cause a memory violation!")
    local bad_ptr = ffi.cast("int*", 0)
    bad_ptr[0] = 123
end
