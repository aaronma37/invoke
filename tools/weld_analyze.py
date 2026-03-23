
import sys

def weld_and_analyze(path, epsilon=1e-5):
    vertices = []
    faces = []
    with open(path, 'r') as f:
        for line in f:
            if line.startswith('v '):
                vertices.append(tuple(map(float, line.split()[1:4])))
            elif line.startswith('f '):
                face = [int(p.split('/')[0]) - 1 for p in line.split()[1:]]
                faces.append(face)
    
    print(f"Original Vertices: {len(vertices)}")
    
    # Weld vertices by position
    unique_verts = {}
    weld_map = []
    new_vertices = []
    
    for i, v in enumerate(vertices):
        # Quantize to epsilon
        qv = tuple(round(x / epsilon) for x in v)
        if qv not in unique_verts:
            unique_verts[qv] = len(new_vertices)
            new_vertices.append(v)
        weld_map.append(unique_verts[qv])
    
    print(f"Welded Vertices: {len(new_vertices)}")
    
    # Remap faces
    welded_faces = []
    for face in faces:
        welded_face = [weld_map[vi] for vi in face]
        welded_faces.append(welded_face)

    # Connectivity on welded mesh
    adj = [set() for _ in range(len(new_vertices))]
    for face in welded_faces:
        for i in range(len(face)):
            v1 = face[i]
            v2 = face[(i+1)%len(face)]
            adj[v1].add(v2)
            adj[v2].add(v1)
            
    visited = [False] * len(new_vertices)
    components = 0
    for i in range(len(new_vertices)):
        if not visited[i]:
            components += 1
            stack = [i]
            visited[i] = True
            while stack:
                u = stack.pop()
                for v in adj[u]:
                    if not visited[v]:
                        visited[v] = True
                        stack.append(v)
    
    print(f"Welded Connected Components: {components}")

if __name__ == "__main__":
    weld_and_analyze(sys.argv[1])
