"""
Release Packaging Tool for TFAlert
Enforces strict Release Packaging Hygiene:
- Verifies test suite passes first
- Builds release ZIP with root 'TFAlert/' directory preserved
- Strips developer tools (tools/, *.py, tests/, dev docs, dotfiles)
"""

import os
import sys
import zipfile
import subprocess

def package():
    addon_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    repo_name = "TFAlert"
    zip_output = os.path.join(addon_dir, "..", f"{repo_name}.zip")

    print(f"1. Running test suite...")
    test_script = os.path.join(addon_dir, "tools", "run_tests.py")
    res = subprocess.run([sys.executable, test_script], cwd=addon_dir)
    if res.returncode != 0:
        print("Packaging aborted: tests failed!")
        sys.exit(1)

    print(f"\n2. Building clean release archive: {zip_output}")
    # Files permitted in end-user release package
    allowed_extensions = {".lua", ".xml", ".toc", ".md", ".txt", ".png", ".blp", ".tga"}
    excluded_names = {"HANDOFF.md", "AGENTS.md", "TODO.md"}
    excluded_dirs = {"tools", "tests", "__pycache__", ".git", ".github"}

    included_files = []
    with zipfile.ZipFile(zip_output, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(addon_dir):
            # Prune excluded directories
            dirs[:] = [d for d in dirs if d not in excluded_dirs]
            
            for file in files:
                ext = os.path.splitext(file)[1].lower()
                if ext in allowed_extensions and file not in excluded_names and not file.startswith("."):
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, addon_dir)
                    arcname = os.path.join(repo_name, rel_path)
                    zf.write(full_path, arcname)
                    included_files.append(arcname)

    print("\n3. Contamination Check (Release Packaging Hygiene):")
    with zipfile.ZipFile(zip_output, "r") as zf:
        namelist = zf.namelist()
        for name in namelist:
            assert not name.endswith(".py"), f"Contamination: Python file in release: {name}"
            assert "tools/" not in name and "tests/" not in name, f"Contamination: Dev tools in release: {name}"
            assert not os.path.basename(name).startswith("."), f"Contamination: Dotfile in release: {name}"
            print(f"  [OK] {name}")

    print(f"\n>>> Release package successfully created: {zip_output} ({len(included_files)} files) <<<")

if __name__ == "__main__":
    package()
