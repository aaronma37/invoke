# The Invoke Philosophy

**Invoke** is an AI-native runtime engine. It is a fundamental rejection of monolithic software, redesigned for the era of "Vibe Coding."

## I. The Core: "Pure Silicon" (Zig)
The Invoke Kernel is a minimalist, compiled binary. It is the **Motherboard** that provides the physical infrastructure for data.
* **The Responsibility:** It handles only three things: Memory Allocation (Wires), Execution Scheduling (The Heartbeat), and Hardware I/O (Vulkan/Drivers).
* **Strict Isolation:** The Kernel does **not** include `lua.h` or any language-specific headers. It treats all logic as "Opaque Nodes" via a stable C-style ABI.
* **The Benefit:** This makes the kernel tiny (< 2MB), portable, and immune to crashes from the logic layer.

## II. The Standard: "The Primary Engine" (LuaJIT)
While technically an extension, LuaJIT is the **soul** of Invoke. it is the recommended, default choice for 99% of development.
* **Privileged Integration:** Shipped in the "Standard Distribution." To the hardware, it is a modular plugin; to the user, it is the primary interface.
* **FFI Stenciling:** It uses a "Shim" to map Zig’s raw memory wires directly into LuaJIT’s FFI tables for C-speed execution with instant hot-reloading.
* **The Benefit:** You get the speed of thought. You can rewrite combat logic or graphics math while the app is running, without ever touching a compiler.

## III. The Workflow: "AI-Native Sculpting"
Invoke is designed for a world where AI is the primary author of code.
* **The Architect (Macro):** Manages the "Big Picture"—wiring nodes together in `topology.json` and defining memory schemas.
* **The Worker (Micro):** Writes tiny, stateless Lua scripts inside the nodes.
* **Infinite Iteration:** Because Wires hold the state, you can swap Lua logic a thousand times a minute. The AI "sculpts" the behavior of the system in real-time.

## IV. Summary of the "Invoke Handshake"
| Component | Language | Knowledge of `lua.h` | Knowledge of `abi.h` |
| :--- | :--- | :--- | :--- |
| **Kernel** | Zig | No (Strict Isolation) | Yes (The Contract) |
| **Extension** | Zig/C | Yes (The Bridge) | Yes (The Contract) |
| **Node** | Lua | Internal Only | Indirect (via FFI) |

---

## The Core Mantra: Logic is Ephemeral, Data is Eternal.
In Invoke, the traditional concept of an "Object" is destroyed. State lives on **Wires** (eternal), and behavior lives in **Nodes** (ephemeral). This separation allows for fearless experimentation and radical token efficiency.
