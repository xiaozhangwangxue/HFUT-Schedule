#!/bin/zsh
# 从已安装的 iPhone 上取回课表，写入小组件包内快照（保底数据源）。
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
widget_snapshot="${project_dir}/HFUTScheduleWidget/ScheduleSnapshot.json"
device_udid="${1:-00008101-001A6D6C2E22001E}"
app_bundle_id="com.xiaozhangwangxue.hfutschedule.ios"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.2.0-Beta.app/Contents/Developer}"

work_dir="$(mktemp -d)"
snapshot_path="${work_dir}/snapshot.json"

copy_from_device() {
  xcrun devicectl device copy from \
    --device "${device_udid}" \
    --domain-type appDataContainer \
    --domain-identifier "${app_bundle_id}" \
    --source "$1" \
    --destination "${snapshot_path}"
}

if ! copy_from_device "Documents/hfut-widget-snapshot.json" >/dev/null 2>&1; then
  copy_from_device "Library/Application Support/HFUTSchedule/courses.json" >/dev/null
fi

/usr/bin/jq 'map({id, name, teacher, location, weekday, startTime, endTime, colorIndex, weekIndices, dates})' \
  "${snapshot_path}" > "${widget_snapshot}"

echo "已写入 $(/usr/bin/jq 'length' "${widget_snapshot}") 条课程 -> ${widget_snapshot}"
