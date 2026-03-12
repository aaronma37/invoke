local ffi = require("ffi")
require("gen_wires")

-- Activation: Sigmoid
local function sigmoid(x) return 1 / (1 + math.exp(-x)) end
local function d_sigmoid(x) return x * (1 - x) end

local dataset = {
    {{0, 0}, {0}},
    {{0, 1}, {1}},
    {{1, 0}, {1}},
    {{1, 1}, {0}}
}

local lr = 0.5 -- Learning Rate

function tick()
    -- Ensure globals are bound
    if not wire_brain or not wire_layers or not wire_stats then
        return
    end

    local brain = ffi.cast("ai_brain_t*", wire_brain)
    local layers = ffi.cast("ai_layers_t*", wire_layers)
    local stats = ffi.cast("ai_stats_t*", wire_stats)

    -- 1. Initialize (Once)
    if stats.init_flag < 1.0 then
        for i = 0, 7 do brain.w1[i] = (math.random() - 0.5) * 2 end
        for i = 0, 3 do brain.w2[i] = (math.random() - 0.5) * 2 end
        for i = 0, 3 do brain.b1[i] = 0 end
        brain.b2[0] = 0
        stats.init_flag = 1.0
        moontide.log("MLP Brain Initialized")
    end

    -- 2. Training Step (SGD)
    local sample = dataset[math.random(1, #dataset)]
    local input = sample[1]
    local target = sample[2][1]

    layers.input[0] = input[1]
    layers.input[1] = input[2]

    -- FORWARD PASS
    for j = 0, 3 do
        local sum = brain.b1[j]
        for i = 0, 1 do
            sum = sum + layers.input[i] * brain.w1[i * 4 + j]
        end
        layers.hidden[j] = sigmoid(sum)
    end

    local out_sum = brain.b2[0]
    for j = 0, 3 do
        out_sum = out_sum + layers.hidden[j] * brain.w2[j]
    end
    layers.output[0] = sigmoid(out_sum)

    -- BACKPROPAGATION
    local error = target - layers.output[0]
    local delta_o = error * d_sigmoid(layers.output[0])

    for j = 0, 3 do
        local grad = delta_o * layers.hidden[j]
        brain.w2[j] = brain.w2[j] + grad * lr
    end
    brain.b2[0] = brain.b2[0] + delta_o * lr

    for j = 0, 3 do
        local delta_h = delta_o * brain.w2[j] * d_sigmoid(layers.hidden[j])
        for i = 0, 1 do
            brain.w1[i * 4 + j] = brain.w1[i * 4 + j] + (delta_h * layers.input[i] * lr)
        end
        brain.b1[j] = brain.b1[j] + delta_h * lr
    end

    -- Update Stats
    stats.epoch = stats.epoch + 1
    stats.loss = error * error
    stats.target = target

    moontide.sleep(10)
end
