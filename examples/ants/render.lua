local ffi = require("ffi")
local common = require("examples/ants/common")

ffi.cdef[[
    typedef struct { unsigned char r; unsigned char g; unsigned char b; unsigned char a; } Color;
    void InitWindow(int width, int height, const char *title);
    void CloseWindow(void);
    bool WindowShouldClose(void);
    void BeginDrawing(void);
    void EndDrawing(void);
    void ClearBackground(Color color);
    void DrawRectangle(int posX, int posY, int width, int height, Color color);
    void SetTargetFPS(int fps);
]]

local rl = ffi.load("raylib")
local initialized = false
local dim = common.grid_dim

local colors = {
    bg = ffi.new("Color", {10, 10, 15, 255}),
    cell = ffi.new("Color", {0, 255, 100, 255}),
    text = ffi.new("Color", {255, 255, 255, 255})
}

function tick()
    if not wire_grid then return end
    local grid = ffi.cast("Grid*", wire_grid)

    if not initialized then
        rl.InitWindow(dim * 3, dim * 3, "Moontide: Langton's Ant Multiverse")
        rl.SetTargetFPS(60)
        initialized = true
    end

    if rl.WindowShouldClose() then rl.CloseWindow() return end

    rl.BeginDrawing()
    rl.ClearBackground(colors.bg)

    for y = 0, dim - 1 do
        for x = 0, dim - 1 do
            if grid.cells[y * dim + x] == 1 then
                rl.DrawRectangle(x * 3, y * 3, 3, 3, colors.cell)
            end
        end
    end

    rl.EndDrawing()
end
