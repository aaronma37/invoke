# Invoke Changelog

## [v0.4.0] - The "Motherboard" Refactor (PLANNING)
*“Stripping the Kernel: Modular Ubiquity.”*

### 🚀 Planned Architectural Shifts

#### 1. Decoupled Runtimes (Extensions)
*   **Kernel Stripping:** Move LuaJIT and Wasmtime out of the core binary into dynamic shared libraries (`ext/luajit_ext.so`, `ext/wasm_ext.so`).
*   **Dynamic Loading:** Implement `std.DynLib` support in the Zig host to load extensions based on `topology.json`.
*   **Chameleon Scaling:** Enable the engine to run on tiny hardware by only loading necessary extensions.

#### 2. Stable Silicon ABI
*   **The Socket:** Define a stable C-header (`invoke_abi.h`) that serves as the permanent interface between the Motherboard and Extensions.
*   **Binary Portability:** Ensure that extensions compiled for one Invoke Core version work on future versions without re-linking.

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
