local ffi = require("ffi")
ffi.cdef[[typedef struct { int32_t val; } Bit;]]
function tick()
  if not wire_in1 or not wire_in2 or not wire_out then return end
  local i1, i2, o = ffi.cast("Bit*", wire_in1), ffi.cast("Bit*", wire_in2), ffi.cast("Bit*", wire_out)
  o.val = (i1.val ~= i2.val) and 1 or 0
end