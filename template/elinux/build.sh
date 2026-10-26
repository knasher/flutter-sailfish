#!/bin/sh
# From the Flutter app root:
#   ./elinux/build.sh          # flutter-elinux build + RPM inside sfosbuild
#   ./elinux/build.sh deploy
#   ./elinux/build.sh clean
#
# Needs:
#   FLUTTER_SFOS_RPMS  dir with flutter-sfos-<ver> and -devel RPMs
# Optional:
#   FLUTTER_SAILFISH_PATH  a flutter_sailfish package to build against instead
#                          of the one in pubspec.yaml (the Makefile sets it)
set -eu

cd "$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
ELINUX=$PWD/elinux
if [ -z "${FLUTTER_VERSION:-}" ]; then
	# shellcheck disable=SC1091
	. "$ELINUX/flutter-sfos.env"
fi
: "${FLUTTER_VERSION:?set FLUTTER_VERSION or elinux/flutter-sfos.env}"

RPMS=${FLUTTER_SFOS_RPMS:-$PWD/../../versions/$FLUTTER_VERSION/runtime/rpms}
SFOS=${SFOS:-5.1.0.11}
ARCH=${ARCH:-aarch64}
DEVICE=${DEVICE:-defaultuser@192.168.1.177}

# pubspec_overrides.yaml and .flutter_sailfish are written below for
# FLUTTER_SAILFISH_PATH. A pubspec_overrides.yaml of your own is left alone.
OVERRIDES=pubspec_overrides.yaml
OVERRIDES_MARK="# Written by elinux/build.sh for FLUTTER_SAILFISH_PATH."
if [ -f "$OVERRIDES" ] && [ "$(head -n 1 "$OVERRIDES")" = "$OVERRIDES_MARK" ]; then
	rm -f "$OVERRIDES"
fi
rm -rf .flutter_sailfish

if [ "${1:-}" = clean ]; then
	rm -rf build "$ELINUX"/rpms "$ELINUX"/out "$ELINUX"/bundle \
		"$ELINUX"/build-native rpms
	rm -f ./*.rpm "$ELINUX"/*.rpm
	for f in "$ELINUX"/*.in rpm/*.in; do
		[ -f "$f" ] && rm -f "${f%.in}"
	done
	exit 0
fi

test -d rpm
test -x "$ELINUX/build.sh"

for f in "$ELINUX"/*.in rpm/*.in; do
	[ -f "$f" ] || continue
	sed "s|@FLUTTER_VERSION@|$FLUTTER_VERSION|g" "$f" > "${f%.in}"
done
chmod +x "$ELINUX"/*.sh

rm -f ./flutter-sfos-"$FLUTTER_VERSION"-*.rpm
cp -f "$(ls -t "$RPMS"/flutter-sfos-"$FLUTTER_VERSION"-"$FLUTTER_VERSION"-*.aarch64.rpm | grep -v debug | head -1)" \
	"$(ls -t "$RPMS"/flutter-sfos-"$FLUTTER_VERSION"-devel-"$FLUTTER_VERSION"-*.aarch64.rpm | grep -v debug | head -1)" \
	./

# The build container only sees the app's folder, so the package is copied in.
if [ -n "${FLUTTER_SAILFISH_PATH:-}" ]; then
	if [ -f "$OVERRIDES" ]; then
		echo "elinux/build.sh: $OVERRIDES exists, so FLUTTER_SAILFISH_PATH is ignored" >&2
	else
		mkdir .flutter_sailfish
		(cd "$FLUTTER_SAILFISH_PATH" &&
			tar --exclude=.dart_tool --exclude=build --exclude=pubspec.lock -cf - .) |
			tar -C .flutter_sailfish -xf -
		printf '%s\ndependency_overrides:\n  flutter_sailfish:\n    path: .flutter_sailfish\n' \
			"$OVERRIDES_MARK" >"$OVERRIDES"
	fi
fi

# In-place rpmbuild packages this tree. Drop a previous arch's build first.
if [ -f Makefile ]; then
	make clean
	if make -n distclean >/dev/null 2>&1; then
		make distclean
	fi
fi
if [ -f build/elinux/Makefile ]; then
	make -C build/elinux clean
	if make -C build/elinux -n distclean >/dev/null 2>&1; then
		make -C build/elinux distclean
	fi
fi
rm -rf build

sfosbuild --in-place "$SFOS" "$ARCH" .

if [ "${1:-}" = deploy ]; then
	sfosbuild deploy "$DEVICE" .
fi
