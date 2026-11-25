#!/bin/zsh
# 使用自己的描述文件签名主应用与 Widget；保留两个目标共同的 Keychain 访问组。
# 可选环境：HFUT_APP_PROFILE、HFUT_WIDGET_PROFILE、HFUT_SIGNING_TEAM、HFUT_SIGNING_IDENTITY。
# install_after_build 默认 no；仅显式传入设备和 yes 时安装。
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.2.0-Beta.app/Contents/Developer}"
if [[ "$(xcrun --sdk iphoneos --show-sdk-version)" != "27.2" ]]; then
  echo "错误：此版本必须使用 iOS 27.2 SDK。" >&2
  exit 1
fi

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
derived_dir="${project_dir}/build/SignedDeviceDerivedData"
build_configuration="${HFUT_BUILD_CONFIGURATION:-Release}"
if [[ "${build_configuration}" != "Release" && "${build_configuration}" != "Debug" ]]; then
  echo "错误：HFUT_BUILD_CONFIGURATION 必须为 Release 或 Debug。" >&2
  exit 1
fi
dist_dir="${project_dir}/dist"
device_udid="${1:-}"
install_after_build="${2:-no}"
if [[ "${install_after_build}" == "yes" && -z "${device_udid}" ]]; then
  echo "错误：安装需要显式传入目标设备与 yes。" >&2
  exit 1
fi

app_bundle_id="com.xiaozhangwangxue.hfutschedule.ios"
widget_bundle_id="${app_bundle_id}.widget"
profile_dir="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

# App ID prefix is supplied by the profile and is not necessarily its TeamIdentifier.
# Decode in memory and output only the required entitlements to private temporary files.
python3 - "${profile_dir}" "${app_bundle_id}" "${widget_bundle_id}" "${work_dir}" <<'PY'
import datetime
import fnmatch
import hashlib
import os
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

profile_dir, app_id, widget_id, output = sys.argv[1:]
output = Path(output)
team_filter = os.environ.get('HFUT_SIGNING_TEAM', '')
identity_filter = os.environ.get('HFUT_SIGNING_IDENTITY', '').upper()
shared_suffix = 'com.xiaozhangwangxue.hfutschedule.ios'
now = datetime.datetime.now(datetime.timezone.utc)


def fail(message):
    print('错误：' + message, file=sys.stderr)
    sys.exit(1)


def command(*args):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


identities = command('/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning')
available = set(re.findall(rb'\b([0-9A-Fa-f]{40})\b', identities.stdout))
available = {value.decode().upper() for value in available}
if identity_filter:
    if not re.fullmatch(r'[0-9A-F]{40}', identity_filter):
        fail('HFUT_SIGNING_IDENTITY 必须是本机签名证书的 SHA-1 标识。')
    available &= {identity_filter}
if not available:
    fail('没有可用的本机代码签名身份。')


def candidates(bundle_id, explicit_path):
    paths = [Path(explicit_path).expanduser()] if explicit_path else sorted(Path(profile_dir).glob('*.mobileprovision'))
    results = []
    for path in paths:
        decoded = command('/usr/bin/security', 'cms', '-D', '-i', str(path))
        if decoded.returncode:
            continue
        try:
            profile = plistlib.loads(decoded.stdout)
            ent = profile['Entitlements']
            identifier = ent['application-identifier']
            prefix = identifier.partition('.')[0]
            team = ent['com.apple.developer.team-identifier']
            if not isinstance(prefix, str) or not re.fullmatch(r'[A-Za-z0-9]+', prefix):
                continue
            if not isinstance(team, str) or not re.fullmatch(r'[A-Za-z0-9]+', team):
                continue
            if team_filter and team != team_filter:
                continue
            if not fnmatch.fnmatchcase(prefix + '.' + bundle_id, identifier):
                continue
            if prefix not in profile.get('ApplicationIdentifierPrefix', [prefix]):
                continue
            shared_group = prefix + '.' + shared_suffix
            if not any(fnmatch.fnmatchcase(shared_group, group) for group in ent.get('keychain-access-groups', [])):
                continue
            expiry = profile['ExpirationDate']
            if expiry.tzinfo is None:
                expiry = expiry.replace(tzinfo=datetime.timezone.utc)
            if expiry <= now:
                continue
            certificates = {hashlib.sha1(value).hexdigest().upper() for value in profile.get('DeveloperCertificates', [])}
            valid_identities = sorted(certificates & available)
            if not valid_identities:
                continue
            results.append(dict(path=path, prefix=prefix, team=team, group=shared_group,
                                entitlements=ent, expiry=expiry, identity=valid_identities[0]))
        except Exception:
            continue
    return results


app_candidates = candidates(app_id, os.environ.get('HFUT_APP_PROFILE', ''))
widget_candidates = candidates(widget_id, os.environ.get('HFUT_WIDGET_PROFILE', ''))
pairs = [(app, widget) for app in app_candidates for widget in widget_candidates
         if app['prefix'] == widget['prefix'] and app['team'] == widget['team']]
if not pairs:
    fail('找不到同时允许 App / Widget 共用 Keychain 组的有效描述文件和本机签名身份；请为两个目标用同一团队生成描述文件。')
if len({(app['prefix'], app['team']) for app, _ in pairs}) > 1:
    fail('存在多组可用签名配置，请显式设置 HFUT_APP_PROFILE 和 HFUT_WIDGET_PROFILE，或 HFUT_SIGNING_TEAM。')
app, widget = max(pairs, key=lambda pair: min(pair[0]['expiry'], pair[1]['expiry']))
for kind, bundle_id, selected in [('app', app_id, app), ('widget', widget_id, widget)]:
    entitlements = {
        'application-identifier': selected['prefix'] + '.' + bundle_id,
        'com.apple.developer.team-identifier': selected['team'],
        'get-task-allow': bool(selected['entitlements'].get('get-task-allow', False)),
        'keychain-access-groups': [selected['group']]
    }
    with (output / (kind + '.entitlements')).open('wb') as stream:
        plistlib.dump(entitlements, stream)
    shutil.copyfile(selected['path'], output / (kind + '.mobileprovision'))
    (output / (kind + '.identity')).write_text(selected['identity'])
(output / 'team').write_text(app['team'])
PY

signing_team="$(<"${work_dir}/team")"
app_identity="$(<"${work_dir}/app.identity")"
widget_identity="$(<"${work_dir}/widget.identity")"
stamp="$(date +%Y%m%d-%H%M%S)"
ipa_path=""
app_path="${derived_dir}/Build/Products/${build_configuration}-iphoneos/HFUTSchedule.app"
widget_path="${app_path}/PlugIns/HFUTScheduleWidget.appex"

echo "==> 生成工程"
cd "${project_dir}"
xcodegen generate >/dev/null

echo "==> 构建（未签名）"
xcodebuild -project HFUTSchedule.xcodeproj -scheme HFUTSchedule \
  -configuration "${build_configuration}" -sdk iphoneos27.2 \
  -derivedDataPath "${derived_dir}" \
  DEVELOPMENT_TEAM="${signing_team}" CODE_SIGNING_ALLOWED=NO build \
  > "${TMPDIR:-/tmp}/hfut_unsigned_build.log" 2>&1

if [[ ! -d "${widget_path}" ]]; then
  echo "错误：主应用里没有嵌入小组件扩展。" >&2
  exit 1
fi

echo "==> 签名 Widget 扩展与主应用"
# SPM binary frameworks may retain the vendor/ad-hoc signature after an
# unsigned build. iOS verifies every nested executable during installation.
# Sign dependencies inside-out with this build's identity before their owner.
python3 - "${app_path}" "${app_identity}" <<'PY'
from pathlib import Path
import subprocess
import sys
app = Path(sys.argv[1])
code = [p for p in app.rglob('*')
        if (p.is_dir() and p.suffix == '.framework')
        or (p.is_file() and p.suffix == '.dylib')]
for path in sorted(code, key=lambda p: len(p.parts), reverse=True):
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', sys.argv[2],
                    '--timestamp=none', str(path)], check=True)
PY
cp "${work_dir}/widget.mobileprovision" "${widget_path}/embedded.mobileprovision"
/usr/bin/codesign --force --sign "${widget_identity}" --timestamp=none \
  --entitlements "${work_dir}/widget.entitlements" "${widget_path}"
cp "${work_dir}/app.mobileprovision" "${app_path}/embedded.mobileprovision"
/usr/bin/codesign --force --sign "${app_identity}" --timestamp=none \
  --entitlements "${work_dir}/app.entitlements" "${app_path}"

# Reject re-signing that leaves the extension outside the main app's actual shared group.
"${script_dir}/verify_widget_signing.sh" "${app_path}"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app_path}/Info.plist")
ipa_path="${dist_dir}/HFUTSchedule-iOS-${version}-temporary-signed-${stamp}.ipa"

echo "==> 打包 IPA"
mkdir -p "${dist_dir}" "${work_dir}/Payload"
ditto "${app_path}" "${work_dir}/Payload/HFUTSchedule.app"
(cd "${work_dir}" && /usr/bin/zip -qry "${ipa_path}" Payload)
echo "IPA: ${ipa_path}"

if [[ "${install_after_build}" == "yes" ]]; then
  echo "==> 安装到指定设备"
  xcrun devicectl device install app --device "${device_udid}" "${app_path}"
fi
