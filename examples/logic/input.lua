local ffi = require("ffi")
ffi.cdef[[typedef struct { int32_t val; } Bit;]]
function tick()
  local t = os.clock()
  if wire_a then ffi.cast("Bit*", wire_a).val = (math.floor(t * 2) % 2) end
  if wire_b then ffi.cast("Bit*", wire_b).val = (math.floor(t * 1) % 2) end
  if wire_cin then ffi.cast("Bit*", wire_cin).val = (math.floor(t * 0.5) % 2) end
end