return {
  namespaces = {
    ai = {
      wires = {
        brain = {
            schema = "w1:f32[8];w2:f32[4];b1:f32[4];b2:f32[1]",
            buffered = false
        },
        layers = {
            schema = "input:f32[2];hidden:f32[4];output:f32[1]",
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
          reads = {"brain", "layers", "stats"},
          writes = {"brain", "layers", "stats"}
        }
      }
    }
  }
}
