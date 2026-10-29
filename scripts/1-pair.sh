#!/bin/bash
# Stage 1: pair a Validity 138a:0090 sensor with this computer, using python-validity 0.14
# (+ the 0090 patches and PR #294) rebuilt for Fedora 44. Pairing writes TLS keys and Lenovo's
# firmware extension into the sensor's flash; stage 2 then uses the sensor through libfprint.
# This FACTORY-RESETS the sensor first: fingerprints stored on the chip (e.g. from Windows) are erased.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD
B=$REPO/build

[ "$(id -u)" != 0 ] || { echo "Run as your normal user; the script uses sudo where needed." >&2; exit 1; }
lsusb -d 138a:0090 >/dev/null || { echo "No 138a:0090 fingerprint sensor found (lsusb -d 138a:0090)." >&2; exit 1; }

echo "== build tools"
sudo dnf -y install rpm-build rpmdevtools dnf5-plugins innoextract policycoreutils-python-utils

build() {   # build <dir> <spec>: fetch sources, install build deps, build the RPMs as this user
    local d=$B/$1
    rm -rf "$d"; mkdir -p "$d"/{SOURCES,SPECS}
    cp "$REPO/$1"/* "$d/SOURCES/"; mv "$d/SOURCES/$2" "$d/SPECS/"
    spectool -g -C "$d/SOURCES" "$d/SPECS/$2"
    sudo dnf -y builddep "$d/SPECS/$2"
    echo "== building $1 (log: $d/build.log)"
    rpmbuild --define "_topdir $d" -bb "$d/SPECS/$2" > "$d/build.log" 2>&1 || { echo "build failed, see $d/build.log" >&2; exit 1; }
}
build fprintd-clients fprintd-clients.spec
build open-fprintd open-fprintd.spec
build python-validity python-validity.spec

echo "== installing (replaces Fedora's fprintd/fprintd-pam until stage 2)"
sudo dnf -y install \
    "$B"/fprintd-clients/RPMS/x86_64/fprintd-clients-1.94.2-*.x86_64.rpm \
    "$B"/fprintd-clients/RPMS/x86_64/fprintd-clients-pam-1.94.2-*.x86_64.rpm \
    "$B"/open-fprintd/RPMS/noarch/open-fprintd-*.noarch.rpm \
    "$B"/python-validity/RPMS/noarch/python3-validity-*.noarch.rpm

# SELinux: the driver lives under /usr/lib and would run in init_t, which may not write its state
# file under /usr/share ("Permission denied: .../backoff"). Label it as a program so it runs as an
# ordinary service. Stage 2 removes this rule again.
sudo semanage fcontext -a -t bin_t '/usr/lib/python-validity(/.*)?'
sudo restorecon -RF /usr/lib/python-validity

echo "== factory reset + pairing"
sudo systemctl enable --now open-fprintd.service
sudo systemctl stop python3-validity.service || true
sleep 1
(cd /usr/share/python-validity/playground && sudo python3 factory-reset.py)
sleep 3
sudo systemctl reset-failed python3-validity.service || true
sudo systemctl start python3-validity.service
echo "waiting 30 s for pairing, firmware upload and calibration…"
sleep 30
journalctl -u python3-validity -b --no-pager -o cat --since "-1 min" |
    grep -E "^INFO|Exception" | tail -15
echo
fprintd-list "$USER" | tail -2 || true
cat <<'EOF'

Paired if the log above shows "Flash has 5 partitions", "Loaded FWExt" (or "Detected firmware
version") and "Opening sensor", and fprintd-list says "Using device". A single
"Dont know how to handle message type 15" right after the firmware upload is normal; the service
restarts past it.
Do NOT enroll with python-validity (it fails with 0401 on this sensor). Run scripts/2-libfprint.sh.
EOF
