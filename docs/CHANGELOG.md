# Moontide Changelog

## [v0.8.0] - The "Deep Water" Update (PHASE 5 ROADMAP)
*“Beyond the Single Host: Global Scaling.”*

### 🚀 Planned Architectural Shifts
1.  **"Tide-Pool" Network Extension:** A dedicated I/O socket that manages thousands of concurrent connections and pours packets into Ring Buffer Wires.
2.  **Level Journaling (Persistence):** Background streaming of Wire back-buffers to persistent storage without blocking the Heartbeat.
3.  **Cell Partitioning (Dynamic Sub-Graphs):** The ability to spin up independent sub-kernels for different game zones that communicate via Gateway Wires.
4.  Dynamic Topology API (`moontide.load_topology`):** Allow logic nodes to trigger the loading of sub-graph blueprints for seamless level transitions.
5.  **Batch Tick Mode:** A high-speed execution mode that runs a specific number of frames (or until a condition is met) as fast as possible for MCTS rollouts and Monte Carlo simulations.
6.  **CLI `bundle` Command:** One-click packaging of the Moontide kernel, extensions, and assets into a standalone distribution.


---

## [v0.7.0] - The Moontide Shift (COMPLETED)
*“Identity, Reliability, and Silicon Armor.”*

### 🚀 Major Architectural Shifts
1.  **Total Rebrand:** Transitioned from "Invoke" to "Moontide," embracing the cosmic rhythm of Double-Buffering.
2.  **Guard Pages (Silicon Armor):** Implemented hardware-level overflow protection by placing PROT_NONE pages between every wire.
3.  **Deterministic Scheduling:** Hardened the DAG builder to strictly enforce write-exclusivity, ensuring bit-perfect parallelism.
4.  **Global SDK Installation:** Added `moontide sdk install` to distribute Moontide as a system-wide platform.
5.  **Circular Dependency Detection:** The Kernel now identifies and rejects impossible Task Graphs.
6.  **Schema Evolution v2:** Added integrity checks to trigger evolution when the schema string changes, even if size remains constant.

---

## [v0.6.0] - The "Nervous System" Update (COMPLETED)
... (rest of history unchanged)
