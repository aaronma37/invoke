local ffi = require("ffi")
local batch_size = 20000
ffi.cdef(string.format([[
    typedef struct { float x[%d]; float y[%d]; } Batch;
]], batch_size, batch_size))

function tick()
    if not wire_batch then return end
    local b = ffi.cast("Batch*", wire_batch)
    for i = 0, batch_size - 1 do
        b.x[i] = math.random() * 800
        b.y[i] = math.random() * 600
    end
end
