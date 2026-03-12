local ffi = require("ffi")

-- 1. Load the auto-generated FFI headers for our Wires
require("gen_wires")

local initialized = false

function tick()
    -- 2. Cast the raw wire pointer to our struct type EVERY TICK
    -- This ensures we are always pointing to the correct "Back" bank.
    local data = ffi.cast("world_particles_t*", wire_particles)

    -- 3. Initial state (only if count is 0)
    if not initialized and data.count == 0 then
        data.count = 500 -- Start with 500 particles
        for i = 0, data.count - 1 do
            data.x[i] = math.random() * 800
            data.y[i] = math.random() * 600
            data.vx[i] = (math.random() - 0.5) * 4
            data.vy[i] = (math.random() - 0.5) * 4
        end
        initialized = true
        moontide.log("Particles Initialized: " .. data.count)
    end

    -- 4. Physics Loop (The "Stateless" part we can Hot-Reload)
    local centerX, centerY = 400, 300
    local vortexStrength = 0.1
    local friction = 0.98
    
    for i = 0, data.count - 1 do
        -- Calculate vector to center
        local dx = centerX - data.x[i]
        local dy = centerY - data.y[i]
        local dist = math.sqrt(dx*dx + dy*dy) + 0.1
        
        -- Vortex Force: Pull toward center AND push tangent
        data.vx[i] = data.vx[i] + (dx / dist) * vortexStrength + (dy / dist) * 0.5
        data.vy[i] = data.vy[i] + (dy / dist) * vortexStrength - (dx / dist) * 0.5
        
        data.vx[i] = data.vx[i] * friction
        data.vy[i] = data.vy[i] * friction
        
        data.x[i] = data.x[i] + data.vx[i]
        data.y[i] = data.y[i] + data.vy[i]

        -- Bounce off walls (less aggressive)
        if data.x[i] < 0 or data.x[i] > 800 then data.vx[i] = -data.vx[i] end
        if data.y[i] < 0 or data.y[i] > 600 then data.vy[i] = -data.vy[i] end
    end
end
