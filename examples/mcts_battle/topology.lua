local num_sims = 10

local topo = {
  namespaces = {}
}

-- Create 10 parallel simulation buckets
for i = 1, num_sims do
  local ns_name = "sim_" .. i
  topo.namespaces[ns_name] = {
    wires = {
      -- Each timeline has its own isolated HP and stats
      stats = "player_hp:f32;boss_hp:f32;ticks:i32"
    },
    nodes = {
      {
        name = "worker",
        type = "luajit",
        mode = "Heartbeat",
        script = "examples/mcts_battle/worker.lua",
        reads = {"stats"},
        writes = {"stats"}
      }
    }
  }
end

-- Global namespace to monitor the winner
topo.namespaces.global = {
  wires = {
    results = "best_timeline:i32;best_boss_hp:f32"
  },
  nodes = {}
}

return topo
