# VAE & LoRA Strategy for Geometric KANs

To achieve the ultimate goal of an "Asset Maker" with sliders and toggles, we must expand the Moontide engine from training *single* geometric KANs to training *families* of KANs. This document outlines the architectural roadmap for integrating Variational Autoencoders (VAEs) and Low-Rank Adaptation (LoRA) into the KAN ecosystem.

---

## 1. The VAE: The "Sliders" (Latent Space Interpolation)

Currently, our KAN takes an input `(u, v)` and outputs a `displacement`. To get sliders, the KAN must take an input of `(u, v, z_1, z_2, ..., z_n)`, where `z` is a latent vector representing geometric style (e.g., $z_1$ = sleeve length, $z_2$ = bagginess).

### How to build it:
1. **Dataset Generation:**
   * Generate 1,000 different shirts using TripoSR.
   * Run the Vulkan `uv_sampler.zig` 1,000 times against the *same* Base Human Mesh.
   * You now have a massive tensor of shape `[1000, Num_Vertices, Displacement]`.
2. **The Autoencoder Architecture:**
   * **Encoder (Standard MLP/Conv):** Takes the full displacement map of a shirt and compresses it down into a tiny Latent Vector `z` (e.g., 8 or 16 float values).
   * **Decoder (The KAN):** Takes the `(u, v)` coordinate *and* the Latent Vector `z` as inputs to the first layer, and attempts to reconstruct the displacement.
3. **The Resulting Workflow:**
   * In the game engine, you expose the 8 float values of `z` as UI Sliders. 
   * As the user drags a slider, the `z` vector changes. The KAN smoothly interpolates the geometry between a t-shirt and a winter coat in real-time.

---

## 2. LoRA (Low-Rank Adaptation): The "Toggles" (Style Overlays)

If a VAE defines the overall *shape*, a LoRA defines the *fine details and textures*. Instead of training a new KAN for "leather texture" vs "cloth texture", we train a LoRA.

### How it maps to KANs:
In a standard MLP, a LoRA is $W' = W + (A \times B)$, where $A$ and $B$ are tiny matrices.
In our KAN, the "weights" are the B-spline coefficients in memory (`kan.coeffs`).

1. **The Base KAN:** Train a highly accurate KAN on a smooth, generic t-shirt. This is the frozen base model.
2. **Training the LoRA:**
   * Take a TripoSR target that has a complex chainmail texture.
   * Freeze the Base KAN's coefficients.
   * Introduce a LoRA matrix (a very small set of trainable parameters) that *adds* onto the B-spline coefficients during the forward pass.
   * Train *only* the LoRA to map the high-frequency chainmail details.
3. **The Resulting Workflow:**
   * The Vulkan shader loads the Base KAN.
   * The UI has a toggle: `[x] Apply Chainmail`.
   * When checked, the engine instantly adds the LoRA matrix to the `kan.coeffs` buffer in Vulkan VRAM. The shirt instantly gains the chainmail displacement.

---

## 3. The Implementation Roadmap

To make this a reality without breaking the current high-speed Zig engine, the following architectural steps are required:

### Step 1: N-Dimensional Input Support (Zig Core)
Currently, `KanLayer` is hardcoded for `3 -> 32 -> ...`. We need the first layer to accept dynamic input dimensions `(u, v, z_0...z_n)`. This requires updating `kan_dataloader.zig` to feed latent vectors alongside spatial coordinates.

### Step 2: The Multi-Target Loss Function (Zig Trainer)
The trainer must be updated to handle "Batch of Batches". Instead of training 1 shape on 16 threads, it needs to train 16 different shapes simultaneously, calculating the reconstruction loss across the entire Latent Space.

### Step 3: LoRA Coefficient Addition (Vulkan / Zig Inference)
We need a simple utility in `projects/kan_viewer/` that can take two binary files (`base.kan` and `chainmail.lora.kan`) and merge their coefficients in memory before passing them to the Vulkan Compute Shader.

### Summary
* **VAE:** Modifies the *Inputs* (adding `z`). Gives continuous Sliders.
* **LoRA:** Modifies the *Coefficients* (adding $\Delta W$). Gives discrete Toggles.