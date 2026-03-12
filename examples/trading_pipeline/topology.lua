return {
  namespaces = {
    hft = {
      wires = {
        -- The raw price data
        price_stream = "current_price:f32;last_price:f32",
        -- The processed technical indicator
        signal = "moving_average:f32;trend:i32", -- 1=Up, -1=Down
        -- The trading account state
        account = "cash:f32;position:i32"
      },
      nodes = {
        {
          name = "feed",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/trading_pipeline/feed.lua",
          reads = {},
          writes = {"price_stream"}
        },
        {
          name = "processor",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/trading_pipeline/processor.lua",
          reads = {"price_stream"},
          writes = {"signal"}
        },
        {
          name = "bot",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/trading_pipeline/bot.lua",
          reads = {"price_stream", "signal"},
          writes = {"account"}
        }
      }
    }
  }
}
