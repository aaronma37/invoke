return {
  namespaces = {
    ai = {
      wires = {
        ["tensor.commands"] = {
            schema = "data:u32[224]", -- 32 commands * 7 u32s each
            buffered = false
        },
        ["tensor.memory"] = {
            schema = "data:f32[1024]",
            buffered = false
        },
        stats = {
            schema = "loss:f32;epoch:i32;target:f32;init_flag:f32",
            buffered = false
        }
      },
      nodes = {
        {
          name = "trainer",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/mlp/trainer.lua",
          reads = {"tensor.memory", "stats"},
          writes = {"tensor.commands", "tensor.memory", "stats"}
        },
        {
          name = "tensor_engine",
          type = "tensor",
          mode = "Heartbeat",
          script = "none",
          reads = {"tensor.commands", "tensor.memory"},
          writes = {"tensor.commands", "tensor.memory"}
        }
      }
    }
  }
}
