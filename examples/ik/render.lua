local ffi = require("ffi")

local segments = 15
ffi.cdef(string.format([[
    typedef struct {
        float x[%d];
        float y[%d];
        float length;
    } ArmWire;
    typedef struct { float x; float y; } MouseWire;

    typedef struct { float x; float y; } Vector2;
    typedef struct { unsigned char r; unsigned char g; unsigned char b; unsigned char a; } Color;

    void InitWindow(int width, int height, const char *title);
    void CloseWindow(void);
    bool WindowShouldClose(void);
    void BeginDrawing(void);
    void EndDrawing(void);
    void ClearBackground(Color color);
    void DrawCircleV(Vector2 center, float radius, Color color);
    void DrawLineEx(Vector2 start, Vector2 end, float thick, Color color);
    void SetTargetFPS(int fps);
]], segments, segments))

local rl = ffi.load("raylib")
local initialized = false

function tick()
    if not initialized then
        rl.InitWindow(800, 600, "Moontide: Inverse Kinematics Swarm")
        rl.SetTargetFPS(60)
        initialized = true
    end

    if rl.WindowShouldClose() then
        rl.CloseWindow()
        return
    end

    rl.BeginDrawing()
    rl.ClearBackground(ffi.new("Color", {20, 20, 25, 255}))

    -- Draw all arms
    for k, v in pairs(_G) do
        if k:match("wire_arm_") then
            local arm = ffi.cast("ArmWire*", v)
            local id = tonumber(k:match("wire_arm_(%d+)")) or 1
            local hue = (id * 18) % 360
            -- Procedural color based on arm ID
            local color = ffi.new("Color", {100, 150 + (id * 5), 255 - (id * 5), 255})

            for i = 0, segments - 2 do
                rl.DrawLineEx(
                    ffi.new("Vector2", arm.x[i], arm.y[i]),
                    ffi.new("Vector2", arm.x[i+1], arm.y[i+1]),
                    math.max(1, 10 - i), -- Tapered thickness
                    color
                )
            end
            -- Draw Joint
            rl.DrawCircleV(ffi.new("Vector2", arm.x[segments-1], arm.y[segments-1]), 5, color)
        end
    end

    -- Draw target
    if wire_mouse then
        local mouse = ffi.cast("MouseWire*", wire_mouse)
        rl.DrawCircleV(ffi.new("Vector2", mouse.x, mouse.y), 10, ffi.new("Color", {255, 255, 255, 100}))
    end

    rl.EndDrawing()
end
