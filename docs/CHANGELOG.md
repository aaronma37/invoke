# Invoke Changelog

## [v0.7.0] - Indestructible Isolation (PLANNING)
*“The Watchdog and the Jail: Total Fault Tolerance.”*

### 🚀 Planned Architectural Shifts
1.  **Execution Watchdog:** Forcible interruption of infinite loops/deadlocks.
2.  **Strike System (Jailing):** Automatically disabling nodes that crash repeatedly until hot-swapped.
3.  **Forensic Crash Logs:** CPU register and context dumping via `invoke.log`.

---

## [v0.6.0] - The "Nervous System" Update (COMPLETED)
*“Cross-Namespace Messaging and Thread-Safe Triggers.”*

### 🚀 Major Architectural Shifts
1.  **Cross-Namespace Poke (`invoke.poke`):** Implemented a global, tag-based event bus. Nodes can now trigger reactions in other namespaces without memory dependencies.
2.  **Thread-Safe Event Queue:** Developed a Mutex-protected queue in the Orchestrator to handle simultaneous "pokes" from parallel worker threads.
3.  **Atomic ABI Evolution:** Extended the Silicon ABI to include host-side event registration.

---

## [v0.5.0] - The "Chameleon Kernel" (COMPLETED)
*“Parallelism as a Switch: The Assembly Line Model.”*

### 🚀 Major Architectural Shifts
1.  **Double-Buffered Wires:** Implemented Front/Back memory banks. Reads are gated to Front (stable); Writes are gated to Back (ephemeral).
2.  **Multicore DAG Scheduler:** The Kernel now performs topological dependency analysis and dispatches independent nodes to a `std.Thread.Pool`.
3.  **Thread-Local Recovery:** Decentralized the signal recovery system. Crashes are now isolated to individual worker threads, ensuring the rest of the motherboard continues.
4.  **Barrier Synchronization:** Implemented `WaitGroup` barriers between execution levels to ensure deterministic frame results.

---

## [v0.4.5] - The "Armor & Telemetry" Update (COMPLETED)
...
### 🚀 Major Architectural Shifts

#### 1. Granular Silicon Gating (mprotect)
*   **Hardware Enforcement:** The Motherboard now surgically unlocks only the requested memory permissions (`PROT_READ` vs `PROT_WRITE`) based on the topology bindings.
*   **Violation Recovery:** Successfully verified that illegal memory access triggers a segfault which is caught and recovered from without halting the heartbeat.

#### 2. Schema Evolution & Migration
*   **Eternal Data:** Changing a wire's schema mid-execution now triggers an automatic data migration. The kernel maps old fields to new offsets by name, ensuring state survives architectural shifts.

#### 3. Global Engine Logging (`invoke.log`)
*   **Universal Telemetry:** Implemented a host-side logging callback in the ABI. Both Lua and WASM nodes can now send structured, severity-leveled messages back to the Kernel.
*   **Context Enrichment:** Logs are automatically prefixed with the Node's full path for precise debugging.

#### 4. WASM Guest SDK
*   **Invoke SDK:** Created a lightweight Zig SDK for WASM nodes, abstracting away manual offset management and providing clean logging/wiring interfaces.
*   **Performance:** Optimized the WASM extension to cache function exports, reducing frame overhead to near-zero.

---

## [v0.4.0] - The "Motherboard" Refactor (COMPLETED)
*“Stripping the Kernel: Modular Ubiquity.”*

---

## [v0.3.0] - The "Universal Silicon" Update
*“The Engine that Never Stops: Architecture as Sculpting.”*

### 🚀 Major Architectural Shifts

#### 1. Graph Hot-Reloading (The "Universal Silicon" Milestone)
*   **Idempotent Orchestration:** The host can now reload `topology.json` mid-execution. If a wire already exists, its memory and data are preserved ("Eternal Data").
*   **Surgical Architecture Swaps:** Adding new namespaces, wires, or re-binding node connections no longer requires a restart. The host detects changes to the graph and applies them in a "Pause-Swap-Play" sequence.
*   **Real-Time Sculpting:** Developers (or AIs) can now evolve the entire system architecture while the application is running, seeing the results in milliseconds.

#### 2. Pro-Mode Host Monitor
*   **Cross-System Monitoring:** Updated the Zig host to monitor and print state across different namespaces (e.g., tracking how `environment.wind` affects `player.stats`).
*   **Dynamic Binding Logic:** Improved the host's ability to resolve both local and global wire paths during node initialization.

---

## [v0.2.0] - The Namespaced Topology Update
*“Logic is Ephemeral, Data is Eternal, Spaghetti is Solved.”*

### 🚀 Major Architectural Shifts

#### 1. Namespaced Topology (The "Spaghetti Fix")
*   **Hierarchical Addressing:** Migrated from a flat node list to a `StringHashMap` that supports full path namespacing (e.g., `player.stats`, `environment.wind`).
*   **System Isolation:** Systems are now physically isolated. A node in the `player` namespace can only see wires it is explicitly granted access to in the topology, preventing "global variable pollution."
*   **AI "Zoom":** This allows the Architect AI to reason about individual systems (like `Combat_System`) without loading the context of the entire engine.

#### 2. Graph DSL Bootstrapping (`topology.json`)
*   **Configuration-as-Code:** The engine now completely bootstraps itself from a single JSON file. The host no longer has hardcoded logic for what nodes or wires exist.
*   **Runtime Schema Calculation:** Added `CalculateSchemaSize` to `schema.zig`. The host now calculates the exact byte-alignment and size requirements for wires defined in JSON strings at runtime.
*   **Dynamic Wiring:** Implemented an automatic "Binding" phase. During boot, the host reads the `reads` and `writes` arrays in the JSON and injects the corresponding memory pointers directly into the specific Nodes.

#### 3. Raw Wire Architecture (The "Eternal Data" Pillar)
*   **Typeless Memory Buffers:** Replaced typed Zig structs with `RawWire` (`[]u8` buffers). This ensures that memory is just a flat block of bytes. 
*   **C-ABI Integrity:** Nodes (LuaJIT/C) use FFI to "cast" these raw bytes back into their local schemas. This allows for **Zero-Overhead Hot-Swapping**: you can change the logic of a node, but the raw bytes on the wire remain exactly where they were, preserving the state (e.g., Player X/Y).

---

### 🛠️ Technical Hardening

#### LuaJIT Bridge Stability
*   **Global Variable Mapping:** Implemented a translation layer that converts namespaced wire paths (e.g., `environment.wind`) into Lua-safe global identifiers (e.g., `wire_environment_wind`).
*   **Pointer Stability:** Fixed critical segmentation faults by ensuring that null-terminated string pointers for Lua's C-API are stable and correctly allocated during the Node's lifecycle.
*   **Hot-Reloading:** Refined the `mtime` (modification time) check so that each individual Node independently monitors its own script file for changes, allowing for surgical logic updates mid-execution.

#### Multi-System Verification (The "Wind" Test)
*   **Cross-Namespace Communication:** Successfully proved that the `environment` system can generate data (Wind force) and the `player` system can react to it, despite neither system knowing the other exists.
*   **Live Feedback:** A stable, heartbeat-driven loop where the Host Monitor tracks the interplay between isolated systems in real-time.

---

### 📁 File Impact

| File | Status | Description |
| :--- | :--- | :--- |
| `topology.json` | **NEW** | The single source of truth for the engine's structure. |
| `src/core/orchestrator.zig` | **UPDATED** | Manages namespaced hash maps for wires and nodes. |
| `src/core/wire.zig` | **UPDATED** | Implements the `RawWire` flat-memory model. |
| `src/core/node.zig` | **UPDATED** | Handles LuaJIT state, hot-reloading, and wire binding. |
| `src/main.zig` | **UPDATED** | Acts as the JSON bootstrapper and host monitor. |
| `docs/CHANGELOG.md` | **NEW** | This file. |

---

## [v0.1.0] - The Initial Prototype
*   Zig host scaffolded with `build.zig`.
*   Initial `Wire(T)` and `Node` types.
*   Basic `Orchestrator` tick loop.
*   `Sandbox` validation logic added.
*   Successful "Hello World" of the Zig-to-LuaJIT memory bridge.
