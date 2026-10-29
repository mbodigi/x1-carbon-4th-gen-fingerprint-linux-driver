# ThinkPad X1 Carbon 4th gen fingerprint reader on Linux (Validity VFS7500 `138a:0090`, Fedora 44)

Build recipes, patches and two scripts that got the fingerprint reader of a **ThinkPad X1 Carbon
4th gen** working on **Fedora 44**: enroll, `fprintd-verify`, and PAM (lock screen, polkit dialogs).

```
$ lsusb -d 138a:0090
Bus 001 Device 004: ID 138a:0090 Validity Sensors, Inc. VFS7500 Touch Fingerprint Sensor
```

Out of the box, Fedora's `fprintd` says `No devices available` for this sensor. Nothing here is new
driver work: it packages other people's fixes (see [Credits](#credits)) for current Fedora.

## Tested on

Exactly one machine, so treat anything else as untested:

| | |
|---|---|
| Laptop | ThinkPad X1 Carbon 4th gen (20FC) |
| Sensor | `138a:0090`, flash W25Q80B, ROM 6.7 build 164 |
| OS | Fedora 44, kernel 7.2, Python 3.14, Secure Boot on |
| Result | pairing, enrollment, `fprintd-verify`, PAM via `pam_fprintd` |

The same sensor ships in other ThinkPads of that generation. People in the upstream issues report
the same errors and fixes on a **T460s, T460p and P50** ([#287](https://github.com/uunicorn/python-validity/issues/287),
[#291](https://github.com/uunicorn/python-validity/issues/291), [PR #294](https://github.com/uunicorn/python-validity/pull/294)),
but this repo hasn't been tried there.

The two scripts are a cleaned-up version of the exact steps that worked on the laptop above; they
haven't been re-run start to finish in this form. Read them before running them.

## How it works

1. **Pair** (`scripts/1-pair.sh`): [python-validity](https://github.com/uunicorn/python-validity) 0.14
   with the 0090 patches from the [tigro/python-validity COPR](https://copr.fedorainfracloud.org/coprs/tigro/python-validity/)
   plus [PR #294](https://github.com/uunicorn/python-validity/pull/294), rebuilt for Python 3.14.
   It factory-resets the sensor, writes a fresh partition table and TLS keys, and uploads Lenovo's
   firmware extension (`validity-sensors-firmware` downloads it).
   Without PR #294 this ROM fails with `Exception: Failed: 04af` in `erase_flash(1)`.
2. **Use** (`scripts/2-libfprint.sh`): python-validity can pair this sensor but can't enroll it
   (`create_enrollment` → `0401`). So it's removed again, and Fedora's own `fprintd` + `fprintd-pam`
   run on a libfprint 1.94.100 that has the vfs0090 driver from
   [Zaytzew/libfprint-vfs0090-1.94](https://github.com/Zaytzew/libfprint-vfs0090-1.94).
   It's a single RPM: installing it pulls in `fprintd` and `fprintd-pam` from Fedora, and its
   Epoch 1 keeps Fedora's own libfprint from updating over it.

## Install

```sh
git clone https://github.com/mbodigi/x1-carbon-4th-gen-fingerprint-linux-driver
cd x1-carbon-4th-gen-fingerprint-linux-driver
scripts/1-pair.sh        # asks for sudo; FACTORY-RESETS the sensor (wipes prints stored on it)
scripts/2-libfprint.sh
fprintd-enroll           # see the tips below
fprintd-verify
```

### Or with the prebuilt RPMs (Fedora 44, x86_64)

The [release](https://github.com/mbodigi/x1-carbon-4th-gen-fingerprint-linux-driver/releases) has the
RPMs built from these specs on the tested laptop (unsigned; check them against `SHA256SUMS`).
No build tools or build time needed:

```sh
mkdir rpms && cd rpms        # download the release files here, then:
sha256sum -c SHA256SUMS
cd ..
PREBUILT=rpms scripts/1-pair.sh
PREBUILT=rpms scripts/2-libfprint.sh
```

Stage 2 is one file: `libfprint-1.94.100-1.vfs0090` installs the driver and pulls in `fprintd`
and `fprintd-pam` by itself. The four others are only for the one-time pairing in stage 1.
They only fit Fedora 44 (Python 3.14, libfprint 1.94.100); on anything else, build from source.

Fingerprint for sudo, login and GNOME: `sudo authselect enable-feature with-fingerprint`. The
scripts leave that choice to you.

### Enrollment tips

The sensor is small (144×144 px) and a match needs 12 matching points. On the tested laptop a quick
first enrollment matched about 1 touch in 5; after a careful one, every test touch matched. For the 5 touches: press firmly, hold
about a second, lift completely, and move a little each time: centered, more fingertip, lower, rolled
left, rolled right. If `fprintd-verify` keeps failing, `fprintd-delete $USER` and enroll again.

## Known limits

- **It answers when you lift your finger.** The sensor's firmware only finishes a scan when the
  finger leaves (measured: the match arrives at the lift, not while the finger rests on it). Touch,
  then lift.
- **Match on host.** Templates are stored on the computer (`/var/lib/fprint`, root only), not in the
  sensor.
- **The driver outranks Fedora's libfprint** (Epoch 1), so updates leave it alone. If a future
  fprintd ever needs a newer libfprint, dnf will report a conflict instead of silently breaking the
  reader: rebuild from the spec then. After a Fedora release upgrade, rebuild.
- After a cancelled scan the driver logs `Deactivation failed at state 1 … transfer timed out` and
  takes about 3 s to release the sensor. Harmless so far.
- The driver and both patches are community work, outside Fedora and upstream libfprint, in your
  authentication path. Decide for yourself where you use it.

## Troubleshooting (from the pairing run)

| Message | What it was |
|---|---|
| `PermissionError: … /usr/share/python-validity/backoff` | SELinux runs the driver as `init_t`; `1-pair.sh` labels it `bin_t` |
| `Exception: Failed: 04af` in `erase_flash(1)` / `read_tls_flash()` | ROM 6.7 b164 without PR #294; factory-reset and pair with the patched build |
| `Dont know how to handle message type 15` once after the firmware upload | normal, the service restarts past it |
| `dnf`: `libfprint-devel … requires libfprint = 1.94.100-1.fc44` | remove `libfprint-devel` (`2-libfprint.sh` does) |
| `fprintd-verify`: always `verify-no-match` | weak enrollment, see the tips |

## Undo

```sh
sudo dnf -y distro-sync libfprint     # back to Fedora's build (the reader stops working)
```

The pairing stays in the sensor's flash and does no harm. The build dependencies the scripts
installed can be removed with `dnf history` (`dnf history undo <id>` of the `builddep` transactions).

## Credits

- [uunicorn/python-validity](https://github.com/uunicorn/python-validity) and
  [open-fprintd](https://github.com/uunicorn/open-fprintd): the reverse-engineered driver used for pairing (MIT / GPL-2.0)
- [tigro's COPR](https://copr.fedorainfracloud.org/coprs/tigro/python-validity/): the Fedora specs and 0090 patches these are based on
- [PR #294](https://github.com/uunicorn/python-validity/pull/294) by gocarlos: pairing fix for ROM 6.7 build 164
- [Zaytzew/libfprint-vfs0090-1.94](https://github.com/Zaytzew/libfprint-vfs0090-1.94): the vfs0090 driver ported to libfprint 1.94
  (from rabbitambulance-ra's fork of the libfprint-tod-vfs0090 driver by Marco Trevisan, Nikita Mikhailov and contributors; LGPL-2.1+)
- [libfprint](https://gitlab.freedesktop.org/libfprint/libfprint) and [fprintd](https://gitlab.freedesktop.org/libfprint/fprintd)

## License

The scripts and this README: MIT (see `LICENSE`). Specs and patches keep their upstream licenses:
python-validity MIT, open-fprintd and fprintd GPL-2.0(+), libfprint and the vfs0090 driver patch LGPL-2.1+.
