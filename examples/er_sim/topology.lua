return {
  namespaces = {
    er = {
      wires = {
        -- The Global Clock
        clock = "now:f64;events_processed:i32",
        -- The Event Queue (Fixed size for now)
        -- type: 1=Arrival, 2=TriageFinish, 3=DoctorFinish
        queue = "count:i32;times:f64[100];types:i32[100]"
      },
      nodes = {
        {
          name = "timekeeper",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/er_sim/timekeeper.lua",
          reads = {"queue"},
          writes = {"clock"}
        },
        {
          name = "simulation",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/er_sim/simulation.lua",
          reads = {},
          writes = {"queue", "clock"}
        }
      }
    }
  }
}
