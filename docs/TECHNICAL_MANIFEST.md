# The Moontide Technical Manifest

**Moontide** is a high-performance runtime separating "Silicon" (Zig host) from "Software" (AI-logic).

## 1. The Motherboard (Zig Kernel)
A static, high-performance binary (< 2MB) providing the "Universal Silicon" platform.
*   **Pure Silicon:** Zero dependencies on `lua.h`.
*   **Silicon Gating:** Ruthlessly enforces hardware-level memory protection (`mprotect`) on Wires.
*   **The Socket (moontide_abi.h):** A permanent C-ABI contract for all extensions.
*   **Chameleon Scheduler:** A dependency-aware DAG executor that can toggle between Deterministic (Double-Buffered) and Dynamic (Single-Buffered) execution.

## 2. Eternal Data (Wires)
State lives on raw, page-aligned memory buffers that persist across logic reloads.
*   **Double-Buffer Switch:** Wires can be "Banks" (Front/Back). Reads come from Front; Writes go to Back. The Kernel performs a Pointer Swap at the Frame Barrier.
*   **Zero-Recompile Schema:** Uses JIT-Type-Casting to lay memory "stencils" over raw wires.
*   **Schema Evolution:** Automated data migration when topology fields shift mid-execution.

## 3. Ephemeral Logic (Nodes)
Application behavior is isolated into "pluggable" sockets.
*   **Indestructible Heartbeat:** Robust signal recovery ensures the Motherboard survives crashes in user logic.
*   **Universal SDK:** Standardized logging (`moontide.log`) and services provided by the host via the ABI.

## 4. The Handshake (ABI Protocol)
Extensions must implement the following C-interface:
*   `init()`: Identify capability and register with Motherboard.
*   `bind_wire(name, ptr, access)`: Receive a memory pointer and permission level.
*   `execute()`: Run logic for the current heartbeat.
*   `set_log_handler(fn)`: Receive the host's telemetry callback.

## 4. Data Layout Freedom (SOA vs AOS)
Moontide is **Layout-Agnostic**. The Kernel provides raw memory; the AI defines the orientation.

*   **AOS (Array of Structures):** Perfect for "Brain" nodes. The AI defines a complex wire (e.g., `stats: {x, y, hp}`). This is easy for logic but slower for the CPU cache.
*   **SOA (Structure of Arrays):** Perfect for "Muscle" nodes (SIMD). The AI defines separate wires (e.g., `pos_x`, `pos_y`, `health`). This keeps the CPU cache hot and enables zero-copy vectorized processing.
*   **The Switch:** Refactoring from AOS to SOA—which takes weeks in a traditional engine—is a 10-second change to the `topology.json` in Moontide.

## 5. Universal Development
| Aspect | Mechanism |
| :--- | :--- |
| **Persistence** | Logic is swapped; Wires (RAM) remain constant. |
| **Ubiquity** | The same kernel runs on any hardware; only extensions change. |
| **Efficiency** | Worker AI context is isolated to a single Node + Wire Schema. |
