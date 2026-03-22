local ffi = require("ffi")

local M = {}

function M.load(path)
    print("UV Loader: Loading " .. path)
    local f = io.open(path, "r")
    if not f then error("Could not open file: " .. path) end

    local positions = {}
    local uvs = {}
    local normals = {}
    
    local triangles = {}
    
    for line in f:lines() do
        local parts = {}
        for part in line:gmatch("%S+") do table.insert(parts, part) end
        
        if parts[1] == "v" then
            table.insert(positions, {tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4])})
        elseif parts[1] == "vt" then
            table.insert(uvs, {tonumber(parts[2]), tonumber(parts[3])})
        elseif parts[1] == "vn" then
            table.insert(normals, {tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4])})
        elseif parts[1] == "f" then
            local face_data = {}
            for i = 2, #parts do
                local v, vt, vn = parts[i]:match("([^/]*)/?([^/]*)/?([^/]*)")
                table.insert(face_data, {
                    v = tonumber(v), 
                    vt = tonumber(vt) or 0, 
                    vn = tonumber(vn) or 0
                })
            end
            
            -- Triangulate fan
            for i = 2, #face_data - 1 do
                local tri = {face_data[1], face_data[i], face_data[i+1]}
                for _, vert in ipairs(tri) do
                    local p = positions[vert.v] or {0,0,0}
                    local uv = uvs[vert.vt] or {0,0}
                    local n = normals[vert.vn] or {0,1,0}
                    
                    table.insert(triangles, {
                        pos = p,
                        uv = uv,
                        normal = n
                    })
                end
            end
        end
    end
    f:close()
    
    return triangles
end

return M
