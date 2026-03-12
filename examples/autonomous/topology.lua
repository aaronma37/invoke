return {
  namespaces = {
    auto = {
      wires = {
        -- The shared state of the discovery
        discovery = {
            schema = "guess:f32[4];secret:f32[4];initialized:i32",
            buffered = false
        },
        -- Performance and feedback
        metrics = {
            schema = "score:f32;attempts:i32;best_score:f32",
            buffered = false
        }
      },
      nodes = {
        {
          name = "prober",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/autonomous/prober.lua",
          reads = {"discovery"},
          writes = {"discovery"}
        },
        {
          name = "evaluator",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/autonomous/evaluator.lua",
          reads = {"discovery", "metrics"},
          writes = {"metrics"}
        },
        {
          name = "architect",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/autonomous/architect.lua",
          reads = {"metrics"},
          writes = {}
        }
      }
    }
  }
}
