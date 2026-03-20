# The Moontide Neural Philosophy

**Moontide Neural** is a fundamental rejection of the "Batch Inference" world. It is a biological-scale runtime engine designed for the era of **Always-On Edge Intelligence.**

## I. The Core: "Pure Spiking Silicon"
The Moontide Kernel is no longer a general-purpose DAG runner. It is an **Oscillator.**
*   **The Responsibility:** It manages **Memory (The Liquid)** and **Synchrony (The Pulse).**
*   **Strict Isolation:** The Kernel treats all neural nodes as ephemeral mathematical transformations. It enforces bit-perfect consistency through double-buffering.
*   **The Benefit:** It turns a consumer laptop into a deterministic neuromorphic brain capable of processing spikes with nanosecond latency.

## II. The Standard: "The Liquid State"
While traditional AI is "Stateless" (requiring a context window for memory), Moontide is **"Inherently Stateful."**
*   **History in the Ripples:** The "Liquid" is a reservoir of spiking neurons that naturally stores the history of the system in its physical ripples.
*   **Eternal Data:** Because the reservoir state is a **Wire** in RAM, it persists across node hot-reloads. You can update the physics of the brain without ever draining the reservoir.

## III. The Workflow: "Synaptic Sculpting"
Moontide is designed for a world where AI is modeled after biology.
*   **Inference (Fast):** Millions of simple, leaky integrate-and-fire neurons ticking at 1000Hz+ using AVX-512.
*   **Learning (Slow):** STDP (Spike-Timing-Dependent Plasticity) nodes that analyze the "History" of the wires and modify weights in the background.
*   **Infinite Iteration:** You "sculpt" the connectivity of the system in real-time, modifying the Synaptic Fabric while the engine is running.

## IV. The Concurrency: "Synchronous Pulse"
We reject the DAG-based topological sort in favor of **Synchronous Pulse Domains.**
*   **Global Heartbeat:** Every 1ms (or faster), all nodes in a domain pulse simultaneously.
*   **Shared Silicon:** All threads are pinned to specific CCDs on the 9950X to ensure that the entire brain fits within the L3 cache, eliminating the cross-chiplet latency bottleneck.

## V. Summary of the "Neural Handshake"
| Component | Responsibility | Knowledge of Logic | Knowledge of Data |
| :--- | :--- | :--- | :--- |
| **Kernel** | Oscillator (Silicon) | No (Strict Isolation) | Yes (Synchrony) |
| **Synaptic Fabric** | The Liquid (Wire) | No (Pure Memory) | Yes (Connectivity) |
| **Pulse Node** | The Ripple (Logic) | Internal Only | Indirect (via SDK) |

---

## The Core Mantra: Logic is the Ripple, Data is the Liquid.
In Moontide Neural, the "Object" is dead. State lives in the **Synaptic Fabric** (Eternal), and behavior lives in the **Pulse Nodes** (Ephemeral). This separation enables a scale of real-time, deterministic intelligence that monolithic, discrete-time systems cannot achieve.
