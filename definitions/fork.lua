-- Primitive Definition: Fork (Y-Junction)
-- Maps (u, v, z) -> (x, y, z) with two output sockets.

return {
    name = "fork",
    topology_type = "periodic_u",
    
    sockets = {
        bottom = { edge = "v", value = 0.0 },
        top_left  = { edge = "v", value = 1.0, u_range = {0.0, 0.5} },
        top_right = { edge = "v", value = 1.0, u_range = {0.5, 1.0} }
    },

    evaluate = function(u, v, z)
        local radius = z[1] or 0.5
        local height = z[2] or 1.0
        local base_offset = z[3] or 0.0
        
        -- Split logic: as V increases, we push X left or right
        local split_amount = v * 1.5
        local x_offset = (u < 0.5) and -split_amount or split_amount
        
        -- Adjust angle to wrap each branch individually at the top
        local local_u = (u < 0.5) and (u * 2) or ((u - 0.5) * 2)
        local angle = local_u * math.pi * 2
        
        local x = math.cos(angle) * (radius * 0.7) + x_offset
        local y = math.sin(angle) * (radius * 0.7)
        local z_pos = base_offset + (v * height)
        
        return x, y, z_pos, 0, 0 -- No semantic channels needed for this test
    end
}
