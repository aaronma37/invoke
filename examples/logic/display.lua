local ffi = require("ffi")

ffi.cdef[[
    typedef struct { int32_t val; } Bit;
    typedef struct { unsigned char r; unsigned char g; unsigned char b; unsigned char a; } Color;
    void InitWindow(int width, int height, const char *title);
    void CloseWindow(void);
    bool WindowShouldClose(void);
    void BeginDrawing(void);
    void EndDrawing(void);
    void ClearBackground(Color color);
    void DrawCircle(int posX, int posY, float radius, Color color);
    void DrawText(const char *text, int posX, int posY, int fontSize, Color color);
    void SetTargetFPS(int fps);
]]

local rl = ffi.load("raylib")
local initialized = false

local function draw_led(label, x, y, wire)
    local val = 0
    if wire then val = ffi.cast("Bit*", wire).val end
    
    local color = (val > 0) and ffi.new("Color", {0, 255, 0, 255}) or ffi.new("Color", {50, 50, 50, 255})
    rl.DrawCircle(x, y, 20, color)
    rl.DrawText(label, x - 10, y + 30, 10, ffi.new("Color", {200, 200, 200, 255}))
    rl.DrawText(tostring(val), x - 5, y - 5, 20, ffi.new("Color", {255, 255, 255, 255}))
end

function tick()
    if not initialized then
        rl.InitWindow(600, 400, "Moontide: 1-Bit Full Adder Silicon Emulation")
        rl.SetTargetFPS(60)
        initialized = true
    end

    if rl.WindowShouldClose() then rl.CloseWindow() return end

    rl.BeginDrawing()
    rl.ClearBackground(ffi.new("Color", {15, 15, 15, 255}))

    rl.DrawText("LOGIC BREADBOARD", 20, 20, 20, ffi.new("Color", {255, 255, 255, 255}))

    -- Inputs
    draw_led("IN: A", 100, 150, wire_a)
    draw_led("IN: B", 100, 250, wire_b)
    draw_led("IN: CIN", 200, 200, wire_cin)

    -- Outputs
    draw_led("OUT: SUM", 450, 150, wire_sum)
    draw_led("OUT: COUT", 450, 250, wire_cout)

    rl.EndDrawing()
end
