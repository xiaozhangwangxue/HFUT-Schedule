#!/bin/zsh
# 一键收尾：刷新小组件快照 → 申请描述文件 → 临时签名 → 安装 → 输出 IPA。
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
device_udid="${1:-00008101-001A6D6C2E22001E}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.2.0-Beta.app/Contents/Developer}"

cd "${project_dir}"

echo "==> 1/4 刷新小组件快照"
"${script_dir}/sync_widget_snapshot.sh" "${device_udid}" || echo "（跳过：设备上还没有快照文件，继续用现有数据）"

echo "==> 2/4 申请/更新描述文件"
xcodebuild -project HFUTSchedule.xcodeproj -scheme HFUTSchedule \
  -configuration Release -destination "platform=iOS,id=${device_udid}" \
  -allowProvisioningUpdates build > "${TMPDIR:-/tmp}/hfut_provisioning.log" 2>&1 \
  || grep -E "error:" "${TMPDIR:-/tmp}/hfut_provisioning.log" | sort -u

echo "==> 3/4 临时签名并打包"
"${script_dir}/build_temporary_signed_ipa.sh" "${device_udid}" yes

echo "==> 4/4 复制 IPA 到下载目录"
latest_ipa="$(ls -t "${project_dir}/dist/"*.ipa | head -1)"
cp "${latest_ipa}" "${HOME}/Downloads/"
echo "完成：${HOME}/Downloads/${latest_ipa:t}"
