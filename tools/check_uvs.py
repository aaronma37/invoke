
import sys

def check_uv_overlap(path):
    uvs = []
    with open(path, 'r') as f:
        for line in f:
            if line.startswith('vt '):
                uvs.append(tuple(map(float, line.split()[1:3])))
    
    print(f"File: {path}")
    print(f"Total UVs: {len(uvs)}")
    
    unique_uvs = set(uvs)
    print(f"Unique UVs: {len(unique_uvs)}")
    
    if len(uvs) != len(unique_uvs):
        print(f"CRITICAL: Found {len(uvs) - len(unique_uvs)} overlapping UV coordinates!")
        # Find which ones
        from collections import Counter
        counts = Counter(uvs)
        overlap_samples = [uv for uv, count in counts.items() if count > 1]
        print(f"First 5 overlapping UVs: {overlap_samples[:5]}")
    else:
        print("Success: No UV overlaps found.")

if __name__ == "__main__":
    check_uv_overlap("artifacts/raw/vroid_base.obj")
