return {
  namespaces = {
    interlat = {
      wires = {
        -- The "Latent Concept" (128-dimensional vector)
        latent_thought = {
            schema = "vec:f32[128];concept_id:i32",
            buffered = true
        },
        -- Final Output Stream
        output_stream = {
            schema = "text:char[64];intensity:f32",
            buffered = false
        }
      },
      nodes = {
        {
          name = "encoder",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/interlat/encoder.lua",
          writes = {"latent_thought"}
        },
        {
          name = "modulator",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/interlat/modulator.lua",
          reads = {"latent_thought"},
          writes = {"latent_thought"}
        },
        {
          name = "decoder",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/interlat/decoder.lua",
          reads = {"latent_thought"},
          writes = {"output_stream"}
        }
      }
    }
  }
}
