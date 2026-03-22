import os
import subprocess
import pytest
import trimesh
import numpy as np

def run_command(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr)
        pytest.fail(f"Command failed: {' '.join(cmd)}")

@pytest.fixture
def sample_meshes(tmp_path):
    # Create a base sphere (r=1.0)
    base_mesh = trimesh.creation.icosphere(subdivisions=2, radius=1.0)
    base_path = tmp_path / "test_base.obj"
    base_mesh.export(str(base_path))
    
    # Create a target sphere (r=1.2) - target should be slightly larger to test displacement
    target_mesh = trimesh.creation.icosphere(subdivisions=2, radius=1.2)
    target_path = tmp_path / "test_target.obj"
    target_mesh.export(str(target_path))
    
    return base_path, target_path

def test_uv_distillation_pipeline(sample_meshes, tmp_path):
    base_path, target_path = sample_meshes
    name = "test_run"
    
    # Ensure artifacts directories are set up or redirected for the test
    # For testing, we'll just run it in the project root but with a specific name 
    # and then check the artifacts/ directory. 
    # Alternatively, we could mock the orchestrator to use tmp_path.
    
    # Let's just run it! 
    # We'll use a small number of epochs for speed.
    run_command([
        "python3", "pipelines/uv_distillation/orchestrate.py",
        "--target", str(target_path),
        "--base", str(base_path),
        "--name", name,
        "--epochs", "10"
    ])
    
    # Verify outputs exist
    dataset_path = f"artifacts/datasets/{name}.pcb"
    model_path = f"artifacts/models/{name}.kan"
    output_obj = f"artifacts/eval/{name}_displaced.obj"
    
    assert os.path.exists(dataset_path), "PCB dataset not found"
    assert os.path.exists(model_path), "KAN model not found"
    assert os.path.exists(output_obj), "Final displaced mesh not found"
    
    # Verify the output mesh is actually displaced (radius should be > 1.0)
    final_mesh = trimesh.load(output_obj)
    norms = np.linalg.norm(final_mesh.vertices, axis=1)
    avg_radius = np.mean(norms)
    
    print(f"Average radius of displaced mesh: {avg_radius}")
    assert avg_radius > 1.05, f"Mesh radius {avg_radius} is too small, displacement might have failed."
    assert avg_radius < 1.35, f"Mesh radius {avg_radius} is too large, displacement might be wrong."

if __name__ == "__main__":
    # If run directly, just execute the test logic manually
    pass
