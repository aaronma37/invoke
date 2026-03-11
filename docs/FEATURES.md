# Moontide Feature Set

### The "Wins" (Pros)

*   **Infinite Iteration (Hot-Reloading):** Change your Lua or WASM code while the app is running. The engine detects the change and swaps the logic in milliseconds without losing your progress.
*   **Indestructible Simulation (Crash Recovery):** If a specific piece of logic crashes or attempts a memory violation, the engine catches it and continues the next frame. One bad script won't kill the whole app.
*   **Data That Never Dies (Eternal State):** Your data (position, health, stats) is stored separately from your logic. You can rewrite your entire physics system mid-execution, and your characters will stay exactly where they were.
*   **Hardware-Level Security (Gating):** The engine uses your CPU's hardware to enforce "who can touch what." This catches sneaky bugs where one system accidentally overwrites another system's data.
*   **Live Data Reshaping (Schema Evolution):** Need to add a "Level" field to your player data? Change the config, and the engine will automatically move your existing data to the new structure while it's running.
*   **Multi-Language Freedom:** Use the best tool for the job. Write high-level "vibes" in Lua and performance-heavy math in Zig/WASM. They all talk to each other through the same memory.
*   **Parallel Safety Switch (Double-Buffering):** Flip a switch to safely use all your CPU cores without ever worrying about "Race Conditions" or "Heisenbugs." Nodes read from stable memory and write to a workspace that is synced at the end of the frame.
*   **Decoupled Messaging (Poking):** Trigger actions in other systems (like playing a sound or applying damage) using simple "tags" instead of complex code links.

---

### The "Future" (Planned)

*   **Execution Watchdog:** Automatically detect and kill logic that gets stuck in an infinite loop, ensuring the rest of the engine keeps running.
*   **Bad Actor Jail:** Automatically disable scripts that crash repeatedly until you fix them, preventing log-spam and wasted CPU power.
*   **State Snapshots:** Instantly save or rollback the entire state of the engine by simply copying the "Eternal Wires."

*   **Memory Cost:** To make parallelism 100% safe and deterministic, the engine uses 2x the memory for data (Front and Back banks).
*   **Setup Requirement:** You have to define a "Topology" (a simple JSON map) that tells the engine how your logic nodes and data wires connect.
*   **Security Overhead:** The hardware-level gating features add a tiny amount of work for the CPU every time it swaps between different logic systems.
*   **Fixed Data Sizes:** Because data lives on "Wires" in RAM, you generally have to decide how big a data structure is before you start the simulation.
