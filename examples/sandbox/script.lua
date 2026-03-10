local ffi = require("ffi")

ffi.cdef[[
    typedef struct {
        float x;
        float y;
        int health;
    } Stats;

    typedef struct {
        float force;
        float direction;
    } Wind;
]]

local stats = ffi.cast("Stats*", wire_stats)
local wind = ffi.cast("Wind*", wire_environment_wind)

print("[Player Node] Logic: applying environmental wind force to position")

function tick()
    -- Apply wind force to the X coordinate
    stats.x = stats.x + wind.force
    stats.health = stats.health - 1
end
