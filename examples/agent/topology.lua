return {
  namespaces = {
    agent = {
      wires = {
        -- Incoming Tasks (Eternal State)
        mailbox = {
            schema = "task_id:i32;cmd:char[32];state:i32", -- state: 0=new, 1=planned, 2=finished, 3=failed
            buffered = false
        },
        -- The Planner's decision
        thought = {
            schema = "action:i32;value:f32", -- action: 1=compute, 2=chaos_test
            buffered = false
        },
        -- Final Result
        outcome = {
            schema = "result:f32;total_errors:i32",
            buffered = false
        }
      },
      nodes = {
        {
          name = "planner",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/agent/planner.lua",
          reads = {"mailbox", "outcome"},
          writes = {"mailbox", "thought"}
        },
        {
          name = "executor",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/agent/executor.lua",
          reads = {"mailbox", "thought"},
          writes = {"mailbox", "outcome"}
        }
      }
    }
  }
}
