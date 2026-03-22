import struct
import sys

def pcb_to_obj(pcb_path, base_obj_path, output_obj):
    # Load base vertices
    base_verts = []
    with open(base_obj_path, 'r') as f:
        for line in f:
            if line.startswith('v '):
                base_verts.append([float(x) for x in line.split()[1:4]])
    
    # Load face data to match sampler iteration
    faces = []
    with open(base_obj_path, 'r') as f:
        for line in f:
            if line.startswith('f '):
                # Handle v/vt/vn
                parts = line.split()[1:]
                face = [int(p.split('/')[0]) - 1 for p in parts]
                faces.append(face)

    # Load PCB data
    with open(pcb_path, 'rb') as f:
        data = f.read()
    
    num_samples = len(data) // 36
    
    with open(output_obj, 'w') as out:
        idx = 0
        for f in faces:
            for v_idx in f:
                if idx >= num_samples: break
                
                # Sample: u, v, z, sdf, r, g, b, rough, metal
                sample = struct.unpack('fffffffff', data[idx*36:(idx+1)*36])
                sdf = sample[3]
                
                pos = base_verts[v_idx]
                # Use position as normal fallback for visualization
                mag = (pos[0]**2 + pos[1]**2 + pos[2]**2)**0.5
                if mag > 0:
                    norm = [pos[0]/mag, pos[1]/mag, pos[2]/mag]
                else:
                    norm = [0, 1, 0]
                
                # Displace
                px = pos[0] + norm[0] * sdf
                py = pos[1] + norm[1] * sdf
                pz = pos[2] + norm[2] * sdf
                
                out.write(f"v {px:.6f} {py:.6f} {pz:.6f}\n")
                idx += 1
            if idx >= num_samples: break

    print(f"Exported {idx} points to {output_obj}")

if __name__ == "__main__":
    pcb_to_obj(sys.argv[1], sys.argv[2], sys.argv[3])
