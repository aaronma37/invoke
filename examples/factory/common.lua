local ffi = require("ffi")

-- Common Supply Chain structure
ffi.cdef[[
    typedef struct {
        int32_t count;      /* Current items on belt */
        int32_t capacity;   /* Max items on belt */
        float in_rate;      /* Items/frame entering */
        float out_rate;     /* Items/frame exiting */
    } Belt;
]]

return {
    schema = "count:i32;capacity:i32;in_rate:f32;out_rate:f32"
}
