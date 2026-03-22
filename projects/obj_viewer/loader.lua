local ffi = require("ffi")

local M = {}

function M.load(path)
    print("OBJ Loader (Point Support): Loading " .. path)
    local f = io.open(path, "r")
    if not f then error("Could not open file: " .. path) end

    local positions = {}
    local normals = {}
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
            elseif parts[1] == "f" then
                has_faces = true
                local face_data = {}
                for i = 2, #parts do
                    local v, vt, vn = parts[i]:match("([^/]*)/?([^/]*)/?([^/]*)")
                    table.insert(face_data, {tonumber(v), tonumber(vt), tonumber(vn)})
                end
                for i = 2, #face_data - 1 do
                    local tri_indices = {1, i, i + 1}
                    for _, tidx in ipairs(tri_indices) do
                        local indices = face_data[tidx]
                        local p = positions[indices[1]] or {0,0,0}
                        local n = (indices[3] and normals[indices[3]]) or {0,1,0}
                        table.insert(vertices, p[1]); table.insert(vertices, p[2]); table.insert(vertices, p[3])
                        table.insert(vertices, n[1]); table.insert(vertices, n[2]); table.insert(vertices, n[3])
                        table.insert(vertices, 0.7); table.insert(vertices, 0.7); table.insert(vertices, 0.7)
                    end
                end
            end
        end
    end
    f:close()
    
    -- If no faces were found, load all 'v' entries as a point cloud
    if not has_faces then
        print("No faces found, loading as point cloud...")
        for _, p in ipairs(positions) do
            table.insert(vertices, p[1]); table.insert(vertices, p[2]); table.insert(vertices, p[3])
            table.insert(vertices, 0); table.insert(vertices, 1); table.insert(vertices, 0) -- Normal up
            table.insert(vertices, 1.0); table.insert(vertices, 1.0); table.insert(vertices, 1.0) -- White points
        end
    end
    
    local data = ffi.new("float[?]", #vertices)
    for i=1, #vertices do data[i-1] = vertices[i] end
    return data, #vertices / 9
end

return M
