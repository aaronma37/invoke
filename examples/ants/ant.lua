local ffi = require("ffi")
local common = require("examples/ants/common")

local first_tick = true
local dim = common.grid_dim

function tick()
    -- wire_past: Front Buffer (Read-only)
    -- wire_future: Back Buffer (Write-only)
    if not wire_past or not wire_future or not wire_state then return end
    
    local past = ffi.cast("Grid*", wire_past)
    local future = ffi.cast("Grid*", wire_future)
    local ant = ffi.cast("AntState*", wire_state)

    if first_tick then
        ant.x = math.random(0, dim - 1)
        ant.y = math.random(0, dim - 1)
        ant.dir = math.random(0, 3)
        first_tick = false
    end

    -- Langton's Ant Rules:
    -- 1. Read cell color from PAST (Front Buffer)
    local idx = ant.y * dim + ant.x
    local color = past.cells[idx]

    -- 2. Change direction
    if color == 0 then
        ant.dir = (ant.dir + 1) % 4 -- Turn Right
    else
        ant.dir = (ant.dir - 1) % 4 -- Turn Left
        if ant.dir < 0 then ant.dir = 3 end
    end

    -- 3. Flip color in FUTURE (Back Buffer)
    future.cells[idx] = (color == 0) and 1 or 0

    -- 4. Move forward
    if ant.dir == 0 then ant.y = ant.y - 1
    elseif ant.dir == 1 then ant.x = ant.x + 1
    elseif ant.dir == 2 then ant.y = ant.y + 1
    elseif ant.dir == 3 then ant.x = ant.x - 1
    end

    -- Wrap around
    ant.x = (ant.x + dim) % dim
    ant.y = (ant.y + dim) % dim
end
