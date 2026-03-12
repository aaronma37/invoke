local ffi = require("ffi")
require("gen_wires")

function tick()
    if not wire_discovery or not wire_metrics then return end
    
    local discovery = ffi.cast("auto_discovery_t*", wire_discovery)
    local metrics = ffi.cast("auto_metrics_t*", wire_metrics)

    -- 1. Calculate L2 distance (Lower is better)
    local diff_sq = 0
    for i = 0, 3 do
        local d = discovery.guess[i] - discovery.secret[i]
        diff_sq = diff_sq + (d * d)
    end
    local dist = math.sqrt(diff_sq)

    -- 2. Update Metrics
    metrics.score = dist
    metrics.attempts = metrics.attempts + 1
    
    if metrics.best_score == 0 or dist < metrics.best_score then
        metrics.best_score = dist
    end

    moontide.sleep(10)
end
