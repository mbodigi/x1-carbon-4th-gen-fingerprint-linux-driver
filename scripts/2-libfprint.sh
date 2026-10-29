#!/bin/bash
# Stage 2: replace the python-validity stack with Fedora's own fprintd + fprintd-pam and a libfprint
# that has the vfs0090 driver (needs a sensor paired by scripts/1-pair.sh). The driver RPM has Epoch 1,
# so Fedora's libfprint never updates over it, and it pulls in fprintd + fprintd-pam itself.
# PREBUILT=<dir> uses the release RPM in <dir> instead of building it.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD
B=$REPO/build/libfprint

[ "$(id -u)" != 0 ] || { echo "Run as your normal user; the script uses sudo where needed." >&2; exit 1; }
if [ -n "${PREBUILT:-}" ]; then
    rpm=$(ls "$(realpath "$PREBUILT")"/libfprint-1.94.100-*vfs0090*.x86_64.rpm)
else
    command -v spectool >/dev/null || sudo dnf -y install rpm-build rpmdevtools
    echo "== building libfprint 1.94.100 + vfs0090 (log: $B/build.log)"
    rm -rf "$B"; mkdir -p "$B"/{SOURCES,SPECS}
    cp "$REPO"/libfprint/0001-vfs0090-driver.patch "$B/SOURCES/"
    cp "$REPO"/libfprint/libfprint.spec "$B/SPECS/"
    spectool -g -C "$B/SOURCES" "$B/SPECS/libfprint.spec"
    sudo dnf -y builddep "$B/SPECS/libfprint.spec"
    rpmbuild --define "_topdir $B" -bb "$B/SPECS/libfprint.spec" > "$B/build.log" 2>&1 || { echo "build failed, see $B/build.log" >&2; exit 1; }
    rpm=$(ls "$B"/RPMS/x86_64/libfprint-1.94.100-*vfs0090*.x86_64.rpm | grep -v -e devel -e debug -e tests)
fi
echo "libfprint: $rpm"

echo "== swapping: python-validity stack out, stock fprintd + this libfprint in"
sudo systemctl disable --now python3-validity.service python3-validity-restart-after-resume.service \
    open-fprintd.service open-fprintd-restart-after-resume.service 2>/dev/null || true
# libfprint-devel (pulled in as a build dependency) requires Fedora's exact libfprint: remove it too
installed=$(rpm -q python3-validity open-fprintd fprintd-clients fprintd-clients-pam libfprint-devel | grep -v "not installed" || true)
[ -z "$installed" ] || sudo dnf -y remove $installed
# the driver brings fprintd + fprintd-pam along (Requires)
sudo dnf -y install "$rpm"
sudo semanage fcontext -d -t bin_t '/usr/lib/python-validity(/.*)?' 2>/dev/null || true

echo
rpm -q libfprint fprintd fprintd-pam
fprintd-list "$USER" | tail -2 || true
cat <<'EOF'

Next: enroll a finger with  fprintd-enroll  and test with  fprintd-verify  (see README: enrollment tips).
Fingerprint login for sudo/login/GNOME: sudo authselect enable-feature with-fingerprint
(off by default here on purpose; decide for yourself).
EOF
