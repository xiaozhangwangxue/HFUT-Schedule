#!/bin/zsh
# 生成临时签名的 IPA（主应用 + 周课表小组件），可选直接安装到已连接设备。
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
derived_dir="${project_dir}/build/SignedDeviceDerivedData"
dist_dir="${project_dir}/dist"
device_udid="${1:-00008101-001A6D6C2E22001E}"
install_after_build="${2:-yes}"

app_bundle_id="com.xiaozhangwangxue.hfutschedule.ios"
widget_bundle_id="${app_bundle_id}.widget"
team_id="K6T9P3LS8V"
keychain_group="${team_id}.${app_bundle_id}"
profile_dir="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.2.0-Beta.app/Contents/Developer}"

stamp="$(date +%Y%m%d-%H%M)"
ipa_path="${dist_dir}/HFUTSchedule-iOS-0.1.0-widget-temporary-signed-${stamp}.ipa"
app_path="${derived_dir}/Build/Products/Release-iphoneos/HFUTSchedule.app"
widget_path="${app_path}/PlugIns/HFUTScheduleWidget.appex"

echo "==> 生成工程"
cd "${project_dir}"
/opt/homebrew/bin/xcodegen generate >/dev/null

echo "==> 构建（未签名）"
xcodebuild -project HFUTSchedule.xcodeproj -scheme HFUTSchedule \
  -configuration Release -sdk iphoneos \
  -derivedDataPath "${derived_dir}" \
  CODE_SIGNING_ALLOWED=NO build > "${TMPDIR:-/tmp}/hfut_unsigned_build.log" 2>&1

if [[ ! -d "${widget_path}" ]]; then
  echo "错误：主应用里没有嵌入小组件扩展，构建有问题。" >&2
  exit 1
fi

find_profile() {
  local wanted="$1"
  local profile identifier
  for profile in "${profile_dir}"/*.mobileprovision(N); do
    identifier="$(security cms -D -i "${profile}" 2>/dev/null \
      | plutil -extract Entitlements.application-identifier raw - 2>/dev/null || true)"
    if [[ "${identifier}" == "${wanted}" ]]; then
      echo "${profile}"
      return 0
    fi
  done
  return 1
}

app_profile="$(find_profile "${team_id}.${app_bundle_id}")" || {
  echo "错误：找不到 ${app_bundle_id} 的描述文件，请先在 Xcode 登录 Apple ID。" >&2
  exit 1
}
widget_profile="$(find_profile "${team_id}.${widget_bundle_id}")" || {
  echo "错误：找不到 ${widget_bundle_id} 的描述文件。" >&2
  echo "请打开 Xcode → Settings → Accounts 登录 Apple ID 后重试，登录后会自动创建扩展的描述文件。" >&2
  exit 1
}

identity="$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')"
if [[ -z "${identity}" ]]; then
  echo "错误：钥匙串里没有 Apple Development 证书。" >&2
  exit 1
fi

entitlements_for() {
  local bundle_id="$1"
  local output="$2"
  cat > "${output}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key>
	<string>${team_id}.${bundle_id}</string>
	<key>com.apple.developer.team-identifier</key>
	<string>${team_id}</string>
	<key>get-task-allow</key>
	<true/>
	<key>keychain-access-groups</key>
	<array>
		<string>${keychain_group}</string>
	</array>
</dict>
</plist>
PLIST
}

work_dir="$(mktemp -d)"
entitlements_for "${widget_bundle_id}" "${work_dir}/widget.entitlements"
entitlements_for "${app_bundle_id}" "${work_dir}/app.entitlements"

echo "==> 签名小组件扩展"
cp "${widget_profile}" "${widget_path}/embedded.mobileprovision"
/usr/bin/codesign --force --sign "${identity}" --timestamp=none \
  --entitlements "${work_dir}/widget.entitlements" "${widget_path}"

echo "==> 签名主应用"
cp "${app_profile}" "${app_path}/embedded.mobileprovision"
/usr/bin/codesign --force --sign "${identity}" --timestamp=none \
  --entitlements "${work_dir}/app.entitlements" "${app_path}"

echo "==> 打包 IPA"
mkdir -p "${dist_dir}/Payload"
rm -rf "${dist_dir}/Payload/HFUTSchedule.app"
ditto "${app_path}" "${dist_dir}/Payload/HFUTSchedule.app"
(cd "${dist_dir}" && /usr/bin/zip -qry "${ipa_path}" Payload && rm -rf Payload)

echo "IPA: ${ipa_path}"

if [[ "${install_after_build}" == "yes" ]]; then
  echo "==> 安装到设备 ${device_udid}"
  xcrun devicectl device install app --device "${device_udid}" "${app_path}"
fi
