local ffi = require("ffi")

local M = {}

function M.load(path)
    print("OBJ Loader (Enhanced): Loading " .. path)
    local f = io.open(path, "r")
    if not f then error("Could not open file: " .. path) end

    local positions = {}
    local normals = {}
    local uvs = {}
    local vertices = {} 
    
    local has_faces = false
    
    for line in f:lines() do
        if not line:match("^#") then
            local parts = {}
            for part in line:gmatch("%S+") do table.insert(parts, part) end
            
            if parts[1] == "v" then
                table.insert(positions, {tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4])})
            elseif parts[1] == "vn" then
                table.insert(normals, {tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4])})
            elseif parts[1] == "vt" then
                table.insert(uvs, {tonumber(parts[2]), tonumber(parts[3])})
            elseif parts[1] == "f" then
                has_faces = true
                local face_data = {}
                for i = 2, #parts do
                    local v_str, vt_str, vn_str = parts[i]:match("([^/]*)/?([^/]*)/?([^/]*)")
                    table.insert(face_data, {tonumber(v_str), tonumber(vt_str), tonumber(vn_str)})
                end
                
                -- Simple triangulation for polygons
                for i = 2, #face_data - 1 do
                    local tri_indices = {1, i, i + 1}
                    for _, tidx in ipairs(tri_indices) do
                        local indices = face_data[tidx]
                        local p = positions[indices[1]] or {0,0,0}
                        local n = (indices[3] and normals[indices[3]]) or {0,1,0}
                        local uv = (indices[2] and uvs[indices[2]]) or {0,0}
                        
                        table.insert(vertices, p[1]); table.insert(vertices, p[2]); table.insert(vertices, p[3])
                        table.insert(vertices, n[1]); table.insert(vertices, n[2]); table.insert(vertices, n[3])
                        table.insert(vertices, uv[1]); table.insert(vertices, uv[2]); table.insert(vertices, 1.0) -- Color fallback
                    end
                end
            end
        end
    end
    f:close()
    
    if not has_faces then
        print("No faces found, generating point cloud vertices...")
        for _, p in ipairs(positions) do
            table.insert(vertices, p[1]); table.insert(vertices, p[2]); table.insert(vertices, p[3])
            table.insert(vertices, 0); table.insert(vertices, 1); table.insert(vertices, 0) -- Up normal
            table.insert(vertices, 1.0); table.insert(vertices, 1.0); table.insert(vertices, 1.0) -- White color
        end
    end
    
    local data = ffi.new("float[?]", #vertices)
    for i=1, #vertices do data[i-1] = vertices[i] end
    return data, #vertices / 9, has_faces
end

return M
