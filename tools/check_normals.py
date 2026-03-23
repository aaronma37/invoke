
import sys
import numpy as np

def check_normals(path):
    normals = []
    with open(path, 'r') as f:
        for line in f:
            if line.startswith('vn '):
                normals.append(list(map(float, line.split()[1:4])))
    
    if not normals:
        print("No normals found.")
        return
        
    norms = np.array(normals)
    magnitudes = np.linalg.norm(norms, axis=1)
    
    print(f"File: {path}")
    print(f"Total Normals: {len(norms)}")
    print(f"Avg Magnitude: {np.mean(magnitudes)}")
    print(f"Min Magnitude: {np.min(magnitudes)}")
    print(f"Max Magnitude: {np.max(magnitudes)}")
    
    # Check for NaNs or Zeros
    zeros = np.sum(magnitudes < 1e-6)
    print(f"Zero Normals: {zeros}")
    
    # Avg Direction
    avg_dir = np.mean(norms, axis=0)
    print(f"Avg Direction: {avg_dir}")

if __name__ == "__main__":
    check_normals("artifacts/raw/vroid_base.obj")
