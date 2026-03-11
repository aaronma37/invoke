local ffi = require("ffi")

-- Grid is 256x256
local grid_dim = 256
local grid_size = grid_dim * grid_dim

ffi.cdef(string.format([[
    typedef struct {
        uint8_t cells[%d];
    } Grid;

    typedef struct {
        int32_t x;
        int32_t y;
        int32_t dir; /* 0: Up, 1: Right, 2: Down, 3: Left */
    } AntState;
]], grid_size))

return {
    grid_dim = grid_dim,
    grid_size = grid_size,
    grid_schema = string.format("cells:u8[%d]", grid_size),
    ant_schema = "x:i32;y:i32;dir:i32"
}
