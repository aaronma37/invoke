# Moontide Neural: The Silicon Brain Motherboard

**Stop building monoliths. Start simulating state.**

Moontide Neural is a high-performance, **Synchronous Pulse** runtime engine designed for **Liquid State Machines (LSM)** and **Spiking Neural Networks (SNN)**. It turns the raw silicon of the AMD Zen 5 (AVX-512) into a deterministic, physically isolated assembly line for biological-scale intelligence.

---

## 🧠 The Singular Vision
Moontide rejects the "Transformer/Dense-Matrix" paradigm. Instead, it treats the CPU as a synchronous pulse generator where logic is a "Ripple" and data is the "Liquid." By separating **Eternal Data (Wires)** from **Ephemeral Logic (Nodes)**, we enable a persistent, real-time brain that never stops rippling.

---

## 💎 Core Architectural Pillars

### 1. Synchronous Pulse Scheduling (Clock Domains)
Unlike traditional DAGs, Moontide Neural uses a **Synchronous Pulse Scheduler**.
*   **Recurrence:** Native support for feedback loops (A <-> B) within a single heartbeat.
*   **Deterministic Time:** Double-buffered wires ensure all neurons see a consistent "Last Tick" state, providing bit-perfect temporal accuracy across 32+ threads.
*   **Zen 5 Affinity:** Threads are pinned to specific CCDs (Chiplet Complexes) to keep the "Liquid" state entirely within the 64MB L3 cache of the 9950X.

### 2. Eternal Synaptic Fabric (Wires)
State in Moontide is "Eternal"—it lives outside the logic nodes and persists across reloads.
*   **Sparse Wires:** Optimized for the random-access patterns of synaptic connections.
*   **Silicon Armor:** Hardware-level memory protection (`mprotect`) ensures a single broken synapse triggers a recoverable fault rather than a system crash.
*   **AVX-512 Gathering:** Native Zig SDK support for 512-bit "Gather/Scatter" operations, allowing the update of 16-32 neurons in a single CPU clock cycle.

### 3. Asynchronous Plasticity (Dual-Speed Brain)
Moontide formalizes the separation of **Inference** and **Learning**.
*   **The Fast Path (Thinking):** High-frequency (1000Hz+) nodes simulating "Leaky Integrate-and-Fire" physics.
*   **The Slow Path (Learning):** Background nodes calculating **STDP (Spike-Timing-Dependent Plasticity)** without blocking the inference heartbeat.

### 4. Adaptive Settling (Variable Pulse)
The engine moves beyond fixed frame rates. Nodes can signal the orchestrator that the "Liquid has not yet settled," allowing for variable-length computation cycles based on the complexity of the input spike.

---

## 🏁 Technical Edge (Why AMD?)
Moontide Neural is built to exploit the specific architectural traits of **Zen 5 (9950X)**:
*   **AVX-512 Native Path:** Processing 16 floats per instruction per core.
*   **L3 Cache Dominance:** Keeping the entire 100,000+ neuron reservoir within the high-speed cache.
*   **HSA (Heterogeneous System Architecture):** Zero-copy pointer sharing between the CPU Brain and the GPU Readout.

---

## 🚀 Getting Started

### 1. Build and Install
```bash
zig build
sudo ./zig-out/bin/moontide sdk install
```

### 2. Run the Spiking Pulse Test
```bash
# Execute a basic liquid reservoir simulation on AVX-512
moontide run examples/neural/reservoir_topology.lua
```

---
*Logic is the Ripple, Data is the Liquid. The Moontide is Deterministic.*
