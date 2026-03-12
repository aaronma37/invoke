local ffi = require("ffi")
require("gen_wires")

local style_factor = 1.5 -- Can be hot-reloaded!

function tick()
    if not wire_latent_thought then return end
    local latent = ffi.cast("interlat_latent_thought_t*", wire_latent_thought)

    -- "Steer" the latent space by amplifying certain signals
    for i = 0, 127 do
        latent.vec[i] = latent.vec[i] * style_factor
    end

    moontide.sleep(100)
end
