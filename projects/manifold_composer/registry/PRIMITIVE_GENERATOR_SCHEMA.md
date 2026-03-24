# Primitive Generator Schema (v1)

Every **Primitive Generator** in the library must have a corresponding `.json` entry in this registry. This metadata allows the LLM to understand the mathematical capabilities of the generator.

## Field Definitions

| Field | Description |
| :--- | :--- |
| `generator_id` | Unique string name (e.g., `gen_cylinder_v1`). |
| `type` | `neural` (KAN-based) or `functional` (Code-based). |
| `topology_type` | `open`, `periodic_u` (tube), `periodic_uv` (torus), or `capped`. |
| `definition` | Path to `.kan` binary OR the raw source code (Lua/GLSL). |
| `topology` | e.g., `[2, 32, 32, 3+K]`. |
| `sockets` | Available boundary interfaces for mathematical welding. |
| `semantic_channels` | Discoverable anchors (e.g., `C1: button_zone`). |
| `latent_space` | Procedural parameters (e.g., `z0: length`). |
| `forge_params` | (Neural Only) Parameters used by **The Forge** to train this behavior. |

## Socket Contract
Each socket defines an edge of the generator's internal coordinate space:
*   `v=0`: Primary Input Socket.
*   `v=1`: Primary Output Socket.
*   `u=0/1`: Auxiliary Sockets.

## Generator Traceability
Every neural entry includes a `forge_params` object. This ensures that the mathematical behavior can be re-trained or extended if the LLM requests a variation that the current latent space cannot reach.
