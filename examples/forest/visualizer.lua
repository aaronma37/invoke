local ffi = require("ffi")
local batch_size = 20000

ffi.cdef(string.format([[
    typedef struct { float x[%d]; float y[%d]; } Batch;
    typedef struct { int32_t class[%d]; } Pred;

    typedef struct { unsigned char r; unsigned char g; unsigned char b; unsigned char a; } Color;
    void InitWindow(int width, int height, const char *title);
    void CloseWindow(void);
    bool WindowShouldClose(void);
    void BeginDrawing(void);
    void EndDrawing(void);
    void DrawRectangle(int posX, int posY, int width, int height, Color color);
    void DrawText(const char *text, int posX, int posY, int fontSize, Color color);
    void SetTargetFPS(int fps);
    void ClearBackground(Color color);
]], batch_size, batch_size, batch_size))

local rl = ffi.load("raylib")
local initialized = false

local color0 = ffi.new("Color", {255, 50, 50, 255})
local color1 = ffi.new("Color", {50, 150, 255, 255})
local bg_color = ffi.new("Color", {15, 15, 20, 255})
local text_color = ffi.new("Color", {255, 255, 255, 255})

function tick()
    if not wire_batch or not wire_final_pred then return end
    
    local b = ffi.cast("Batch*", wire_batch)
    local p = ffi.cast("Pred*", wire_final_pred)

    if not initialized then
        rl.InitWindow(800, 600, "Moontide: Random Forest Procedural Art")
        rl.SetTargetFPS(60)
        initialized = true
    end

    if rl.WindowShouldClose() then rl.CloseWindow() return end

    rl.BeginDrawing()
    rl.ClearBackground(bg_color)

    for i = 0, batch_size - 1 do
        local color = p.class[i] == 1 and color1 or color0
        rl.DrawRectangle(b.x[i], b.y[i], 3, 3, color)
    end

    rl.DrawText("RANDOM FOREST ENSEMBLE (8 TREES)", 20, 20, 20, text_color)
    rl.DrawText(string.format("Processing %d points/frame", batch_size), 20, 45, 10, text_color)

    rl.EndDrawing()
end
