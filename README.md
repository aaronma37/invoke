# Moontide: The AI-Native DAG Runtime

**Stop building monoliths. Start sculpting data-flow.**

Moontide is a high-performance, **Data-Oriented DAG (Directed Acyclic Graph)** runtime engine. It is designed to be the "Silicon Motherboard" for AI-generated software, replacing traditional monolithic architectures with a physically isolated, deterministic assembly line.

---

## 💎 Features & Subfeatures

### 1. The Indestructible Core (Silicon Armor)
The Zig-based kernel is a high-security host that treats code as hostile and data as sacred.
*   **Silicon Gating:** Hardware-level memory protection via `mprotect`. Nodes can only touch the wires they are explicitly connected to.
*   **Guard Pages:** Every data wire is separated by a 4KB `PROT_NONE` "dead zone." Any buffer overflow triggers an immediate, recoverable hardware fault.
*   **Indestructible Heartbeat:** Robust signal recovery using `setjmp/longjmp`. The engine survives segfaults and memory violations in user logic.
*   **Execution Watchdog:** A background sentry that monitors node budget. Nodes that hang or exceed their 100ms cycle are forcibly terminated.
*   **Node Jailing (Strike System):** Broken nodes are given "strikes." After 3 failures, they are jailed (disabled) to protect the heartbeat until hot-swapped.

### 2. The Eternal Library (Persistence)
State in Moontide is "Eternal"—it lives outside the logic nodes and persists across reloads and sessions.
*   **Eternal Data (Wires):** Page-aligned, raw memory buffers mapped directly to C-ABI structs.
*   **Binary Snapshots (`.tide` files):** Instant serialization of the entire machine state to disk.
*   **Deep Persistence:** Bit-perfect Save/Load functionality. Restore a 100,000-entity simulation to the exact CPU state in milliseconds.
*   **Schema Evolution:** Change your data layout mid-execution. The kernel automatically detects shifts and migrates existing data to the new schema without a restart.
*   **Type-Change Integrity:** Protection against "Ghost Data." The kernel clears/re-initializes wires if the schema string changes, even if the size remains the same.

### 3. Deterministic Flow (The Assembly Line)
The Moontide scheduler turns your CPU into a rhythmic assembly line.
*   **Multicore DAG Scheduler:** Automatic topological sorting of nodes. Independent systems run in parallel on all available cores.
*   **The Shifting Tide (Double-Buffering):** Nodes read from the "Front" bank and write to the "Back" bank. No mutexes or locks are ever required.
*   **Write-Exclusivity Enforcement:** The scheduler prevents non-determinism by ensuring only one node can write to a specific wire in any parallel level.
*   **Bit-Perfect Replication:** 100% deterministic output. Running the same sim with the same seed results in identical binary state across different machines.

### 4. AI-Native Workflow (Token Efficiency)
Designed specifically for the era of "Vibe Coding" and LLM-driven development.
*   **Context Isolation:** Radical reduction in LLM context requirements. A worker AI only needs the Wire Schema and the Node logic, not the whole repo.
*   **Programmatic Topology:** Define your architecture in Lua. Use loops and logic to procedurally generate massive parallel worlds.
*   **Real-Time Sculpting:** Instant hot-reloading. Save a script or update the topology and see the changes reflected in the running engine instantly.
*   **Cross-Namespace Messaging (`moontide.poke`):** A thread-safe, global event bus for decentralized system communication.

### 5. Polyglot Handshake (Universal Socket)
Moontide is a platform-agnostic socket for the existing software ecosystem.
*   **Stable C-ABI:** A permanent handshake contract between the kernel and logic nodes.
*   **LuaJIT Runtime:** Native-speed logic with the flexibility of a scripting language.
*   **WASM Runtime:** Sandboxed, high-performance execution using Wasmtime.
*   **Global SDK Distribution:** `moontide sdk install` makes Moontide a first-class citizen of your operating system.

---

## 🏁 Quick Start

### 1. Build and Install
```bash
# Build the kernel and extensions
zig build

# Install the SDK and standard runtimes globally
sudo ./zig-out/bin/moontide sdk install
```

### 2. Scaffold a New Project
```bash
mkdir my_sim && cd my_sim
moontide init
```

### 3. Run a Simulation
```bash
# Execute the high-performance parallel boids simulation
moontide run examples/boids/topology.lua
```

---
*Logic is Ephemeral, Data is Eternal. The Moontide is Deterministic.*
