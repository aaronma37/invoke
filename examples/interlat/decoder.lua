local ffi = require("ffi")
require("gen_wires")

local vocabulary = {
    [1] = "Tranquility",
    [2] = "Turbulence",
    [3] = "Growth",
    [4] = "Precision"
}

function tick()
    if not wire_latent_thought or not wire_output_stream then return end
    
    local latent = ffi.cast("interlat_latent_thought_t*", wire_latent_thought)
    local output = ffi.cast("interlat_output_stream_t*", wire_output_stream)

    -- 1. Measure the modulated intensity
    local sum = 0
    for i = 0, 127 do sum = sum + latent.vec[i] end
    output.intensity = sum / 128

    -- 2. Decode the ID into a Word
    local word = vocabulary[latent.concept_id] or "Unknown"
    ffi.copy(output.text, word)

    moontide.sleep(100)
end
