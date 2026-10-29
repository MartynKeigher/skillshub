#!/bin/sh
# Refreshes the catalog that ships inside SkillsHub (SkillsHub/Resources/index.json.gz) from the
# latest SkillsFlow release, and writes index.meta.json with its generation time, so the app can
# tell whether its cached download is newer without decoding the bundled copy.
#
# Run it before a release. It needs curl and python3.
set -eu

base="https://github.com/MartynKeigher/skillsflow/releases/latest/download"
dest="$(cd "$(dirname "$0")/.." && pwd)/SkillsHub/Resources"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if curl -fsSL -o "$work/index.json.gz" "$base/index.json.gz" 2>/dev/null; then
    gunzip -c "$work/index.json.gz" > "$work/index.json"
else
    # Releases before SkillsFlow 0.2 publish only index.json.
    curl -fsSL -o "$work/index.json" "$base/index.json"
    gzip -9 -n -c "$work/index.json" > "$work/index.json.gz"
fi

python3 -I - "$work/index.json" "$work/index.meta.json" <<'PY'
import json, sys
index = json.load(open(sys.argv[1], encoding="utf-8"))
assert index.get("schema_version") in (1, 2), f"unsupported schema {index.get('schema_version')}"
json.dump({"generatedAt": index["generated_at"]}, open(sys.argv[2], "w"))
print(f"catalog {index['generated_at']}: {len(index['skills'])} skills, {len(index['plugins'])} plugins")
PY

mkdir -p "$dest"
mv "$work/index.json.gz" "$dest/index.json.gz"
mv "$work/index.meta.json" "$dest/index.meta.json"
echo "wrote $dest/index.json.gz ($(du -h "$dest/index.json.gz" | cut -f1))"
