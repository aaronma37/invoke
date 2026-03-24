-- Primitive Definition: Cylinder
-- A procedural mapping from (u, v, z) -> (x, y, z, c)

return {
    name = "cylinder",
    topology_type = "periodic_u",
    
    sockets = {
        bottom = { edge = "v", value = 0.0 },
        top    = { edge = "v", value = 1.0 }
    },

    evaluate = function(u, v, z)
        local radius = z[1] or 0.5
        local height = z[2] or 1.0
        
        -- HARDENED: Support for optional stacking offset (z[3])
        local base_offset = z[3] or 0.0
        
        local angle = u * math.pi * 2
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        
        -- Local Z spans [base, base + height]
        local z_pos = base_offset + (v * height)
        
        -- Semantic Channels
        local c1 = (v > 0.95) and 1.0 or 0.0
        local c2 = (v < 0.05) and 1.0 or 0.0

        return x, y, z_pos, c1, c2
    end
}
