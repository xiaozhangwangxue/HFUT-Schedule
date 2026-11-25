#!/bin/zsh
# Add ad-hoc entitlement metadata for sideloading tools to rewrite. This is NOT
# a device-installable signature and never uses a real identity or profile.
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
dist_dir="${project_dir}/dist"
unsigned_ipa="${1:-${dist_dir}/HFUTSchedule-iOS-1.3.1-unsigned.ipa}"
output_ipa="${2:-${dist_dir}/HFUTSchedule-iOS-1.3.1-resignable.ipa}"
if (( $# > 2 )); then
    echo "用法：$0 [unsigned.ipa] [output.ipa]" >&2
    exit 1
fi
if [[ ! -f "${unsigned_ipa}" ]]; then
    echo "错误：找不到未签名 IPA：${unsigned_ipa}" >&2
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp/}hfut-resignable.XXXXXX")"
trap 'rm -rf "${work_dir}"' EXIT

python3 - "${unsigned_ipa}" "${work_dir}" "${output_ipa}" <<'PY'
from pathlib import Path, PurePosixPath
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

source, work, output = (Path(value).resolve() for value in sys.argv[1:])
if source == output:
    raise SystemExit('Input and output IPA must be different files.')

prefix = 'RESIGN0000'
shared_group = prefix + '.com.xiaozhangwangxue.hfutschedule.ios'

# Inspect every entry before extracting anything. In particular, profile
# contents are never read, and archive paths cannot escape this private temp.
with zipfile.ZipFile(source) as archive:
    seen = set()
    entries = archive.infolist()
    for entry in entries:
        name = entry.filename
        path = PurePosixPath(name)
        mode = entry.external_attr >> 16
        if (not name or '\\' in name or path.is_absolute() or '..' in path.parts
                or not path.parts or path.parts[0] != 'Payload'):
            raise SystemExit('Refusing unsafe or non-Payload archive path.')
        canonical_name = path.as_posix().casefold()
        if canonical_name in seen:
            raise SystemExit('Refusing archive with duplicate entries.')
        seen.add(canonical_name)
        if stat.S_ISLNK(mode) or (mode and stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR)):
            raise SystemExit('Refusing archive with symbolic links or special files.')
        if path.name.lower().endswith(('.mobileprovision', '.provisionprofile')):
            raise SystemExit('Refusing archive containing a provisioning profile.')
        if entry.flag_bits & 1:
            raise SystemExit('Encrypted IPA archives are not supported.')
    for entry in entries:
        target = work.joinpath(*PurePosixPath(entry.filename).parts)
        if entry.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(entry) as incoming, target.open('wb') as outgoing:
            shutil.copyfileobj(incoming, outgoing)
        os.chmod(target, ((entry.external_attr >> 16) & 0o777) or 0o644)

payload = work / 'Payload'
apps = list(payload.glob('*.app'))
if len(apps) != 1 or any(item != apps[0] for item in payload.iterdir()):
    raise SystemExit('Expected exactly one application in Payload.')
app = apps[0]
widgets = list(app.glob('PlugIns/*.appex'))
if len(widgets) != 1:
    raise SystemExit('Expected exactly one embedded weekly-schedule widget.')
widget = widgets[0]

def bundle_info(bundle):
    with (bundle / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    identifier = info.get('CFBundleIdentifier', '')
    if not isinstance(identifier, str) or not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', identifier):
        raise SystemExit('Invalid bundle identifier.')
    if info.get('CFBundleShortVersionString') != '1.3.1':
        raise SystemExit('Expected an iOS 1.3.1 application and widget.')
    executable = info.get('CFBundleExecutable')
    if not isinstance(executable, str) or Path(executable).name != executable or not (bundle / executable).is_file():
        raise SystemExit('Bundle is missing its executable.')
    return info

app_info, widget_info = bundle_info(app), bundle_info(widget)
if not widget_info['CFBundleIdentifier'].startswith(app_info['CFBundleIdentifier'] + '.'):
    raise SystemExit('Widget bundle identifier does not belong to the containing app.')

def assert_public_bundle():
    if any(path.name.lower().endswith(('.mobileprovision', '.provisionprofile')) for path in app.rglob('*')):
        raise SystemExit('Refusing bundle containing a provisioning profile.')
    snapshots = list(app.rglob('ScheduleSnapshot.json'))
    if not snapshots or not any(widget in path.parents for path in snapshots):
        raise SystemExit('The public widget snapshot is missing.')
    for path in snapshots:
        # The source-controlled public placeholder is []. Reject unknown
        # envelopes as well as non-empty courses instead of guessing whether
        # arbitrary bundled snapshot fields contain private information.
        if json.loads(path.read_text()) != []:
            raise SystemExit('Refusing personal or non-placeholder widget snapshot.')

assert_public_bundle()

def run(*arguments):
    return subprocess.run(arguments, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def ad_hoc_sign(bundle, info, name):
    identifier = info['CFBundleIdentifier']
    entitlement_path = work / (name + '.entitlements.plist')
    with entitlement_path.open('wb') as stream:
        plistlib.dump({
            'application-identifier': prefix + '.' + identifier,
            'com.apple.developer.team-identifier': prefix,
            'keychain-access-groups': [shared_group],
        }, stream, fmt=plistlib.FMT_XML)
    run('/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none',
        '--generate-entitlement-der', '--identifier', identifier,
        '--entitlements', str(entitlement_path), str(bundle))

# Sign optional nested libraries/frameworks first. They have no app-specific
# entitlement metadata; the two entry-point bundles below share the group.
nested_code = [path for path in app.rglob('*')
               if (path.is_dir() and path.suffix == '.framework')
               or (path.is_file() and path.suffix == '.dylib')]
for code in sorted(nested_code, key=lambda path: len(path.parts), reverse=True):
    run('/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none',
        '--generate-entitlement-der', str(code))

ad_hoc_sign(widget, widget_info, 'widget')
ad_hoc_sign(app, app_info, 'app')

def verify(bundle, info):
    displayed = run('/usr/bin/codesign', '--display', '--entitlements', ':-', str(bundle))
    entitlements = plistlib.loads(displayed.stdout)
    if entitlements.get('keychain-access-groups') != [shared_group]:
        raise SystemExit('Signing did not preserve the unique first shared keychain group.')
    if entitlements.get('application-identifier') != prefix + '.' + info['CFBundleIdentifier']:
        raise SystemExit('Signing produced an incorrect placeholder app identifier.')
    if entitlements.get('com.apple.developer.team-identifier') != prefix:
        raise SystemExit('Signing produced an incorrect placeholder team identifier.')
    details = run('/usr/bin/codesign', '--display', '--verbose=4', str(bundle)).stderr.decode()
    if 'Signature=adhoc' not in details or 'Authority=' in details:
        raise SystemExit('Expected an ad-hoc signature without a certificate authority.')
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(bundle))

verify(widget, widget_info)
verify(app, app_info)
assert_public_bundle()

output.parent.mkdir(parents=True, exist_ok=True)
handle, pending_name = tempfile.mkstemp(prefix='hfut-resignable-', suffix='.ipa.tmp', dir=output.parent)
os.close(handle)
pending = Path(pending_name)
try:
    with zipfile.ZipFile(pending, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(payload.rglob('*')):
            archive.write(path, path.relative_to(work).as_posix())
    with zipfile.ZipFile(pending) as archive:
        if archive.testzip() is not None:
            raise SystemExit('Packaged IPA failed its integrity check.')
        if any(PurePosixPath(name).name.lower().endswith(('.mobileprovision', '.provisionprofile'))
               for name in archive.namelist()):
            raise SystemExit('Packaged IPA unexpectedly contains a provisioning profile.')
    os.replace(pending, output)
finally:
    pending.unlink(missing_ok=True)

print('Verified ad-hoc entitlement metadata for app and widget; no certificate or profile included.')
print('This IPA still requires the user\'s signing tool before installation.')
print(output)
PY
