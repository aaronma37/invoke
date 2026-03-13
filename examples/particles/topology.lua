return {
  namespaces = {
    world = {
      wires = {
        -- 1000 particles: each has pos(x,y) and vel(vx,vy)
        particles = {
          schema = "count:i32;x:f32[1000];y:f32[1000];vx:f32[1000];vy:f32[1000]",
          buffered = true
        },
        ["journal.config"] = {
          schema = "interval_ms:i32;force_save:i32;force_load:i32",
          buffered = false
        },
        ["audio.play"] = {
          schema = "id:u32[16];volume:f32[16];pitch:f32[16]",
          buffered = false
        },
        ["audio.load"] = {
          schema = "path:char[256][32]",
          buffered = false
        }
      },
      nodes = {
        {
          name = "sim",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/particles/sim.lua",
          reads = {"particles"},
          writes = {"particles", "audio.play", "audio.load"}
        },
        {
          name = "view",
          type = "hud",
          mode = "Heartbeat",
          script = "none",
          reads = {"particles"}
        },
        {
          name = "journal",
          type = "journal",
          mode = "Heartbeat",
          script = "none",
          reads = {"journal.config"},
          writes = {"journal.config"}
        },
        {
          name = "audio",
          type = "audio",
          mode = "Heartbeat",
          script = "none",
          reads = {"audio.play", "audio.load"},
          writes = {"audio.play"} -- To clear commands
        }
      }
    }
  }
}
