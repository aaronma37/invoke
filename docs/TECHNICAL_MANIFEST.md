# The Invoke Technical Manifest

**Invoke** is a high-performance runtime separating "Silicon" (Zig host) from "Software" (AI-logic).

## 1. The Motherboard (Zig Kernel)
A static, high-performance binary (< 2MB) providing the "Universal Silicon" platform.
* **Pure Silicon:** Zero dependencies on `lua.h`.
* **Wire Motherboard:** Allocates and manages raw, typeless `[]u8` memory.
* **The Socket (invoke_abi.h):** A permanent C-ABI contract for all extensions.
* **Topological Scheduler:** Ruthlessly enforces the Heartbeat and Poke cycles.

## 2. The Primary Engine (LuaJIT Extension)
The standard runtime for logic execution.
* **Privileged Extension:** Built using the `invoke_abi.h` but possessing deep knowledge of `lua.h`.
* **Zero-Recompile Schema:** Uses JIT-Type-Casting to lay memory "stencils" over raw wires.
* **Hot-Reloading:** Intercepts script changes and performs the "Pause-Swap-Play" handshake.

## 3. The Handshake (ABI Protocol)
Extensions must implement the following C-interface:
* `init()`: Identify capability and register with Motherboard.
* `bind_wire(name, ptr)`: Receive a memory pointer from the motherboard.
* `execute()`: Run logic for the current heartbeat.
* `shutdown()`: Clean up logic state.

## 4. Universal Development
| Aspect | Mechanism |
| :--- | :--- |
| **Persistence** | Logic is swapped; Wires (RAM) remain constant. |
| **Ubiquity** | The same kernel runs on any hardware; only extensions change. |
| **Efficiency** | Worker AI context is isolated to a single Node + Wire Schema. |
