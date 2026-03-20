# The Moontide Neural Technical Manifest

**Moontide Neural** is a high-performance runtime for neuromorphic intelligence, separating "Silicon" (Zig host) from "The Liquid" (Neural state).

## 1. The Pulse Oscillator (Zig Kernel)
The core kernel is no longer a general-purpose scheduler. It is a **Synchronicity Engine.**
*   **Pure Silicon:** Zero dependencies on `lua.h`.
*   **Synchronous Pulse Scheduling:** Replaces the DAG with fixed-frequency "Clock Domains" for synchronous neuronal updates.
*   **Silicon Armor:** Enforces memory protection on Synaptic Wires using `mprotect`.
*   **The Socket (moontide_abi.h):** A permanent C-ABI contract for Pulse and Learning extensions.

## 2. Eternal Synaptic Fabric (Wires)
State lives on raw, page-aligned memory buffers that persist across logic reloads.
*   **Double-Buffer Pulse:** Wires are "Banks" (Front/Back). Reads come from Front (Time $T$); Writes go to Back (Time $T+1$). The Kernel performs a Pointer Swap at the end of the Pulse.
*   **Sparse Connections:** Supports Indirection Tables for non-contiguous synaptic connectivity between neurons.
*   **Gather-Scatter Optimized:** Specifically designed to leverage the **AVX-512** path on Zen 5 hardware.

## 3. Ephemeral Neural Logic (Nodes)
Brain behavior is isolated into "pluggable" sockets.
*   **The Inference Node:** Executes high-speed, leaky integrate-and-fire math. 
*   **The Learning Node:** Executes background plasticity algorithms (STDP) without disrupting the inference heartbeat.

## 4. Hardware-Aware Concurrency
Moontide Neural is "Silicon-Aware" for the 9950X:
*   **CCD Pinning:** Threads are manually affinity-pinned to specific chiplets to maximize L3 cache hits.
*   **Infinity Fabric Bypass:** Data flow between neurons is kept local to a CCD whenever possible to eliminate the cross-chiplet latency bottleneck.

## 5. Summary of the Neural Stack
| Aspect | Mechanism |
| :--- | :--- |
| **Synchrony** | Synchronous Pulse Scheduling replaces DAG dependency sorting. |
| **Performance** | Native AVX-512 "Gather/Scatter" for sparse neural graphs. |
| **Reliability** | Hardware-level memory protection for every synaptic connection. |
| **Scalability** | Asynchronous plasticity (STDP) running on background cores. |

---
*The goal is bit-perfect, deterministic neuromorphic intelligence at the raw speed of the silicon gates.*
