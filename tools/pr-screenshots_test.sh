#!/usr/bin/env bash
# Tests of tools/pr-screenshots.sh against a local bare repository. Run: tools/pr-screenshots_test.sh
set -uo pipefail
script="$(cd "$(dirname "$0")" && pwd)/pr-screenshots.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

# The URL the community site accepts (community-ui, internal/web/authorimages.go).
site_re='^!\[[^]]*\]\(https://raw\.githubusercontent\.com/[A-Za-z0-9](-?[A-Za-z0-9])*/[A-Za-z0-9._-]+/[0-9a-f]{40}/[A-Za-z0-9_-][A-Za-z0-9._-]*\.(png|jpg|jpeg)\)$'

git init -q --bare "$tmp/remote.git"
git init -q -b feat/Big-Trees "$tmp/work"
cd "$tmp/work" || exit 1
git config user.email t@example.com
git config user.name test
git remote add origin "$tmp/remote.git"
echo game >README && git add README && git commit -qm init
printf '\x89PNG\r\n\x1a\nrest' >"Title EN.PNG"
printf '\xff\xd8\xff\xe0rest' >shot.jpeg
printf '<svg onload=alert(1)>' >x.svg
printf 'not a png' >fake.png
echo pending >README

out="$("$script" --repo some-dev/game "Title EN.PNG" shot.jpeg 2>"$tmp/err")" || fail "first push: $(cat "$tmp/err")"
[[ "$(head -1 <<<"$out")" == "<details><summary>Screenshots</summary>" && "$(tail -1 <<<"$out")" == "</details>" ]] ||
  fail "the block is not folded in <details>: $out"
imgs="$(grep '^!\[' <<<"$out")"
[[ "$(wc -l <<<"$imgs")" == 2 ]] || fail "want 2 images: $out"
while read -r line; do
  [[ "$line" =~ $site_re ]] || fail "the site would refuse $line"
  url="${line#*(}"; ((${#url} <= 301)) || fail "the site refuses links over 300 characters: $line"
done <<<"$imgs"
grep -q '/[0-9a-f]\{40\}/title-en\.png)$' <<<"$imgs" || fail "name not made safe, or not at the root: $imgs"
sha1="$(sed -E -n '1s#.*/game/([0-9a-f]{40})/.*#\1#p' <<<"$imgs")"
[[ "$(git --git-dir="$tmp/remote.git" rev-parse screenshots/feat/Big-Trees)" == "$sha1" ]] || fail "the links do not name the pushed commit"
[[ "$(git --git-dir="$tmp/remote.git" show "$sha1:shot.jpeg" | od -An -tx1 | head -c 12)" == " ff d8 ff e0" ]] ||
  fail "the image is not in the commit"
[[ "$(git symbolic-ref --short HEAD)" == feat/Big-Trees && "$(cat README)" == pending ]] || fail "the working tree or branch changed"
[[ -z "$(git diff --cached --name-only)" ]] || fail "the index changed"

# A second run adds a commit on top: the first links stay valid.
printf '\x89PNG\r\n\x1a\nmore' >later.png
out="$("$script" --repo some-dev/game later.png 2>"$tmp/err")" || fail "second push: $(cat "$tmp/err")"
sha2="$(git --git-dir="$tmp/remote.git" rev-parse screenshots/feat/Big-Trees)"
[[ "$(git --git-dir="$tmp/remote.git" rev-parse "$sha2^")" == "$sha1" ]] || fail "the second commit is not on top of the first"
git --git-dir="$tmp/remote.git" cat-file -e "$sha2:title-en.png" || fail "earlier images dropped"

# Dry run pushes nothing, and says its links will not work.
"$script" --dry-run --repo some-dev/game --branch screenshots/try later.png >/dev/null 2>"$tmp/err" || fail "dry run failed"
grep -q "do not paste" "$tmp/err" || fail "dry run does not warn that its links will not work"
git --git-dir="$tmp/remote.git" rev-parse -q --verify screenshots/try >/dev/null && fail "dry run pushed"

# Refusals.
refuse() { local why="$1"; shift; "$script" "$@" >/dev/null 2>&1 && fail "accepted: $why"; }
refuse "svg" --repo some-dev/game x.svg
refuse "fake png" --repo some-dev/game fake.png
refuse "missing file" --repo some-dev/game nope.png
refuse "branch outside screenshots/" --repo some-dev/game --branch main later.png
refuse "branch screenshots/ alone" --repo some-dev/game --branch screenshots/ later.png
refuse "bad branch name" --repo some-dev/game --branch 'screenshots/a..b' later.png
refuse "owner with --" --repo some--dev/game later.png
refuse "repo .." --repo some-dev/.. later.png
refuse "local remote without --repo" later.png
refuse "two images with one name" --repo some-dev/game later.png ./later.png
refuse "no image" --repo some-dev/game
refuse "remote read as an option" --repo some-dev/game --remote "--upload-pack=touch $tmp/pwned" later.png
[[ ! -e "$tmp/pwned" ]] || fail "a --remote value ran a command"
long="$(printf 'a%.0s' {1..240}).png"
cp later.png "$long"
refuse "link over 300 characters" --repo some-dev/game "$long"
head -c 1100000 /dev/zero | cat later.png - >big.png
"$script" --dry-run --repo some-dev/game big.png >/dev/null 2>"$tmp/err" || fail "dry run of a big image failed"
grep -q "over 1 MB" "$tmp/err" || fail "no warning for an image over 1 MB"

# Owner and repo from a GitHub remote.
git remote add gh https://github.com/Some-Dev/my-game.git
out="$("$script" --dry-run --remote gh later.png 2>/dev/null)" || fail "dry run with a GitHub remote"
grep -q '^!\[later\](https://raw.githubusercontent.com/Some-Dev/my-game/[0-9a-f]\{40\}/later.png)$' <<<"$out" ||
  fail "owner/repo not read from the remote: $out"
git remote set-url gh git@github.com:Some-Dev/my-game.git
"$script" --dry-run --remote gh later.png 2>/dev/null | grep -q 'Some-Dev/my-game/' || fail "ssh remote not read"

if ((fails)); then echo "pr-screenshots: $fails failure(s)"; exit 1; fi
echo "pr-screenshots: ok"
