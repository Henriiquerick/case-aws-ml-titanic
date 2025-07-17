import os
import shutil
import zipfile
import subprocess
import sys

# Define paths
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
LAMBDA_DIR = os.path.join(PROJECT_ROOT, 'lambda')
MODEL_PATH_SOURCE = os.path.join(PROJECT_ROOT, 'modelo', 'model.pkl')
LAMBDA_ZIP_PATH = os.path.join(LAMBDA_DIR, 'lambda_function.zip')
REQUIREMENTS_PATH = os.path.join(PROJECT_ROOT, 'requirements.txt')
TEMP_BUILD_DIR = os.path.join(PROJECT_ROOT, 'temp_lambda_build')

# Clean up previous build
if os.path.exists(TEMP_BUILD_DIR):
    shutil.rmtree(TEMP_BUILD_DIR)
if os.path.exists(LAMBDA_ZIP_PATH):
    os.remove(LAMBDA_ZIP_PATH)

os.makedirs(TEMP_BUILD_DIR, exist_ok=True)

# Install dependencies directly into TEMP_BUILD_DIR (flattens structure further)
print(f"Installing dependencies from {REQUIREMENTS_PATH} into {TEMP_BUILD_DIR}...")
try:
    temp_pip_venv_dir = os.path.join(PROJECT_ROOT, 'temp_pip_venv')
    if os.path.exists(temp_pip_venv_dir):
        shutil.rmtree(temp_pip_venv_dir)
    subprocess.check_call([sys.executable, '-m', 'venv', temp_pip_venv_dir])

    pip_executable_temp_venv = os.path.join(temp_pip_venv_dir, 'Scripts', 'pip.exe') if sys.platform == 'win32' else os.path.join(temp_pip_venv_dir, 'bin', 'pip')

    if not os.path.exists(pip_executable_temp_venv):
        raise RuntimeError(f"pip executable not found at {pip_executable_temp_venv}. Check Python venv setup.")

    subprocess.check_call([
        pip_executable_temp_venv, 'install', '-r', REQUIREMENTS_PATH, '-t', TEMP_BUILD_DIR # <--- MUDANÇA AQUI!
    ])
    print("Dependencies installed successfully.")
except subprocess.CalledProcessError as e:
    print(f"Error installing dependencies: {e}")
    sys.exit(1)
finally:
    if os.path.exists(temp_pip_venv_dir):
        shutil.rmtree(temp_pip_venv_dir)

# Copy lambda_function.py and model.pkl to the root of the TEMP_BUILD_DIR
shutil.copy(os.path.join(LAMBDA_DIR, 'lambda_function.py'), TEMP_BUILD_DIR)
shutil.copy(MODEL_PATH_SOURCE, TEMP_BUILD_DIR)


print(f"Creating zip archive at {LAMBDA_ZIP_PATH}...")
with zipfile.ZipFile(LAMBDA_ZIP_PATH, 'w', zipfile.ZIP_DEFLATED) as zf:
    # Add files from the root of TEMP_BUILD_DIR (which now includes libs, code, and model)
    for root, dirs, files in os.walk(TEMP_BUILD_DIR):
        for file in files:
            file_path = os.path.join(root, file)
            # Archive path is relative to TEMP_BUILD_DIR, stripping TEMP_BUILD_DIR from path
            archive_path = os.path.relpath(file_path, TEMP_BUILD_DIR)
            zf.write(file_path, archive_path)

print("Lambda package created successfully!")

# Clean up temporary build directory
shutil.rmtree(TEMP_BUILD_DIR)
print("Temporary build directory cleaned up.")