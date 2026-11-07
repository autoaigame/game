#!/usr/bin/env bash
# Downloads the Blender the character parts are built with, as a portable build (nothing installed), into
# .tools/blender/<version>/ (git-ignored). Safe to run again: it does nothing once that Blender is there.
#   tools/get-blender.sh          download, check the SHA-256, unpack; prints the path of the binary
#   tools/get-blender.sh --path   only print where the binary is (or would be)
# make blender runs it; make part uses that Blender when BLENDER is not given and blender is not on PATH.
#
# The version and the SHA-256 of each archive are pinned here, the one place to change them. They must also
# match the .sha256 file published next to the archives on download.blender.org.
set -euo pipefail

VERSION=5.2.3
SERIES=${VERSION%.*}
BASE="https://download.blender.org/release/Blender${SERIES}"
pinned_sha256() {  # bash 3 (macOS) has no associative arrays
	case "$1" in
		linux-x64.tar.xz) echo 78486c018b4443efe5e75ab54c290ed8c15abafd249b862c2c9ce2530a918eec ;;
		windows-x64.zip) echo 723f08a4401502561eb763cdeacf8745b31e5f3f154d287d3830d97cf75dc2fb ;;
		windows-arm64.zip) echo a539e484b1200e4a2e463560eb1672b60de846850af0e867b52a08607b910698 ;;
		macos-arm64.dmg) echo acc05374485a272342d4b323c15ac01953e7f697da2f1bad8af9c3bf087267a4 ;;
	esac
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/.tools/blender/$VERSION"

case "$(uname -s)-$(uname -m)" in
	Linux-x86_64) PLATFORM=linux-x64.tar.xz; BIN="$DEST/blender" ;;
	MINGW*-x86_64 | MSYS*-x86_64 | CYGWIN*-x86_64) PLATFORM=windows-x64.zip; BIN="$DEST/blender.exe" ;;
	MINGW*-aarch64 | MSYS*-aarch64 | MINGW*-arm64 | MSYS*-arm64) PLATFORM=windows-arm64.zip; BIN="$DEST/blender.exe" ;;
	Darwin-arm64) PLATFORM=macos-arm64.dmg; BIN="$DEST/Blender.app/Contents/MacOS/Blender" ;;
	*)
		echo "no portable Blender $VERSION for $(uname -s) $(uname -m) on download.blender.org" >&2
		echo "(Linux x64, Windows x64 and arm64, macOS arm64 only; Intel Macs: build Blender from source, or use a" >&2
		echo "machine that has one of these, and pass BLENDER=/path/to/blender)" >&2
		exit 1 ;;
esac

if [ "${1:-}" = "--path" ]; then
	echo "$BIN"
	exit 0
fi
if [ -x "$BIN" ]; then
	echo "$BIN"
	exit 0
fi

FILE="blender-$VERSION-$PLATFORM"
WANT=$(pinned_sha256 "$PLATFORM")
DL="$ROOT/.tools/downloads"
mkdir -p "$DL" "$ROOT/.tools"
touch "$ROOT/.tools/.gdignore"  # Godot must not import anything in there

sha() { if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

published=$(curl -fsSL "$BASE/blender-$VERSION.sha256" | awk -v f="$FILE" '$2 == f { print $1 }')
if [ "$published" != "$WANT" ]; then
	echo "the SHA-256 published for $FILE ($published) is not the one pinned in tools/get-blender.sh ($WANT)" >&2
	exit 1
fi
if [ ! -f "$DL/$FILE" ] || [ "$(sha "$DL/$FILE")" != "$WANT" ]; then
	echo "downloading $BASE/$FILE" >&2
	curl -fL --retry 3 --progress-bar -o "$DL/$FILE.part" "$BASE/$FILE"
	mv "$DL/$FILE.part" "$DL/$FILE"
fi
got=$(sha "$DL/$FILE")
if [ "$got" != "$WANT" ]; then
	echo "SHA-256 mismatch for $FILE: got $got, want $WANT" >&2
	rm -f "$DL/$FILE"
	exit 1
fi
echo "SHA-256 ok: $got" >&2

TMP="$DEST.tmp"
rm -rf "$TMP"
mkdir -p "$TMP"
case "$PLATFORM" in
	*.tar.xz)
		tar -xJf "$DL/$FILE" -C "$TMP" --strip-components=1 ;;
	*.zip)
		if command -v unzip > /dev/null; then
			unzip -q "$DL/$FILE" -d "$TMP"
		else
			powershell.exe -NoProfile -Command "Expand-Archive -LiteralPath '$(cygpath -w "$DL/$FILE")' -DestinationPath '$(cygpath -w "$TMP")'"
		fi
		inner=$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n 1)
		if [ -n "$inner" ] && [ ! -e "$TMP/blender.exe" ]; then
			mv "$inner"/* "$TMP"/ && rmdir "$inner"
		fi ;;
	*.dmg)
		# Mounted read-only and copied: nothing is installed in /Applications.
		MNT=$(mktemp -d)
		hdiutil attach -nobrowse -readonly -quiet -mountpoint "$MNT" "$DL/$FILE"
		cp -R "$MNT/Blender.app" "$TMP/"
		hdiutil detach -quiet "$MNT"
		rmdir "$MNT" ;;
esac
rm -rf "$DEST"
mv "$TMP" "$DEST"
"$BIN" --version | head -n 1 >&2
echo "$BIN"
