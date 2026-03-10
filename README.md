# Invoke: The AI-Native Runtime Engine

**Invoke** is a high-performance, minimalist runtime designed for the era of "AI-sculpted" software. It separates stable, compiled infrastructure (**Silicon**) from ephemeral, hot-swappable logic (**Software**).

## 🏗️ Core Pillars
- **Eternal Data (Wires):** State lives on raw, page-aligned memory buffers (`mmap`) that persist across logic reloads.
- **Ephemeral Logic (Nodes):** Business logic is written in **LuaJIT** or **Wasm**. Nodes are "pluggable" sockets with explicit `reads` and `writes` bindings.
- **Granular Silicon Gating:** The kernel enforces hardware-level memory protection (`mprotect`) based on the node's topology, preventing illegal memory access.
- **Indestructible Heartbeat:** A robust signal recovery system (`setjmp`/`longjmp`) allows the kernel to survive and recover from crashes in user logic.

## 📂 Repository Structure
- `src/`: The Zig Kernel (Pure Silicon).
- `sdk/`: The stable C-ABI (`invoke_abi.h`) and Guest SDKs.
- `extensions/`: Runtime extensions (LuaJIT, Wasm) compiled as shared libraries.
- `examples/`: Reference implementations and sandbox tests.
- `gen/`: (Generated) Runtime headers and offsets for logic modules.

## 🛠️ Getting Started

### 1. Build the Motherboard
```bash
zig build
```
This produces the `invoke` kernel in `zig-out/bin/` and shared extensions in `ext/`.

### 2. Run the Sandbox
The sandbox demonstrates cross-language communication between Lua (Wind System) and WASM (Physics System):
```bash
# 1. Compile the WASM node
zig build-exe examples/sandbox/physics.zig -target wasm32-freestanding -rdynamic -O ReleaseSmall -fno-entry -femit-bin=examples/sandbox/physics.wasm -I gen -I sdk

# 2. Boot the Kernel
./zig-out/bin/invoke run examples/sandbox/topology.json
```

## 🚀 Feature Roadmap
- [x] **Indestructible Heartbeat** (v0.1.0)
- [x] **Namespaced Topology** (v0.2.0)
- [x] **Eternal Data (Wires)** (v0.3.0)
- [x] **Granular Silicon Gating** (v0.4.0)
- [x] **Schema Evolution & Migration** (v0.4.5)
- [ ] **Invoke Standard Library** (v0.5.0) - *In Progress*
- [ ] **Cross-Namespace Messaging** (v0.6.0)
- [ ] **Visual Topology Inspector** (v1.0.0)

---
*Logic is Ephemeral, Data is Eternal.*
