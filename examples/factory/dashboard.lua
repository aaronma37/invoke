local ffi = require("ffi")
require("examples/factory/common")

ffi.cdef[[
    typedef struct { float x; float y; } Vector2;
    typedef struct { unsigned char r; unsigned char g; unsigned char b; unsigned char a; } Color;
    void InitWindow(int width, int height, const char *title);
    void CloseWindow(void);
    bool WindowShouldClose(void);
    void BeginDrawing(void);
    void EndDrawing(void);
    void ClearBackground(Color color);
    void DrawRectangle(int posX, int posY, int width, int height, Color color);
    void DrawRectangleLines(int posX, int posY, int width, int height, Color color);
    void DrawText(const char *text, int posX, int posY, int fontSize, Color color);
    void SetTargetFPS(int fps);
]]

local rl = ffi.load("raylib")
local initialized = false

local function draw_belt(label, x, y, wire)
    if not wire then return end
    local belt = ffi.cast("Belt*", wire)
    
    local w = 200
    local h = 40
    
    -- Outline
    rl.DrawRectangleLines(x, y, w, h, ffi.new("Color", {100, 100, 100, 255}))
    
    -- Fill based on count
    local fill_w = (belt.count / belt.capacity) * w
    rl.DrawRectangle(x, y, fill_w, h, ffi.new("Color", {0, 150, 255, 150}))
    
    -- Stats
    rl.DrawText(label, x, y - 15, 10, ffi.new("Color", {255, 255, 255, 255}))
    rl.DrawText(string.format("%d / %d", belt.count, belt.capacity), x + 5, y + 10, 20, ffi.new("Color", {255, 255, 255, 255}))
    rl.DrawText(string.format("In: %.2f | Out: %.2f", belt.in_rate, belt.out_rate), x, y + h + 5, 10, ffi.new("Color", {150, 150, 150, 255}))
end

function tick()
    if not initialized then
        rl.InitWindow(800, 600, "Moontide: Factory Supply Chain Dashboard")
        rl.SetTargetFPS(60)
        initialized = true
    end

    if rl.WindowShouldClose() then rl.CloseWindow() return end

    rl.BeginDrawing()
    rl.ClearBackground(ffi.new("Color", {20, 20, 20, 255}))

    rl.DrawText("FACTORY LOGISTICS", 20, 20, 20, ffi.new("Color", {255, 255, 255, 255}))

    -- Row 1: Raw Ores
    draw_belt("IRON ORE BELT", 50, 100, wire_iron_ore)
    draw_belt("COPPER ORE BELT", 300, 100, wire_copper_ore)
    draw_belt("COAL BELT", 550, 100, wire_coal)

    -- Row 2: Refined Ingots
    draw_belt("IRON INGOT BELT", 50, 300, wire_iron_ingot)
    draw_belt("COPPER WIRE BELT", 300, 300, wire_copper_wire)

    -- Row 3: Final Product
    draw_belt("CIRCUIT BOARD BELT", 300, 500, wire_circuit)

    rl.EndDrawing()
end
