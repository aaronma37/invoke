local ffi = require("ffi")
require("gen_wires")

local price = 150.0

function tick()
    local s = ffi.cast("hft_price_stream_t*", wire_price_stream)
    s.last_price = s.current_price
    
    -- Random walk
    price = price + (math.random() * 2.0 - 1.0)
    s.current_price = price
end
