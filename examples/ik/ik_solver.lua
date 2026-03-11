local ffi = require("ffi")

local segments = 15
ffi.cdef(string.format([[
    typedef struct {
        float x[%d];
        float y[%d];
        float length;
    } ArmWire;
    typedef struct { float x; float y; } MouseWire;
]], segments, segments))

local first_tick = true
local origin_x, origin_y

function init_arm(arm, node_name)
    -- Randomly position the base of the arm
    local id = tonumber(node_name:match("solver_(%d+)")) or 1
    origin_x = 100 + (id * 35)
    origin_y = 550
    arm.length = 25 -- Length of each segment
    
    for i=0, segments-1 do
        arm.x[i] = origin_x
        arm.y[i] = origin_y - (i * arm.length)
    end
    first_tick = false
end

function tick()
    if not wire_mouse then return end
    
    -- Find which arm wire we are bound to (it changes per node instance!)
    local arm_ptr
    for k, v in pairs(_G) do
        if k:match("wire_arm_") then arm_ptr = v break end
    end
    if not arm_ptr then return end

    local arm = ffi.cast("ArmWire*", arm_ptr)
    local mouse = ffi.cast("MouseWire*", wire_mouse)
    local node_name = moontide.name or "solver_1" -- Wait, I need node name

    if first_tick then init_arm(arm, "solver_1") end -- Default fallback

    -- FABRIK ALGORITHM
    local target_x, target_y = mouse.x, mouse.y
    local seg_len = arm.length

    -- 1. Forward Pass (Tip to Base)
    arm.x[segments-1] = target_x
    arm.y[segments-1] = target_y
    for i = segments - 2, 0, -1 do
        local dx = arm.x[i] - arm.x[i+1]
        local dy = arm.y[i] - arm.y[i+1]
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist == 0 then dist = 0.01 end
        arm.x[i] = arm.x[i+1] + (dx / dist) * seg_len
        arm.y[i] = arm.y[i+1] + (dy / dist) * seg_len
    end

    -- 2. Backward Pass (Base to Tip)
    arm.x[0] = origin_x
    arm.y[0] = origin_y
    for i = 1, segments - 1 do
        local dx = arm.x[i] - arm.x[i-1]
        local dy = arm.y[i] - arm.y[i-1]
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist == 0 then dist = 0.01 end
        arm.x[i] = arm.x[i-1] + (dx / dist) * seg_len
        arm.y[i] = arm.y[i-1] + (dy / dist) * seg_len
    end
end
