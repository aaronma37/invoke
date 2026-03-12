local ffi = require("ffi")
require("gen_wires")

local initialized = false

function tick()
    local p = ffi.cast("hft_price_stream_t*", wire_price_stream)
    local s = ffi.cast("hft_signal_t*", wire_signal)
    local a = ffi.cast("hft_account_t*", wire_account)

    if not initialized then
        a.cash = 10000.0
        a.position = 0
        initialized = true
    end

    -- Trading Strategy: Trend Following
    if s.trend == 1 and a.cash > p.current_price then
        -- BUY
        a.position = a.position + 1
        a.cash = a.cash - p.current_price
        moontide.log("BUY at " .. p.current_price .. " | Cash: " .. a.cash)
    elseif s.trend == -1 and a.position > 0 then
        -- SELL
        a.position = a.position - 1
        a.cash = a.cash + p.current_price
        moontide.log("SELL at " .. p.current_price .. " | Cash: " .. a.cash)
    end
end
