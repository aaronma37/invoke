# Manifold Composer: Development Roadmap

## Phase 1: Perfect Pinning (Mathematical Core)
*   **Goal:** Perfect $C^0$ continuity between any two KANs.
*   **Action:** Update `manifold_kan.zig` to correctly map a 1D spline across the 2D coefficient grid of a B-spline surface.
*   **Success Metric:** A MoonCrust visualization showing zero gaps between a Trunk and its Branch.

## Phase 2: The Primitive Library (Training)
*   **Goal:** A small library of pre-trained "Puzzle Pieces" with built-in semantics.
*   **Action:** Train KANs on synthetic geometry with **Multi-Channel Heatmaps**:
    *   **`cylinder.kan`**: Tube manifold with Top/Bottom sockets and a "branching" confidence channel.
    *   **`fork.kan`**: One Bottom socket, multiple Top sockets.
    *   **`cap.kan`**: One Bottom socket, closed Top, and "feature" channels (e.g., eyes, buttons).
*   **Action:** Implement **Latent Interpolation** (`Z-Vector`) so the LLM can control thickness, curvature, and detail for each piece.

## Phase 3: The LLM Orchestrator (Logic)
*   **Goal:** Structural autonomy.
*   **Action:** Define a JSON Schema for "Constructive Geometry."
*   **Action:** Implement a Lua orchestrator that:
    1.  Parses the JSON.
    2.  Allocates KANs from the library.
    3.  Performs the recursive pinning-solve (Root -> Leaves).
*   **Success Metric:** LLM generates a unique multi-armed creature or complex tree from scratch.

## Phase 4: Vulkan Visualization & Export
*   **Goal:** Professional-grade rendering.
*   **Action:** Implement a Vulkan compute shader to evaluate the whole DAG and perform **Dual Contouring** for mesh generation.
*   **Action:** Export the resulting manifold as a rigged `.glb` or `.obj`.
