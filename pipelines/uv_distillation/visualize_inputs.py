import numpy as np
import trimesh
import sys

def visualize_inputs(pcb_path, output_obj):
    # PointSample struct: 9 floats
    # In our current Vector Displacement setup:
    # 0, 1, 2 = Base X, Y, Z (Inputs)
    # 3, 4, 5 = Delta X, Y, Z (Targets)
    data = np.fromfile(pcb_path, dtype=np.float32).reshape(-1, 9)
    
    inputs = data[:, 0:3]
    print(f"Visualizing {len(inputs)} input points.")
    print(f"Input Bounds: {inputs.min(axis=0)} to {inputs.max(axis=0)}")
    
    cloud = trimesh.points.PointCloud(inputs)
    cloud.export(output_obj)
    print(f"Saved input visualization to {output_obj}")

if __name__ == "__main__":
    visualize_inputs(sys.argv[1], sys.argv[2])
