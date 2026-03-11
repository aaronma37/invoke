# The Moontide Philosophy

**Moontide** is an AI-native runtime engine. It is a fundamental rejection of monolithic software, redesigned for the era of "Vibe Coding."

## I. The Core: "Pure Silicon" (Zig)
The Moontide Kernel is a minimalist, compiled binary. It is the **Motherboard** that provides the physical infrastructure for data.
* **The Responsibility:** It handles only three things: Memory Allocation (Wires), Execution Scheduling (The Heartbeat), and Hardware I/O (Vulkan/Drivers).
* **Strict Isolation:** The Kernel does **not** include `lua.h` or any language-specific headers. It treats all logic as "Opaque Nodes" via a stable C-style ABI.
* **The Benefit:** This makes the kernel tiny (< 2MB), portable, and immune to crashes from the logic layer.

## II. The Standard: "The Primary Engine" (LuaJIT)
While technically an extension, LuaJIT is the **soul** of Moontide. it is the recommended, default choice for 99% of development.
* **Privileged Integration:** Shipped in the "Standard Distribution." To the hardware, it is a modular plugin; to the user, it is the primary interface.
* **FFI Stenciling:** It uses a "Shim" to map Zig’s raw memory wires directly into LuaJIT’s FFI tables for C-speed execution with instant hot-reloading.
* **The Benefit:** You get the speed of thought. You can rewrite combat logic or graphics math while the app is running, without ever touching a compiler.

## III. The Workflow: "AI-Native Sculpting"
Moontide is designed for a world where AI is the primary author of code.
* **The Architect (Macro):** Manages the "Big Picture"—wiring nodes together in `topology.json` and defining memory schemas.
* **The Worker (Micro):** Writes tiny, stateless Lua scripts inside the nodes.
* **Infinite Iteration:** Because Wires hold the state, you can swap Lua logic a thousand times a minute. The AI "sculpts" the behavior of the system in real-time.

## IV. The Concurrency: "The Assembly Line"
Moontide rejects the traditional, lock-heavy multithreading model. Instead, it treats the CPU like an assembly line.
*   **Parallel by Design:** By separating Data (Wires) from Logic (Nodes), we can run systems in parallel without a single mutex.
*   **The Double-Buffer Armor:** Wires act as synchronization barriers. Nodes read from the "Front" and write to the "Back." Race conditions are physically impossible.
*   **Deterministic Parallelism:** The result of a frame is bit-for-bit identical regardless of how many cores you use. This eliminates "Heisenbugs" and makes AI-training perfect.

## V. Summary of the "Moontide Handshake"
| Component | Responsibility | Knowledge of Logic | Knowledge of Data |
| :--- | :--- | :--- | :--- |
| **Kernel** | Motherboard (Silicon) | No (Strict Isolation) | Yes (Management) |
| **Extension** | The Bridge (Runtime) | Yes (Lua/WASM) | Yes (Binding) |
| **Node** | The Worker (Logic) | Internal Only | Indirect (via SDK) |

---

## The Core Mantra: Logic is Ephemeral, Data is Eternal.
In Moontide, the traditional concept of an "Object" is destroyed. State lives on **Wires** (eternal), and behavior lives in **Nodes** (ephemeral). This separation allows for fearless experimentation, radical token efficiency, and bit-perfect deterministic parallelism.
