local ffi = require("ffi")
local batch_size = 20000
ffi.cdef(string.format([[
    typedef struct { float x[%d]; float y[%d]; } Batch;
    typedef struct { int32_t class[%d]; } Pred;
]], batch_size, batch_size, batch_size))

local tree = nil

local function build_tree_scaled(depth, min_x, max_x, min_y, max_y)
    if depth == 0 then return { leaf = true, class = math.random(0, 1) } end
    local axis = math.random(0, 1)
    local node = { leaf = false, axis = axis }
    if axis == 0 then
        node.split = min_x + math.random() * (max_x - min_x)
        node.left = build_tree_scaled(depth - 1, min_x, node.split, min_y, max_y)
        node.right = build_tree_scaled(depth - 1, node.split, max_x, min_y, max_y)
    else
        node.split = min_y + math.random() * (max_y - min_y)
        node.left = build_tree_scaled(depth - 1, min_x, max_x, min_y, node.split)
        node.right = build_tree_scaled(depth - 1, min_x, max_x, node.split, max_y)
    end
    return node
end

local function evaluate(node, x, y)
    if node.leaf then return node.class end
    local val = node.axis == 0 and x or y
    if val < node.split then return evaluate(node.left, x, y) else return evaluate(node.right, x, y) end
end

local first_tick = true
function tick()
    if not wire_batch then return end
    
    local pred_ptr = nil
    for k, v in pairs(_G) do
        if k:match("wire_pred_") then pred_ptr = v break end
    end
    if not pred_ptr then return end

    local b = ffi.cast("Batch*", wire_batch)
    local p = ffi.cast("Pred*", pred_ptr)

    if first_tick then
        tree = build_tree_scaled(8, 0, 800, 0, 600)
        first_tick = false
    end

    for i = 0, batch_size - 1 do
        p.class[i] = evaluate(tree, b.x[i], b.y[i])
    end
end
