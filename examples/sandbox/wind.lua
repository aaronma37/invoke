local ffi = require("ffi")
require("gen_wires")

local wind = ffi.cast("environment_wind_t*", wire_wind)
local timer = 0

print("[Wind Node] Generating dynamic weather pattern...")

function tick()
    timer = timer + 0.1
    -- Oscillate wind force between -2.0 and 2.0
    wind.force = math.sin(timer) * 2.0
    wind.direction = 1.0
end
