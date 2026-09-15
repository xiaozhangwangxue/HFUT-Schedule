#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
derived_data="${project_dir}/build/DerivedData"
dist_dir="${project_dir}/dist"
app_path="${derived_data}/Build/Products/Release-iphoneos/HFUTSchedule.app"
ipa_path="${dist_dir}/HFUTSchedule-iOS-0.1.0-unsigned.ipa"

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

mkdir -p "${dist_dir}/Payload"
ditto "${app_path}" "${dist_dir}/Payload/HFUTSchedule.app"
cd "${dist_dir}"
/usr/bin/zip -qry "${ipa_path}" Payload
rm -rf "${dist_dir}/Payload"

echo "${ipa_path}"
