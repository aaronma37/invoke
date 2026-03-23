import numpy as np
import os
import glob
import struct
import sys
from sklearn.decomposition import PCA
import json

def load_pcb_displacement(path):
    data = np.fromfile(path, dtype=np.float32).reshape(-1, 9)
    return data[:, 4:7].flatten()

def run_pca(dataset_dir, n_components=8):
    files = sorted(glob.glob(os.path.join(dataset_dir, "vroid_*.pcb")))
    if not files:
        print(f"No .pcb files found in {dataset_dir}")
        return

    print(f"PCA Encoder: Loading {len(files)} models...")
    
    matrix = []
    for f in files:
        matrix.append(load_pcb_displacement(f))
    matrix = np.array(matrix)

    print(f"Computing PCA (Target: {n_components} sliders)...")
    
    # Standardize: Find the variation RELATIVE to the neutral model
    # Neutral is index 0 (vroid_0000)
    neutral_displacement = matrix[0]
    relative_matrix = matrix - neutral_displacement
    
    pca = PCA(n_components=n_components)
    latents = pca.fit_transform(relative_matrix)
    
    # FORCE vroid_0000 to be exactly zero
    neutral_latent = latents[0].copy()
    latents = latents - neutral_latent
    
    # Normalize to [-1, 1] range based on the maximum absolute value found
    max_abs = np.max(np.abs(latents))
    if max_abs > 1e-8:
        latents_norm = latents / max_abs
    else:
        latents_norm = latents

    output_data = {}
    for i, file in enumerate(files):
        name = os.path.basename(file).replace(".pcb", "")
        output_data[name] = latents_norm[i].tolist()

    with open("artifacts/datasets/vroid_latents.json", "w") as f:
        json.dump(output_data, f)
    
    print("Saved slider data to artifacts/datasets/vroid_latents.json")
    print(f"Neutral Model (vroid_0000) Latents: {output_data['vroid_0000']}")
    
    # Check if any slider is just a global constant
    variances = np.var(latents_norm, axis=0)
    print(f"Slider Variances: {variances}")

if __name__ == "__main__":
    run_pca(sys.argv[1])
