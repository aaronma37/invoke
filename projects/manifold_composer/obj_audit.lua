local ffi = require("ffi")

print("--- DEEP OBJ AUDIT: COORDINATE MAPPING ---")

local f = io.open("output.obj", "r")
local vertices = {}
local faces = {}
for line in f:lines() do
    if line:sub(1, 2) == "v " then
        local x, y, z = line:match("v ([%d%.%-]+) ([%d%.%-]+) ([%d%.%-]+)")
        table.insert(vertices, {x = tonumber(x), y = tonumber(y), z = tonumber(z)})
    elseif line:sub(1, 2) == "f " then
        local v1, v2, v3 = line:match("f (%d+) (%d+) (%d+)")
        table.insert(faces, {tonumber(v1), tonumber(v2), tonumber(v3)})
    end
end
f:close()

local left_cluster = {}
local right_cluster = {}
for i, v in ipairs(vertices) do
    if v.z > 1.9 then -- Focus on the branching zone
        if v.x < -0.1 then left_cluster[i] = true
        elseif v.x > 0.1 then right_cluster[i] = true end
    end
end

for i, face in ipairs(faces) do
    local has_left, has_right = false, false
    for _, v_idx in ipairs(face) do
        if left_cluster[v_idx] then has_left = true end
        if right_cluster[v_idx] then has_right = true end
    end
    
    if has_left and has_right then
        print(string.format("\n[WEB TRIANGLE #%d] Indices: %d, %d, %d", i, face[1], face[2], face[3]))
        for _, v_idx in ipairs(face) do
            local v = vertices[v_idx]
            print(string.format("  Vertex %d: X=%0.4f, Y=%0.4f, Z=%0.4f", v_idx, v.x, v.y, v.z))
        end
    end
end
