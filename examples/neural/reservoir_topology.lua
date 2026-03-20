return {
  namespaces = {
    brain = {
      wires = {
        -- A reservoir of 1,048,576 neurons (1 Million Neurons)
        reservoir = { 
          schema = "potentials:f32[1048576];thresholds:f32[1048576];spikes:u32[2048];history:f32[1048576]",
          buffered = true 
        },
        -- Synaptic Fabric: 1 Million neurons * 32 connections each
        synapses = "targets:u32[33554432];weights:f32[33554432]"
      },
      nodes = {
        {
          name = "sensory_input",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/neural/sensory_input.lua",
          writes = {"reservoir"}
        },
        {
          name = "liquid_physics",
          type = "spiking_simd",
          mode = "Heartbeat",
          script = "none",
          reads = {"reservoir", "synapses"},
          writes = {"reservoir"}
        },
        {
          name = "plasticity_stdp",
          type = "spiking_simd",
          mode = "Heartbeat",
          script = "none",
          reads = {"reservoir"},
          writes = {"synapses"}
        },
        {
          name = "vram_readout",
          type = "webgpu",
          mode = "Heartbeat",
          script = "none",
          reads = {"reservoir"}
        },
        {
          name = "monitor",
          type = "hud",
          mode = "Heartbeat",
          script = "none",
          reads = {"reservoir"}
        }
      }
    }
  }
}
