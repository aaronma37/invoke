import numpy as np
import os
import glob
import struct
import sys
from sklearn.decomposition import PCA
import json

def load_pcb_displacement(path):
    # PointSample: x,y,z, sdf, r,g,b, rough, metal (9 floats)
    # Our displacement vector (dx, dy, dz) is in r, g, b (indices 4, 5, 6)
    data = np.fromfile(path, dtype=np.float32).reshape(-1, 9)
    return data[:, 4:7].flatten() # Returns [dx0, dy0, dz0, dx1, dy1, dz1, ...]

def run_pca(dataset_dir, n_components=16):
    files = sorted(glob.glob(os.path.join(dataset_dir, "vroid_*.pcb")))
    if not files:
        print(f"No .pcb files found in {dataset_dir}")
        return

    print(f"PCA Encoder: Loading {len(files)} models...")
    
    # Pre-allocate matrix [Num_Models, Num_Vertices * 3]
    first_model = load_pcb_displacement(files[0])
    feature_count = len(first_model)
    matrix = np.zeros((len(files), feature_count), dtype=np.float32)
    
    matrix[0] = first_model
    for i in range(1, len(files)):
        matrix[i] = load_pcb_displacement(files[i])
        if i % 50 == 0:
            print(f"  Loaded {i}/{len(files)}...")

    print(f"Computing PCA (Target: {n_components} sliders)...")
    pca = PCA(n_components=n_components)
    latents = pca.fit_transform(matrix)
    
    # Normalize latents to [0, 1] for KAN compatibility
    latents_min = latents.min(axis=0)
    latents_max = latents.max(axis=0)
    
    # Avoid division by zero
    range_vals = latents_max - latents_min
    range_vals[range_vals == 0] = 1.0 
    
    latents_norm = (latents - latents_min) / range_vals

    # Explained variance tells us how much "Human Information" we captured
    variance = np.sum(pca.explained_variance_ratio_)
    print(f"PCA Complete! 16 sliders capture {variance*100:.2f}% of the total body variation.")

    # Save the latents (labels for our KAN training)
    output_data = {}
    for i, file in enumerate(files):
        name = os.path.basename(file).replace(".pcb", "")
        output_data[name] = latents_norm[i].tolist()

    with open("artifacts/datasets/vroid_latents.json", "w") as f:
        json.dump(output_data, f)
    
    print("Saved slider data to artifacts/datasets/vroid_latents.json")

if __name__ == "__main__":
    run_pca(sys.argv[1])
