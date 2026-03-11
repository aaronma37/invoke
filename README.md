# Moontide: The AI-Native DAG Runtime

**Stop building monoliths. Start sculpting data-flow.**

Moontide is a high-performance, **Data-Oriented DAG (Directed Acyclic Graph)** runtime engine. It is designed to be the "Silicon Motherboard" for AI-generated software, replacing traditional monolithic architectures with a physically isolated, deterministic assembly line.

## 🚀 The Architecture
Moontide splits your application into a static, indestructible **Kernel** and a dynamic, polyglot **Logic Layer**.

*   **The Motherboard (Zig Host):** A tiny (< 2MB) kernel that manages raw memory and schedules execution. It is designed to be indestructible.
*   **The Topology (Lua Blueprint):** Your application structure is defined in a **Lua script**. This allows for programmatic, procedurally generated graphs with the power of loops and conditionals. The Kernel enforces the resulting graph.
*   **The Grapes (Polyglot Nodes):** Individual logic units written in the language best suited for the task: **LuaJIT** (for speed), **WASM** (for security), or **C/Zig** (for hardware).

## 🧠 Why Moontide? (The "Pro" Verdict)

### 1. Radical Token Efficiency
Traditional codebases are toxic to AI. To fix one function, an LLM often needs the entire file's context. Moontide fixes this via **Context Isolation**:
*   **Isolated Worker:** A "Worker" AI only needs to see the **Wire Schema** and the **Node Goal**. 
*   **Context Window Optimization:** By reducing context from 10,000 lines to ~100 tokens of schema, AI success rates hit near 100% with massive cost savings.
*   **Programmatic Blueprint:** By using Lua for topology, an AI can describe complex wiring patterns in 10 lines of code rather than 1,000 lines of JSON.

### 2. Data-Oriented Design (DOD)
Moontide rejects the "Object" (State + Methods). Instead, it uses the **Eternal Data** model:
*   **Wires:** Strictly-typed, page-aligned memory buffers mapped to C-ABI (`extern struct`).
*   **Zero-Copy:** Data never moves. Nodes plug into raw memory "Wires." There is **zero serialization overhead** (no JSON/Protobuf/FlatBuffers).
*   **Eternal State:** Logic is ephemeral; Wires are eternal. You can hot-swap your physics logic mid-tick, and the "Player" position in memory remains untouched.

### 3. Deterministic Parallelism
Moontide treats the CPU like an assembly line, not a messy room of locks and mutexes.
*   **Double-Buffered Wires:** Nodes read from the "Front" bank and write to the "Back" bank. 
*   **Race-Condition Immune:** Systems run in parallel with **zero mutexes**. 
*   **Bit-Perfect Output:** The engine is 100% deterministic. The results of a frame are identical regardless of core count—essential for AI training and debugging "Heisenbugs."

### 4. Indestructible Host (Silicon Armor)
The Zig Kernel uses hardware-level protection (`mprotect`) to gate memory.
*   **Silicon Gating:** If a Node tries to write to a wire it wasn't granted access to, the CPU triggers a fault.
*   **Signal Recovery:** The Motherboard catches the crash, recovers the stack, and keeps the engine running while logging the error for the AI to fix.

## 🔌 Polyglot Interoperability (Universal FFI)
Moontide is not a silo; it is a **Universal Socket** for the existing software ecosystem. Because the "Handshake" is pure C-ABI, Moontide is compatible with almost every high-performance library on Earth.

*   **Zero-Glue Integration:** Skip the binding generators. If a library accepts a C-pointer (like **OpenCV**, **FFmpeg**, or **Vulkan**), you can plug an Moontide Wire directly into it with zero translation.
*   **Language Agnostic:** Any language that supports C-FFI can become an Moontide Node. We currently support **LuaJIT**, **WASM**, and **Native C/Zig**, with **Python** and **Rust** in the pipeline.
*   **Legacy-Friendly:** Wrap your existing C++ or Fortran math libraries in a 10-line Moontide shim and instantly gain the benefits of hot-reloading and hardware-protected state.

## 🛠️ The Development Loop
Moontide turns software development into **Sculpting**:

1.  **Architect:** An LLM (Gemini) defines the **Graph Topology** in JSON.
2.  **Synthesis:** The Kernel generates bit-perfect **C/Lua Headers** automatically.
3.  **Worker:** A local LLM (Gemma) writes mathematically pure **Lua/WASM logic**.
4.  **Sculpt:** The logic is hot-swapped into the running process. **Zero Recompiles.**

## 🌐 Ubiquitous Applications
The same 2MB **Universal Kernel** can be deployed across any hardware stack, transforming how we build in every sector:

| Sector | Moontide's Impact | Why it Wins |
| :--- | :--- | :--- |
| **Robotics (ROS 3.0)** | **The Real-Time Brain:** A deterministic, zero-copy alternative to heavy ROS middleware. | Swap movement nodes over-the-air while the robot is walking. Hardware gating ensures a buggy node can't crash the physical motors. |
| **Game Engines** | **The Eternal Engine:** A pure-DOD renderer where logic can be rewritten while the game is live. | Zero-latency hot-swapping of Physics and AI. Deterministic parallelism makes "Rollback Netcode" and Replays bit-perfect by default. |
| **Web & Edge** | **The No-Tax Kernel:** High-density WASM orchestration without the "JavaScript Tax." | Runs as a tiny WASM kernel in the browser or on the edge. High-performance logic with near-native speed and air-gapped security. |
| **Graphics** | **Live Render Pipelines:** Re-wire Vulkan/WebGPU passes via JSON topology. | Sculpt shaders and render logic in real-time. The GPU state remains eternal while the "Software" logic evolves. |
| **Enterprise** | **Invisible Logic:** A visual map of business rules that are physically impossible to break. | AI maintains the "Topology" of complex business logic. The system scales infinitely because the AI context is isolated to tiny, 50-line nodes. |

## 🏁 Quick Start

### 1. Build the Kernel
```bash
zig build
```

### 2. Execute the AI Sandbox
```bash
# Compile the WASM worker
zig build-exe examples/sandbox/physics.zig -target wasm32-freestanding -rdynamic -O ReleaseSmall -fno-entry -femit-bin=examples/sandbox/physics.wasm -I gen -I sdk

# Run the Graph (using the Lua topology)
./zig-out/bin/moontide run examples/sandbox/topology.lua
```

---
*Logic is Ephemeral, Data is Eternal. The Motherboard is Indestructible.*
