-- Sensory Input: Simulated Audio Frequencies (FFT)
-- Maps 128 frequency bins to the first 128 neurons in the reservoir

function tick(pulse_count)
    -- Simulate a sweep frequency over time
    local freq_bin = math.floor((pulse_count / 10) % 128)
    
    -- Inject spike into the neuron corresponding to the active frequency
    -- wire_reservoir is bound to the BACK bank by the orchestrator
    wire_reservoir.potentials[freq_bin] = 1.0
    
    if pulse_count % 100 == 0 then
        moontide.log("SENSORY: Stimulating frequency bin " .. freq_bin)
    end
end
