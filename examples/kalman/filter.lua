local ffi = require("ffi")

ffi.cdef[[
    typedef struct {
        float true_x;
        float measured;
        float t;
    } RawSignal;

    typedef struct {
        float value;
    } FilteredSignal;

    typedef struct {
        float p; /* covariance */
        float q; /* process noise */
        float r; /* measurement noise */
        float k; /* kalman gain */
    } State;
]]

-- Initialize the filter
local first_tick = true
function init_filter(raw, fil, st)
    st.p = 1.0
    st.q = 0.01
    st.r = 30 * 30
    st.k = 0.0
    fil.value = raw.measured
    first_tick = false
end

function tick()
    if not wire_raw_signal or not wire_filtered_signal or not wire_state then return end
    
    local raw = ffi.cast("RawSignal*", wire_raw_signal)
    local fil = ffi.cast("FilteredSignal*", wire_filtered_signal)
    local st = ffi.cast("State*", wire_state)
    
    if first_tick then init_filter(raw, fil, st) end

    -- 1. PREDICT
    st.p = st.p + st.q

    -- 2. UPDATE (Correction)
    st.k = st.p / (st.p + st.r)
    fil.value = fil.value + st.k * (raw.measured - fil.value)
    st.p = (1 - st.k) * st.p
end
