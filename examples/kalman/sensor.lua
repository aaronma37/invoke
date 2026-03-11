local ffi = require("ffi")

ffi.cdef[[
    typedef struct {
        float true_x;
        float measured;
        float t;
    } RawSignal;
]]

-- Box-Muller transform for Gaussian noise
local function box_muller()
    local u1 = math.random()
    if u1 == 0 then u1 = 1e-9 end
    local u2 = math.random()
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

function tick()
    if not wire_raw_signal then return end
    local sig = ffi.cast("RawSignal*", wire_raw_signal)

    sig.t = sig.t + 0.05
    -- Ground Truth: Smooth Sine Wave
    sig.true_x = 100 * math.sin(sig.t)
    -- Add Heavy Noise (standard deviation = 30)
    local noise = box_muller() * 30
    sig.measured = sig.true_x + noise
end
