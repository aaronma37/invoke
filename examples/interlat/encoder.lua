local ffi = require("ffi")
require("gen_wires")

local concepts = {
    [1] = "PEACE",
    [2] = "CHAOS",
    [3] = "NATURE",
    [4] = "TECH"
}

local start_time = os.time()

function tick()
    if not wire_latent_thought then return end
    local latent = ffi.cast("interlat_latent_thought_t*", wire_latent_thought)

    -- Cycle concept every 2 seconds
    local elapsed = os.time() - start_time
    local id = (math.floor(elapsed / 2) % 4) + 1
    
    latent.concept_id = id
    
    -- Fill latent vector with signature noise
    for i = 0, 127 do
        -- Base value derived from ID + random jitters
        latent.vec[i] = (id * 0.2) + (math.random() * 0.1)
    end

    moontide.sleep(100)
end
