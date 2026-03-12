local ffi = require("ffi")
require("gen_wires")

local history = {}
local window = 10

function tick()
    local p = ffi.cast("hft_price_stream_t*", wire_price_stream)
    local s = ffi.cast("hft_signal_t*", wire_signal)

    table.insert(history, p.current_price)
    if #history > window then table.remove(history, 1) end

    -- Simple Moving Average
    local sum = 0
    for _, v in ipairs(history) do sum = sum + v end
    s.moving_average = sum / #history

    -- Trend detection
    if p.current_price > s.moving_average then
        s.trend = 1
    else
        s.trend = -1
    end
end
