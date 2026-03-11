local ffi = require("ffi")
require("examples/factory/common")

local progress = 0
local process_time = 30 -- frames per ingot

function tick()
    if not wire_input or not wire_output then return end
    local src = ffi.cast("Belt*", wire_input)
    local dst = ffi.cast("Belt*", wire_output)

    if src.count > 0 and dst.count < dst.capacity then
        progress = progress + 1
        if progress >= process_time then
            src.count = src.count - 1
            dst.count = dst.count + 1
            progress = 0
        end
        src.out_rate = 1.0 / process_time
        dst.in_rate = 1.0 / process_time
    else
        src.out_rate = 0
        dst.in_rate = 0
    end
end
