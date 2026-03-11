local ffi = require("ffi")
require("examples/factory/common")

local progress = 0
local process_time = 120 -- complex items take longer

function tick()
    if not wire_in_a or not wire_in_b or not wire_output then return end
    local src_a = ffi.cast("Belt*", wire_in_a)
    local src_b = ffi.cast("Belt*", wire_in_b)
    local dst = ffi.cast("Belt*", wire_output)

    -- Consumes 1 of A and 1 of B to produce 1 complex item
    if src_a.count > 0 and src_b.count > 0 and dst.count < dst.capacity then
        progress = progress + 1
        if progress >= process_time then
            src_a.count = src_a.count - 1
            src_b.count = src_b.count - 1
            dst.count = dst.count + 1
            progress = 0
        end
        src_a.out_rate = 1.0 / process_time
        src_b.out_rate = 1.0 / process_time
        dst.in_rate = 1.0 / process_time
    else
        src_a.out_rate = 0
        src_b.out_rate = 0
        dst.in_rate = 0
    end
end
