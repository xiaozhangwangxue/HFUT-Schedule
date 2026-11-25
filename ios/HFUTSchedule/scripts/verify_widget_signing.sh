#!/bin/zsh
# Read-only signing check for an explicitly supplied .app or .ipa.
# Prints only bundle/signature/group status, never profile devices, certificates or data.
set -euo pipefail

if [[ "$#" -ne 1 || "${1:-}" == "--help" ]]; then
  echo "用法：verify_widget_signing.sh <已签名的 .app 或 .ipa>"
  [[ "${1:-}" == "--help" ]] && exit 0
  exit 2
fi

python3 - "$1" <<'PY'
import fnmatch
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

GROUP_SUFFIX = "com.xiaozhangwangxue.hfutschedule.ios"

def run(*args):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)

def read_plist(path):
    with path.open('rb') as stream:
        return plistlib.load(stream)

def signed_entitlements(bundle):
    result = run('/usr/bin/codesign', '-d', '--entitlements', ':-', str(bundle))
    if result.returncode:
        return None
    try:
        return plistlib.loads(result.stdout)
    except Exception:
        return None

def profile_allows(bundle, entitlements, group):
    path = bundle / 'embedded.mobileprovision'
    if not path.is_file():
        return False
    result = run('/usr/bin/security', 'cms', '-D', '-i', str(path))
    if result.returncode:
        return False
    try:
        profile = plistlib.loads(result.stdout)
        allowed = profile.get('Entitlements', {})
        identifier = entitlements.get('application-identifier', '')
        bundle_identifier = read_plist(bundle / 'Info.plist').get('CFBundleIdentifier', '')
        profile_identifier = allowed.get('application-identifier', '')
        team = entitlements.get('com.apple.developer.team-identifier')
        return bool(
            identifier and profile_identifier and team
            and identifier == identifier.partition('.')[0] + '.' + bundle_identifier
            and fnmatch.fnmatchcase(identifier, profile_identifier)
            and team == allowed.get('com.apple.developer.team-identifier')
            and any(fnmatch.fnmatchcase(group, pattern)
                    for pattern in allowed.get('keychain-access-groups', []) if isinstance(pattern, str))
        )
    except Exception:
        return False

def inspect(app):
    plugins = app / 'PlugIns'
    widgets = []
    for candidate in sorted(plugins.glob('*.appex')):
        try:
            info = read_plist(candidate / 'Info.plist')
            if info.get('NSExtension', {}).get('NSExtensionPointIdentifier') == 'com.apple.widgetkit-extension':
                widgets.append(candidate)
        except Exception:
            continue
    print('主应用：存在')
    print('Widget 扩展：' + ('存在且唯一' if len(widgets) == 1 else '缺失或不唯一'))
    if len(widgets) != 1:
        return False

    widget = widgets[0]
    app_ent = signed_entitlements(app)
    widget_ent = signed_entitlements(widget)
    print('主应用签名 entitlement：' + ('可读取' if app_ent else '缺失'))
    print('Widget 签名 entitlement：' + ('可读取' if widget_ent else '缺失'))
    if not app_ent or not widget_ent:
        return False

    app_groups = set(app_ent.get('keychain-access-groups', []))
    widget_groups = set(widget_ent.get('keychain-access-groups', []))
    common = sorted(group for group in app_groups & widget_groups
                    if isinstance(group, str) and group.endswith('.' + GROUP_SUFFIX)
                    and '$(' not in group and '*' not in group)
    app_identifier = app_ent.get('application-identifier', '')
    widget_identifier = widget_ent.get('application-identifier', '')
    prefix = app_identifier.partition('.')[0]
    same_prefix = bool(prefix and prefix == widget_identifier.partition('.')[0])
    same_team = bool(app_ent.get('com.apple.developer.team-identifier') and
                     app_ent.get('com.apple.developer.team-identifier') == widget_ent.get('com.apple.developer.team-identifier'))
    app_first = next(iter(app_ent.get('keychain-access-groups', [])), None)
    widget_first = next(iter(widget_ent.get('keychain-access-groups', [])), None)
    groups_match = (same_prefix and same_team and len(common) == 1
                    and common[0] == prefix + '.' + GROUP_SUFFIX
                    and app_first == widget_first == common[0])
    print('App / Widget 共用 Keychain 组：' + ('一致' if groups_match else '不一致'))
    profiles_match = groups_match and all(profile_allows(bundle, ent, common[0])
                                        for bundle, ent in [(app, app_ent), (widget, widget_ent)])
    print('两个描述文件允许共组：' + ('是' if profiles_match else '否或未能验证'))
    valid = all(run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(bundle)).returncode == 0
                for bundle in [widget, app])
    print('App / Widget 签名完整性：' + ('通过' if valid else '未通过'))
    return bool(groups_match and profiles_match and valid)

def main():
    supplied = Path(sys.argv[1]).expanduser()
    if supplied.is_dir() and supplied.suffix == '.app':
        return inspect(supplied)
    if not supplied.is_file() or supplied.suffix.lower() != '.ipa':
        print('结果：请输入存在的 .app 或 .ipa。')
        return False
    with tempfile.TemporaryDirectory(prefix='hfut-signing-check-') as temporary:
        target = Path(temporary)
        with zipfile.ZipFile(supplied) as archive:
            # Only unpack the supplied package; never touch installed apps or their containers.
            for member in archive.infolist():
                destination = (target / member.filename).resolve()
                if not destination.is_relative_to(target.resolve()):
                    raise ValueError('Invalid archive path')
            archive.extractall(target)
        apps = list((target / 'Payload').glob('*.app'))
        if len(apps) != 1:
            print('主应用：缺失或不唯一')
            return False
        return inspect(apps[0])

try:
    passed = main()
except Exception:
    # Do not emit subprocess stderr, profile contents or certificate subjects.
    print('结果：无法完成签名结构检查。')
    sys.exit(1)
print('结果：' + ('共组签名检查通过' if passed else '共组签名检查未通过'))
sys.exit(0 if passed else 1)
PY
