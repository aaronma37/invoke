local ffi = require("ffi")

local M = {}

local function count_chars(str, char)
    local _, count = str:gsub(char, "")
    return count
end

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
                local v, vt, vn
                if parts[i]:find("//") then
                    v, vn = parts[i]:match("(%d+)//(%d+)")
                    vt = 0
                elseif count_chars(parts[i], "/") == 2 then
                    v, vt, vn = parts[i]:match("(%d+)/(%d+)/(%d+)")
                elseif count_chars(parts[i], "/") == 1 then
                    v, vt = parts[i]:match("(%d+)/(%d+)")
                    vn = 0
                else
                    v = parts[i]
                    vt = 0
                    vn = 0
                end
                table.insert(face_data, {
                    v = tonumber(v), 
                    vt = tonumber(vt) or 0, 
                    vn = tonumber(vn) or 0
                })
            end
            
            -- Triangulate fan
            for i = 2, #face_data - 1 do
                local tri_indices = {face_data[1], face_data[i], face_data[i+1]}
                local tri_verts = {}
                for _, vert in ipairs(tri_indices) do
                    local p = positions[vert.v] or {0,0,0}
                    local uv = uvs[vert.vt] or {0,0}
                    local n = normals[vert.vn] or {0,0,0}
                    table.insert(tri_verts, {pos = p, uv = uv, normal = n})
                end

                -- Calculate face normal if needed
                local v0, v1, v2 = tri_verts[1].pos, tri_verts[2].pos, tri_verts[3].pos
                local e1 = {v1[1]-v0[1], v1[2]-v0[2], v1[3]-v0[3]}
                local e2 = {v2[1]-v0[1], v2[2]-v0[2], v2[3]-v0[3]}
                local fn = {
                    e1[2]*e2[3] - e1[3]*e2[2],
                    e1[3]*e2[1] - e1[1]*e2[3],
                    e1[1]*e2[2] - e1[2]*e2[1]
                }
                local fmag = math.sqrt(fn[1]^2 + fn[2]^2 + fn[3]^2)
                if fmag > 1e-8 then
                    fn = {fn[1]/fmag, fn[2]/fmag, fn[3]/fmag}
                else
                    fn = {0, 1, 0}
                end

                for _, v in ipairs(tri_verts) do
                    if v.normal[1]^2 + v.normal[2]^2 + v.normal[3]^2 < 1e-6 then
                        v.normal = fn
                    end
                    table.insert(triangles, v)
                end
            end
        end
    end
    f:close()
    
    return triangles
end

return M
