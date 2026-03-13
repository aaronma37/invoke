local ffi = require("ffi")

-- 1. Load the auto-generated FFI headers for our Wires
require("gen_wires")

local initialized = false

function tick()
    -- 2. Cast the raw wire pointer to our struct type EVERY TICK
    local data = ffi.cast("world_particles_t*", wire_particles)
    local journal = ffi.cast("journal_config_t*", wire_journal_config)
    local audio_play = ffi.cast("audio_play_t*", wire_audio_play)
    local audio_load = ffi.cast("audio_load_t*", wire_audio_load)

    -- 3. Initialize config and state
    if not initialized then
        -- Set journal to save every 2 seconds
        journal.interval_ms = 2000
        
        -- Request sound loading (ID 1)
        local path = "examples/particles/hit.wav"
        ffi.copy(audio_load.path[0], path)
        
        if data.count == 0 then
            data.count = 500 -- Start with 500 particles
            for i = 0, data.count - 1 do
                data.x[i] = math.random() * 800
                data.y[i] = math.random() * 600
                data.vx[i] = (math.random() - 0.5) * 4
                data.vy[i] = (math.random() - 0.5) * 4
            end
        end
        
        initialized = true
        moontide.log("Particles, Journal & Audio Initialized.")
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
        local hit = false
        if data.x[i] < 0 or data.x[i] > 800 then 
            data.vx[i] = -data.vx[i] 
            hit = true
        end
        if data.y[i] < 0 or data.y[i] > 600 then 
            data.vy[i] = -data.vy[i] 
            hit = true
        end

        -- 5. Audio "Poke" on Hit
        if hit and math.random() < 0.05 then -- 5% chance to play sound on hit to avoid spam
            -- Find empty slot in audio play queue
            for slot = 0, 15 do
                if audio_play.id[slot] == 0 then
                    audio_play.id[slot] = 1 -- Play Sound ID 1
                    audio_play.volume[slot] = 0.5
                    audio_play.pitch[slot] = 0.8 + math.random() * 0.4
                    break
                end
            end
        end
    end
end
