#!/usr/bin/env bash
# Upload one depot from the machine that built it, or publish one build from
# depot manifests those uploads already produced. SetLive stays empty on a
# depot upload so a single platform cannot replace the branch.
set -euo pipefail

mode="${1:?upload or publish}"

if [ -z "${STEAM_USERNAME:-}" ] || [ -z "${STEAM_CONFIG_VDF:-}" ]; then
  echo "STEAM_USERNAME and STEAM_CONFIG_VDF are required" >&2
  exit 1
fi

install_steamcmd() {
  local dir="${RUNNER_TEMP:-/tmp}/steamcmd"
  mkdir -p "$dir"
  case "$(uname -s)" in
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        sudo dpkg --add-architecture i386
        sudo apt-get update -qq
        sudo apt-get install -y lib32gcc-s1 libc6-i386
      fi
      curl -fsSL -o "$dir/steamcmd.tar.gz" https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
      tar -xzf "$dir/steamcmd.tar.gz" -C "$dir"
      STEAMCMD=(bash "$dir/steamcmd.sh")
      ;;
    Darwin)
      curl -fsSL -o "$dir/steamcmd.tar.gz" https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz
      tar -xzf "$dir/steamcmd.tar.gz" -C "$dir"
      STEAMCMD=(bash "$dir/steamcmd.sh")
      ;;
    MINGW*|MSYS*|CYGWIN*)
      curl -fsSL -o "$dir/steamcmd.zip" https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip
      unzip -q -o "$dir/steamcmd.zip" -d "$dir"
      STEAMCMD=("$dir/steamcmd.exe")
      ;;
    *)
      echo "unsupported OS $(uname -s)" >&2
      exit 1
      ;;
  esac
  STEAMCMD_DIR="$dir"
}

write_config() {
  STEAMCMD_DIR="$STEAMCMD_DIR" python3 - <<'PY'
import base64, os
from pathlib import Path
data = base64.b64decode(os.environ["STEAM_CONFIG_VDF"])
home = Path.home()
dirs = [
    Path(os.environ["STEAMCMD_DIR"]) / "config",
    home / ".steam" / "root" / "config",
    home / ".steam" / "steam" / "config",
    home / ".local" / "share" / "Steam" / "config",
    home / "Steam" / "config",
    home / "Library" / "Application Support" / "Steam" / "config",
]
for d in dirs:
    d.mkdir(parents=True, exist_ok=True)
    path = d / "config.vdf"
    path.write_bytes(data)
    path.chmod(0o600)
PY
}

run_steamcmd() {
  local log="$1"
  shift
  # steamcmd updates itself on first launch and can exit before the command.
  "${STEAMCMD[@]}" +quit >"$log" 2>&1 || true
  set +e
  "${STEAMCMD[@]}" +login "$STEAM_USERNAME" "$@" +quit | tee -a "$log"
  local status=${PIPESTATUS[0]}
  set -e
  return "$status"
}

finished() {
  local app_id="$1"
  local log="$2"
  grep -q "Successfully finished AppID ${app_id} build (BuildID" "$log"
}

manifest_gid() {
  local depot="$1"
  local output="$2"
  local log="$3"
  python3 - "$depot" "$output" "$log" <<'PY'
import re, sys
from pathlib import Path
depot, output, log = sys.argv[1:]
root = Path(output)
file_gids = []
text = Path(log).read_text(errors="ignore")
if root.is_dir():
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        match = re.fullmatch(rf"{depot}_(\d+)", path.name.removesuffix(".manifest"))
        if path.suffix == ".manifest" and match:
            file_gids.append(match.group(1))
        if path.suffix in {".vdf", ".log"} or path.name == Path(log).name:
            text += "\n" + path.read_text(errors="ignore")
# "New manifestID 123" is the id steamcmd just created. "baselinemanifest"
# is the previous one and must not be selected.
created = re.findall(r"New manifestID\s+(\d{10,})", text, flags=re.I)
exact = re.findall(r'(?<![A-Za-z])"manifest"\s+"(\d{10,})"', text, flags=re.I)
if file_gids:
    print(file_gids[-1])
elif created:
    print(created[-1])
elif exact:
    print(exact[-1])
else:
    print("")
PY
}

case "$mode" in
  upload)
    app_id="${STEAM_APP_ID:?}"
    depot_id="${STEAM_DEPOT_ID:?}"
    content_root="${STEAM_CONTENT_ROOT:?}"
    local_path="${STEAM_LOCAL_PATH:?}"
    depot_path="${STEAM_DEPOT_PATH:?}"
    desc="${STEAM_BUILD_DESC:?}"
    case "$(uname -s)" in
      MINGW*|MSYS*|CYGWIN*) content_root="$(cygpath -m "$content_root")" ;;
    esac
    work="${RUNNER_TEMP:-/tmp}/steampipe"
    rm -rf "$work"
    mkdir -p "$work/output"
    python3 - "$work/app_build.vdf" "$app_id" "$depot_id" "$content_root" "$local_path" "$depot_path" "$work/output" "$desc" <<'PY'
import sys
vdf, app, depot, root, local_path, depot_path, output, desc = sys.argv[1:]
def q(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')
open(vdf, "w", encoding="utf-8").write(f'''"AppBuild"
{{
  "AppID" "{q(app)}"
  "Desc" "{q(desc)}"
  "ContentRoot" "{q(root)}"
  "BuildOutput" "{q(output)}"
  "SetLive" ""
  "Depots"
  {{
    "{q(depot)}"
    {{
      "FileMapping"
      {{
        "LocalPath" "{q(local_path)}"
        "DepotPath" "{q(depot_path)}"
        "recursive" "1"
      }}
      "FileExclusion" "*.pdb"
    }}
  }}
}}
''')
PY
    install_steamcmd
    write_config
    log="$work/steamcmd.log"
    run_steamcmd "$log" +run_app_build "$work/app_build.vdf" || true
    if ! finished "$app_id" "$log"; then
      echo "steamcmd did not finish depot ${depot_id}" >&2
      tail -n 120 "$log" >&2
      exit 1
    fi
    gid="$(manifest_gid "$depot_id" "$work/output" "$log")"
    if [ -z "$gid" ]; then
      echo "depot ${depot_id} uploaded but its manifest id was not in the steamcmd output" >&2
      find "$work/output" -type f -print >&2 || true
      for f in "$work/output"/*; do
        echo "===== $f =====" >&2
        tail -n 40 "$f" >&2 || true
      done
      exit 1
    fi
    out="${GITHUB_WORKSPACE:-.}/steam-manifest"
    mkdir -p "$out"
    printf '%s %s\n' "$depot_id" "$gid" > "$out/manifest.txt"
    echo "depot ${depot_id} manifest ${gid}"
    ;;
  publish)
    app_id="${STEAM_APP_ID:?}"
    branch="${STEAM_BRANCH:?}"
    desc="${STEAM_BUILD_DESC:?}"
    manifests="${STEAM_MANIFESTS_DIR:?}"
    work="${RUNNER_TEMP:-/tmp}/steampipe-publish"
    rm -rf "$work"
    mkdir -p "$work/output"
    python3 - "$work/app_build.vdf" "$app_id" "$desc" "$branch" "$work/output" "$manifests" <<'PY'
import sys
from pathlib import Path
vdf, app, desc, branch, output, manifests = sys.argv[1:]
rows = []
for path in sorted(Path(manifests).rglob("manifest.txt")):
    depot, gid = path.read_text(encoding="utf-8").split()
    if not depot.isdigit() or not gid.isdigit():
        raise SystemExit(f"bad manifest file {path}")
    rows.append((depot, gid))
if len(rows) != 3:
    raise SystemExit(f"expected 3 depot manifests, found {len(rows)}")
def q(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')
# A depot subsection is built from files. A string is a script path, and that
# script's "manifest" key is the already-uploaded manifest id.
vdf_dir = Path(vdf).parent
names = []
for depot, gid in rows:
    name = f"depot_{depot}.vdf"
    (vdf_dir / name).write_text(
        f'"depotbuild"\n{{\n  "DepotID" "{q(depot)}"\n  "manifest" "{q(gid)}"\n}}\n',
        encoding="utf-8",
    )
    names.append((depot, name))
depots = "\n".join(f'    "{q(depot)}" "{q(name)}"' for depot, name in names)
Path(vdf).write_text(f'''"AppBuild"
{{
  "AppID" "{q(app)}"
  "Desc" "{q(desc)}"
  "ContentRoot" ""
  "BuildOutput" "{q(output)}"
  "SetLive" "{q(branch)}"
  "Depots"
  {{
{depots}
  }}
}}
''', encoding="utf-8")
print(Path(vdf).read_text(encoding="utf-8"))
PY
    install_steamcmd
    write_config
    log="$work/steamcmd.log"
    run_steamcmd "$log" +run_app_build "$work/app_build.vdf" || true
    if ! finished "$app_id" "$log" || grep -q "empty depot" "$log"; then
      echo "steamcmd did not publish app ${app_id} on ${branch}" >&2
      tail -n 120 "$log" >&2
      exit 1
    fi
    echo "published app ${app_id} on ${branch}"
    ;;
  *)
    echo "unknown mode ${mode}" >&2
    exit 1
    ;;
esac
