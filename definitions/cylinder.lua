-- Primitive Definition: Cylinder
-- A procedural mapping from (u, v, z) -> (x, y, z, c)

return {
    name = "cylinder",
    
    -- Sockets define the canonical interfaces
    sockets = {
        bottom = { edge = "v", value = 0.0 },
        top    = { edge = "v", value = 1.0 }
    },

    -- The "Ground Truth" function for The Forge
    evaluate = function(u, v, z)
        -- Latent vector Z controls physical proportions
        local radius = z[1] or 0.5
        local height = z[2] or 1.0
        
        -- Angle wraps around U [0, 1]
        local angle = u * math.pi * 2
        
        -- Physical Coordinates
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        local z_pos = v * height
        
        -- Semantic Channels
        -- C1: Branch Potential (Highest at the top rim)
        local c1 = (v > 0.95) and 1.0 or 0.0
        
        -- C2: Structural Integrity (Rigid at the bottom)
        local c2 = (v < 0.05) and 1.0 or 0.0

        return x, y, z_pos, c1, c2
    end
}
