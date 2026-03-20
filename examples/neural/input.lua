local count = 0

function tick()
    count = count + 1
    
    -- Every 100 ticks (~10Hz if running at 1000Hz), 
    -- we inject a massive spike into the first 16 neurons
    if count % 100 == 0 then
        -- wire_reservoir is injected by the kernel via FFI
        for i = 0, 15 do
            wire_reservoir.potentials[i] = 1.0
        end
        moontide.log("PULSE: Injected spike into reservoir.")
    end
end
