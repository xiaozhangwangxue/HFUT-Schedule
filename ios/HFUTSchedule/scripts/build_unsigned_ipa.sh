#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
derived_data="${project_dir}/build/PublicRelease"
dist_dir="${project_dir}/dist"
app_path="${derived_data}/Build/Products/Release-iphoneos/HFUTSchedule.app"

# 公开制品必须使用空快照；私人注入构建不能复用此流程。
python3 - "${project_dir}/HFUTScheduleWidget/ScheduleSnapshot.json" <<'PY'
import json, sys
payload = json.load(open(sys.argv[1]))
courses = payload if isinstance(payload, list) else payload.get('courses', [])
if courses:
    raise SystemExit('Refusing public build: widget snapshot contains course data.')
PY

cd "${project_dir}"
xcodegen generate
xcodebuild \
  -project HFUTSchedule.xcodeproj \
  -scheme HFUTSchedule \
  -sdk iphoneos \
  -configuration Release \
  -derivedDataPath "${derived_data}" \
  CODE_SIGNING_ALLOWED=NO \
  build

python3 - "${app_path}" <<'PY'
from pathlib import Path
import json, sys
app = Path(sys.argv[1])
snapshots = list(app.rglob('ScheduleSnapshot.json'))
if not snapshots or not (app/'stu.json').exists():
    raise SystemExit('Public bundle is missing its widget snapshot or campus links.')
for path in snapshots:
    payload = json.loads(path.read_text())
    courses = payload if isinstance(payload, list) else payload.get('courses', [])
    if courses:
        raise SystemExit('Refusing public archive: bundled widget contains course data.')
PY

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app_path}/Info.plist")
ipa_path="${dist_dir}/HFUTSchedule-iOS-${version}-unsigned.ipa"
package_dir=$(mktemp -d "${TMPDIR:-/tmp/}hfut-public-ipa.XXXXXX")
trap 'rm -rf "${package_dir}"' EXIT
mkdir -p "${dist_dir}" "${package_dir}/Payload"
ditto "${app_path}" "${package_dir}/Payload/HFUTSchedule.app"
cd "${package_dir}"
/usr/bin/zip -qry "${package_dir}/HFUTSchedule.ipa" Payload
mv "${package_dir}/HFUTSchedule.ipa" "${ipa_path}"

echo "${ipa_path}"
