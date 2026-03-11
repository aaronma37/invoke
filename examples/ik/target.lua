local ffi = require("ffi")

ffi.cdef[[
    typedef struct { float x; float y; } Vector2;
    Vector2 GetMousePosition(void);
    bool IsWindowReady(void);

    typedef struct { float x; float y; } MouseWire;
]]

function tick()
    if not wire_mouse then return end
    local mouse = ffi.cast("MouseWire*", wire_mouse)
    
    -- We can only poll mouse if Raylib is up
    local rl = ffi.load("raylib")
    if rl.IsWindowReady() then
        local pos = rl.GetMousePosition()
        mouse.x = pos.x
        mouse.y = pos.y
    else
        -- Fallback: circle pattern
        local t = os.clock()
        mouse.x = 400 + math.cos(t) * 200
        mouse.y = 300 + math.sin(t) * 200
    end
end
