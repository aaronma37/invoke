# The Moontide KAN Philosophy

**Moontide** is a fundamental rejection of the "Discrete Matrix" AI world. It is a high-precision, continuous-parameterization engine designed for the era of **Neurosymbolic Geometry.**

## I. The Core: "Spline Sculpting"
The Moontide Kernel is no longer a general-purpose DAG runner. It is a **Geometric Compiler.**
*   **The Responsibility:** It manages **Grids (The Topology)** and **Splines (The Activation).**
*   **Strict Isolation:** The Kernel treats all KAN nodes as continuous mathematical transformations. It enforces bit-perfect consistency through analytical gradients.
*   **The Benefit:** It turns a consumer laptop into a high-performance training workstation capable of fitting complex 3D volumes into minimal spline coefficients.

## II. The Standard: "Continuous Representation"
While traditional 3D is "Discrete" (using millions of triangles or voxels), Moontide is **"Inherently Continuous."**
*   **Shape in the Curves:** Geometry is not a set of vertices; it is a mathematical field stored in the coefficients of B-splines.
*   **Infinite Resolution:** Because the representation is a function $f(X, Y, Z)$, you can query the surface at any level of detail without ever seeing a polygon edge.

## III. The Workflow: "Grid Evolution"
Moontide is designed for a world where geometry is modeled after continuous signals.
*   **Coarse Training (Fast):** Learning the basic volumetric shape using low-resolution spline grids.
*   **Fine Training (Precise):** Dynamically doubling the grid density (Grid Extension) to capture high-frequency details (pores, fabric, rivets) in the final training passes.
*   **Sparsification:** Pruning unnecessary edges and coefficients to reach the mathematical limit of geometric compression.

## IV. The Concurrency: "Segmented Training"
We reject monolithic training in favor of **Modular KANs.**
*   **Modular Training:** Each body part (arm, torso, armor plate) is trained as a separate, specialized KAN.
*   **Shared Silicon:** All threads are pinned to specific CCDs on the 9950X to ensure that the entire spline grid fits within the L3 cache, eliminating the cross-chiplet latency bottleneck.

## V. Summary of the "Geometric Handshake"
| Component | Responsibility | Knowledge of Logic | Knowledge of Data |
| :--- | :--- | :--- | :--- |
| **Kernel** | Spline Compiler (Silicon) | No (Strict Isolation) | Yes (Knot Vectors) |
| **Grid** | The Grid (Wire) | No (Pure Memory) | Yes (Coefficients) |
| **KAN Node** | The Curve (Logic) | Internal Only | Indirect (via B-splines) |

---

## The Core Mantra: Logic is the Spline, Data is the Grid.
In Moontide, the "Pixel" is dead. State lives in the **Spline Grid** (Continuous), and behavior lives in the **Analytical Activation** (Mathematical). This separation enables a scale of geometric precision and data density that discrete-time systems cannot achieve.
