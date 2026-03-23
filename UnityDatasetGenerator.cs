using UnityEngine;
using UnityEditor;
using System.IO;
using System.Text;
using System.Collections.Generic;
using UniVRM10;

public class DatasetGenerator : EditorWindow
{
    [MenuItem("Moontide/Generate Dataset")]
    public static void Generate()
    {
        string masterPath = "Assets/MasterModel.vrm"; 
        string outputFolder = "Dataset_Output/";
        int count = 100; 
        Dictionary<string, float[]> metadata = new Dictionary<string, float[]>();

        if (!Directory.Exists(outputFolder)) Directory.CreateDirectory(outputFolder);

        GameObject master = AssetDatabase.LoadAssetAtPath<GameObject>(masterPath);
        if (master == null) {
            Debug.LogError($"Master Model not found at {masterPath}!");
            if (Application.isBatchMode) EditorApplication.Exit(1);
            return;
        }

        GameObject instance = Instantiate(master);
        Vrm10Instance vrmInstance = instance.GetComponent<Vrm10Instance>();
        Animator anim = instance.GetComponent<Animator>();
        SkinnedMeshRenderer[] allSmrs = instance.GetComponentsInChildren<SkinnedMeshRenderer>();

        // Neutral Anchor
        instance.transform.position = Vector3.zero;
        instance.transform.localScale = Vector3.one;
        Vector3 baseAnchorPos = GetHipVertexPosition(instance);

        Debug.Log($"--- Starting Large-Scale Bust Dataset Generation ({count} samples) ---");

        for (int i = 0; i < count; i++)
        {
            instance.transform.localScale = Vector3.one;
            instance.transform.position = Vector3.zero;
            instance.transform.rotation = Quaternion.identity;

            // Reset all bones
            foreach (HumanBodyBones bone in System.Enum.GetValues(typeof(HumanBodyBones))) {
                if (bone == HumanBodyBones.LastBone) continue;
                SetBoneScale(anim, bone, Vector3.one);
            }
            foreach (var smr in allSmrs) {
                for (int b = 0; b < smr.sharedMesh.blendShapeCount; b++) smr.SetBlendShapeWeight(b, 0);
            }

            // Randomize ONLY Bust Size (0.0 to 1.5 range)
            float bustVal = (i == 0) ? 0.0f : Random.Range(0.0f, 1.5f);
            
            // Apply BlendShapes
            foreach (var smr in allSmrs) {
                for (int b = 0; b < smr.sharedMesh.blendShapeCount; b++) {
                    string name = smr.sharedMesh.GetBlendShapeName(b).ToLower();
                    if (name.Contains("bust_size") || name.Contains("breast_size")) {
                        smr.SetBlendShapeWeight(b, Mathf.Clamp(bustVal * 100.0f, 0, 100.0f));
                    }
                }
            }
            
            // Apply Bone Scaling (Extra depth for values > 1.0)
            float boneScale = 1.0f + (bustVal * 0.6f);
            foreach (Transform t in instance.GetComponentsInChildren<Transform>()) {
                if (t.name.ToLower().Contains("bust") || t.name.ToLower().Contains("breast")) {
                    t.localScale = new Vector3(boneScale, boneScale, boneScale);
                }
            }

            if (vrmInstance != null) { vrmInstance.Runtime.Process(); }

            string id = "vroid_" + i.ToString("D4");
            string filename = outputFolder + id + ".obj";
            
            // Record metadata: [Waist, Shoulder, ChestDepth, ArmLength, BustSize]
            // We only vary BustSize (index 4)
            metadata[id] = new float[] { 0.0f, 0.0f, 0.0f, 0.0f, bustVal };

            Vector3 currentAnchorPos = GetHipVertexPosition(instance);
            Vector3 shift = currentAnchorPos - baseAnchorPos;
            ExportUnifiedOBJ(instance, filename, shift);
        }

        // Save Metadata
        string jsonPath = outputFolder + "vroid_metadata.json";
        StringBuilder jsonSb = new StringBuilder();
        jsonSb.AppendLine("{");
        int countIdx = 0;
        foreach (var entry in metadata) {
            jsonSb.Append($"  \"{entry.Key}\": [{entry.Value[0]:F4}, {entry.Value[1]:F4}, {entry.Value[2]:F4}, {entry.Value[3]:F4}, {entry.Value[4]:F4}]");
            if (++countIdx < metadata.Count) jsonSb.AppendLine(",");
            else jsonSb.AppendLine();
        }
        jsonSb.AppendLine("}");
        File.WriteAllText(jsonPath, jsonSb.ToString());

        DestroyImmediate(instance);
        if (Application.isBatchMode) EditorApplication.Exit(0);
    }

    static Vector3 GetHipVertexPosition(GameObject root) {
        SkinnedMeshRenderer body = null;
        foreach (var smr in root.GetComponentsInChildren<SkinnedMeshRenderer>()) {
            if (smr.name.ToLower().Contains("body")) { body = smr; break; }
        }
        if (body == null) return Vector3.zero;
        Mesh m = new Mesh();
        body.BakeMesh(m);
        Vector3 p = body.transform.TransformPoint(m.vertices[0]);
        DestroyImmediate(m);
        return p;
    }

    static void SetBoneScale(Animator anim, HumanBodyBones bone, Vector3 scale) {
        Transform t = anim.GetBoneTransform(bone);
        if (t != null) t.localScale = scale;
    }

    static void ExportUnifiedOBJ(GameObject root, string path, Vector3 shift)
    {
        StringBuilder sb = new StringBuilder();
        sb.AppendLine("# Moontide VAE-KAN Torso-Only Export");
        SkinnedMeshRenderer[] smrs = root.GetComponentsInChildren<SkinnedMeshRenderer>();
        List<Vector3> allPos = new List<Vector3>();
        List<Vector3> allNorm = new List<Vector3>();
        List<Vector2> allUV = new List<Vector2>();
        List<int> allTris = new List<int>();
        Dictionary<Vector3Int, int> weldMap = new Dictionary<Vector3Int, int>();
        float epsP = 0.001f;

        for (int meshIdx = 0; meshIdx < smrs.Length; meshIdx++)
        {
            var smr = smrs[meshIdx];
            bool isBody = smr.name.ToLower().Contains("body");
            if (!isBody) continue; // Skip face, hair, accessories

            Mesh mesh = new Mesh();
            smr.BakeMesh(mesh); 
            Vector3[] vertices = mesh.vertices;
            Vector3[] normals = mesh.normals;
            Vector2[] uvs = mesh.uv;
            int[] meshMap = new int[vertices.Length];

            for (int v = 0; v < vertices.Length; v++) {
                Vector3 worldV = smr.transform.TransformPoint(vertices[v]) - shift;
                
                // --- CLIPPING LOGIC ---
                // Remove Head (above neck)
                if (worldV.y > 1.42f) { meshMap[v] = -1; continue; }
                // Remove Feet (below ankles)
                if (worldV.y < 0.15f) { meshMap[v] = -1; continue; }
                // Remove Hands (beyond wrists)
                if (Mathf.Abs(worldV.x) > 0.65f && worldV.y > 0.8f) { meshMap[v] = -1; continue; }

                Vector3 worldN = smr.transform.TransformDirection(normals[v]);
                Vector3Int key = new Vector3Int(Mathf.RoundToInt(worldV.x / epsP), Mathf.RoundToInt(worldV.y / epsP), Mathf.RoundToInt(worldV.z / epsP));
                if (!weldMap.TryGetValue(key, out int idx)) {
                    idx = allPos.Count;
                    weldMap[key] = idx;
                    allPos.Add(worldV);
                    allNorm.Add(worldN);
                    allUV.Add(uvs[v]);
                }
                meshMap[v] = idx;
            }

            for (int sub = 0; sub < mesh.subMeshCount; sub++) {
                if (sub < smr.sharedMaterials.Length && !smr.sharedMaterials[sub].name.ToUpper().Contains("SKIN")) continue;
                int[] tris = mesh.GetTriangles(sub);
                for (int t = 0; t < tris.Length; t += 3) {
                    int i1 = meshMap[tris[t]];
                    int i2 = meshMap[tris[t+1]];
                    int i3 = meshMap[tris[t+2]];
                    // Only add triangle if all three vertices are valid (not clipped)
                    if (i1 != -1 && i2 != -1 && i3 != -1) {
                        allTris.Add(i1);
                        allTris.Add(i2);
                        allTris.Add(i3);
                    }
                }
            }
            DestroyImmediate(mesh);
        }

        for (int i = 0; i < allPos.Count; i++) {
            sb.AppendLine($"v {allPos[i].x:F6} {allPos[i].y:F6} {allPos[i].z:F6}");
            sb.AppendLine($"vn {allNorm[i].x:F6} {allNorm[i].y:F6} {allNorm[i].z:F6}");
            sb.AppendLine($"vt {allUV[i].x:F6} {allUV[i].y:F6}");
        }
        for (int i = 0; i < allTris.Count; i += 3) {
            sb.AppendLine($"f {allTris[i]+1}/{allTris[i]+1}/{allTris[i]+1} {allTris[i+1]+1}/{allTris[i+1]+1}/{allTris[i+1]+1} {allTris[i+2]+1}/{allTris[i+2]+1}/{allTris[i+2]+1}");
        }
        File.WriteAllText(path, sb.ToString());
    }
}
