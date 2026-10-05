#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Render normally checks out submodules, but older copies of this repository
# contain only .gitmodules (without gitlink entries). Support both layouts.
git submodule update --init --recursive

# GitHub commits created on Windows may not preserve executable bits.
chmod +x tools/*.sh tools/check_exploit_js.py

clone_if_missing() {
    local path="$1"
    local url="$2"
    local commit="$3"
    if [ ! -e "$path/.git" ]; then
        rm -rf "$path"
        # Use a complete clone: the patch steps inspect the checked-out source
        # tree, and partial clones can leave missing blobs in CI environments.
        git clone "$url" "$path"
    fi
    if ! git -C "$path" cat-file -e "$commit^{commit}" 2>/dev/null; then
        git -C "$path" fetch --depth=1 origin "$commit"
    fi
    git -C "$path" checkout --detach "$commit"
}

clone_if_missing third_party/ps5-unified-autoloader https://github.com/itsPLK/ps5-unified-autoloader.git 915a65e232e03e293829e34bca18866659b2bcf4
clone_if_missing third_party/umtx2 https://github.com/idlesauce/umtx2.git a080beb74d9e4bc34f3563798b716bd86b2d6ee0
clone_if_missing third_party/ps5-elfldr https://github.com/itsPLK/ps5-elfldr.git bb1e117988217a0239679029601e93c7286394d7
clone_if_missing third_party/relapse https://github.com/ntfargo/Relapse-Exploit.git d8e6896b5cb33b04f1e038a5d698d3d4aee5947c
clone_if_missing third_party/slopkit https://github.com/itsPLK/slopkit.git e69a21762f8d12479443502ce19ea4a575295c48

# Recreate the same patched exploit tree and verified binary dependencies used
# by the native build, without requiring the PS5 SDK or a native ELF build.
bash tools/apply_relapse_patch.sh
bash tools/apply_slopkit_patch.sh
bash tools/apply_umtx2_patch.sh
bash tools/download_deps.sh

BUILD_TYPE=stable python3 tools/gen_version.py
VERSION="$(BUILD_TYPE=stable python3 tools/gen_version.py --print)"
BUILD_TIME="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

rm -rf public
mkdir -p "public/app/$VERSION"
cp -R frontend/installer-page/. public/
cp -R frontend/pointer/. public/app/
cp -R frontend/autoloader/. "public/app/$VERSION/"

# Resolve the tokens normally filled by the native file-registry generator.
python3 - "$VERSION" "$BUILD_TIME" <<'PY'
import pathlib
import sys

version, build_time = sys.argv[1:]
root = pathlib.Path("public")
replacements = {
    "[[VERSION_PLACEHOLDER]]": version,
    "[[BUILD_TIME_PLACEHOLDER]]": build_time,
    "[[APP_DIR_PLACEHOLDER]]": version,
    "[[EXPLOIT_MODE]]": "auto",
}

for path in root.rglob("*"):
    if not path.is_file() or path.suffix not in {".html", ".js", ".appcache"}:
        continue
    data = path.read_text(encoding="utf-8")
    for old, new in replacements.items():
        data = data.replace(old, new)
    path.write_text(data, encoding="utf-8")

(root / "app" / version / "__complete__").write_text(version + "\n", encoding="utf-8")
PY

mkdir -p /tmp/ps5-wkal-overrides
