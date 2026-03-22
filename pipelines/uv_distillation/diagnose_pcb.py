import numpy as np
import sys

def diagnose_pcb(path):
    print(f"Diagnosing PCB: {path}")
    # PointSample: 9 floats
    data = np.fromfile(path, dtype=np.float32).reshape(-1, 9)
    print(f"Total Samples: {len(data)}")
    
    print("\nFirst 5 Samples (Raw Floats):")
    for i in range(min(5, len(data))):
        print(f"Sample {i}: {data[i]}")
        
    print("\nInterpretation (Vector Displacement):")
    for i in range(min(5, len(data))):
        s = data[i]
        print(f"Sample {i}: Base({s[0]:.3f}, {s[1]:.3f}, {s[2]:.3f}) -> Delta({s[3]:.3f}, {s[4]:.3f}, {s[5]:.3f})")

    print("\nStats:")
    print(f"  Field 0 (U/X) Range: {data[:,0].min():.4f} to {data[:,0].max():.4f}")
    print(f"  Field 1 (V/Y) Range: {data[:,1].min():.4f} to {data[:,1].max():.4f}")
    print(f"  Field 2 (Z)   Range: {data[:,2].min():.4f} to {data[:,2].max():.4f}")
    print(f"  Field 3 (dX)  Range: {data[:,3].min():.4f} to {data[:,3].max():.4f}")
    print(f"  Field 4 (dY)  Range: {data[:,4].min():.4f} to {data[:,4].max():.4f}")
    print(f"  Field 5 (dZ)  Range: {data[:,5].min():.4f} to {data[:,5].max():.4f}")

if __name__ == "__main__":
    diagnose_pcb(sys.argv[1])
