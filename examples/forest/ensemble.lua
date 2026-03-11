local ffi = require("ffi")
local num_trees = 8
local batch_size = 20000
ffi.cdef(string.format([[
    typedef struct { int32_t class[%d]; } Pred;
]], batch_size))

function tick()
    if not wire_final_pred then return end
    local final = ffi.cast("Pred*", wire_final_pred)
    
    local preds = {}
    for k, v in pairs(_G) do
        if k:match("wire_pred_") and not k:match("final") then
            table.insert(preds, ffi.cast("Pred*", v))
        end
    end
    
    if #preds == 0 then return end

    for i = 0, batch_size - 1 do
        local sum = 0
        for j = 1, #preds do
            sum = sum + preds[j].class[i]
        end
        final.class[i] = (sum > (#preds / 2)) and 1 or 0
    end
end
