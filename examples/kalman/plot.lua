local ffi = require("ffi")

-- Standard Signal Schema
ffi.cdef[[
    typedef struct {
        float true_x;
        float measured;
        float t;
    } RawSignal;

    typedef struct {
        float value;
    } FilteredSignal;

    typedef struct { float x; float y; } Vector2;
    typedef struct { unsigned char r; unsigned char g; unsigned char b; unsigned char a; } Color;

    void InitWindow(int width, int height, const char *title);
    void CloseWindow(void);
    bool WindowShouldClose(void);
    void BeginDrawing(void);
    void EndDrawing(void);
    void ClearBackground(Color color);
    void DrawLineV(Vector2 start, Vector2 end, Color color);
    void DrawText(const char *text, int posX, int posY, int fontSize, Color color);
    void SetTargetFPS(int fps);
]]

local rl = ffi.load("raylib")

local width = 800
local height = 600
local history = {}
local max_history = 800

local colors = {
    bg = ffi.new("Color", {24, 24, 24, 255}),
    ground = ffi.new("Color", {0, 255, 0, 255}),    -- Green
    measured = ffi.new("Color", {255, 0, 0, 100}), -- Faded Red
    filtered = ffi.new("Color", {0, 200, 255, 255}) -- Cyan
}

local initialized = false
function tick()
    -- RE-CAST EVERY TICK
    if not wire_raw_signal or not wire_filtered_signal then return end
    local raw = ffi.cast("RawSignal*", wire_raw_signal)
    local fil = ffi.cast("FilteredSignal*", wire_filtered_signal)

    if not initialized then
        print("[Plotter] Initializing Raylib window...")
        rl.InitWindow(width, height, "Invoke: Kalman Filter Signal Analysis")
        rl.SetTargetFPS(60)
        initialized = true
    end

    if rl.WindowShouldClose() then
        rl.CloseWindow()
        return
    end

    -- Update history
    table.insert(history, {
        true_x = raw.true_x,
        measured = raw.measured,
        filtered = fil.value
    })
    if #history > max_history then table.remove(history, 1) end

    if #history % 100 == 0 then
        print("[Plotter] History size: " .. #history .. " | Latest Measured: " .. raw.measured)
    end

    rl.BeginDrawing()
    rl.ClearBackground(colors.bg)

    local mid_y = height / 2

    for i = 2, #history do
        local x1 = i - 1
        local x2 = i
        
        -- Draw Measured (Noisy)
        rl.DrawLineV(
            ffi.new("Vector2", x1, mid_y + history[i-1].measured),
            ffi.new("Vector2", x2, mid_y + history[i].measured),
            colors.measured
        )

        -- Draw Ground Truth
        rl.DrawLineV(
            ffi.new("Vector2", x1, mid_y + history[i-1].true_x),
            ffi.new("Vector2", x2, mid_y + history[i].true_x),
            colors.ground
        )

        -- Draw Filtered (Kalman)
        rl.DrawLineV(
            ffi.new("Vector2", x1, mid_y + history[i-1].filtered),
            ffi.new("Vector2", x2, mid_y + history[i].filtered),
            colors.filtered
        )
    end

    rl.DrawText("KALMAN FILTER ANALYSIS", 20, 20, 20, ffi.new("Color", {255, 255, 255, 255}))
    rl.DrawText("GREEN: GROUND TRUTH", 20, 50, 10, colors.ground)
    rl.DrawText("RED: MEASURED (NOISE)", 20, 65, 10, colors.measured)
    rl.DrawText("CYAN: FILTERED (KALMAN)", 20, 80, 10, colors.filtered)

    rl.EndDrawing()
end
