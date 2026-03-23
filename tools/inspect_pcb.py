
import numpy as np
import sys

def analyze_pcb(path):
    # PointSample: x,y,z, sdf, r,g,b, rough, metal (9 floats)
    # Displacement dx,dy,dz is stored in r,g,b (indices 4,5,6)
    data = np.fromfile(path, dtype=np.float32).reshape(-1, 9)
    displacements = data[:, 4:7]
    
    print(f"File: {path}")
    print(f"Num Points: {len(data)}")
    print(f"Avg Displacement: {np.mean(displacements, axis=0)}")
    print(f"Min Displacement: {np.min(displacements, axis=0)}")
    print(f"Max Displacement: {np.max(displacements, axis=0)}")
    print(f"Std Dev: {np.std(displacements, axis=0)}")
    print("-" * 30)

if __name__ == "__main__":
    analyze_pcb("artifacts/datasets/vroid_batch_pcb/vroid_0000.pcb")
    analyze_pcb("artifacts/datasets/vroid_batch_pcb/vroid_0001.pcb") # Tall
    analyze_pcb("artifacts/datasets/vroid_batch_pcb/vroid_0003.pcb") # Wide
