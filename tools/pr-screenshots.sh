#!/usr/bin/env bash
# Push images to a screenshots branch that is never merged, and print the Screenshots block of the PR
# body, with links fixed on the commit (raw.githubusercontent.com/<owner>/<repo>/<full SHA>/<path>).
#
#   tools/pr-screenshots.sh [--remote NAME] [--branch screenshots/NAME] [--repo OWNER/REPO] [--dry-run] IMAGE...
#
# --remote   where to push (default: origin, your fork)
# --branch   default: screenshots/<current branch>
# --repo     owner/repo of the links (default: read from the remote's GitHub URL)
# --dry-run  print the block to check it, push nothing (its links will never work: do not paste it)
#
# The images go at the root of the branch, directly under the commit in their links: the community site
# accepts no folder there, since "<SHA>/<folder>" could also be read as a branch name. Each run adds a
# commit on top of the branch, never rewrites it: links in older versions of the PR body keep working.
# The working tree, the index and the current branch are left alone.
set -euo pipefail

die() { echo "pr-screenshots: $*" >&2; exit 1; }

remote=origin branch="" repo="" dry=0
images=()
while (($#)); do
  case "$1" in
    --remote) remote="${2:?--remote needs a value}"; shift 2 ;;
    --branch) branch="${2:?--branch needs a value}"; shift 2 ;;
    --repo) repo="${2:?--repo needs a value}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    -h|--help) sed -n '2,/^[^#]/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    --) shift; images+=("$@"); break ;;
    -*) die "unknown option $1" ;;
    *) images+=("$1"); shift ;;
  esac
done
((${#images[@]})) || die "no image given (see --help)"
[[ "$remote" != -* ]] || die "invalid remote: $remote"
git rev-parse --git-dir >/dev/null 2>&1 || die "run it inside the game's git repository"

if [[ -z "$branch" ]]; then
  current="$(git symbolic-ref --short -q HEAD)" || die "detached HEAD: pass --branch screenshots/<name>"
  branch="screenshots/${current#screenshots/}"
fi
[[ "$branch" == screenshots/?* ]] || die "the branch must start with screenshots/"
git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "invalid branch name: $branch"

if [[ -z "$repo" ]]; then
  url="$(git remote get-url "$remote" 2>/dev/null)" || die "no remote $remote (or pass --repo)"
  repo="$(sed -E -n 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+)$#\2#p' <<<"$url")"
  repo="${repo%.git}"
  [[ -n "$repo" ]] || die "$remote is not a GitHub remote: pass --repo OWNER/REPO"
fi
# The community site accepts only these names (and GitHub has no others).
[[ "$repo" =~ ^[A-Za-z0-9](-?[A-Za-z0-9]){0,38}/[A-Za-z0-9._-]{1,100}$ && "${repo#*/}" != . && "${repo#*/}" != .. ]] ||
  die "unexpected owner/repo: $repo"

# A file name the site accepts: [a-z0-9._-], starting with a letter or a digit, lower-case extension.
safe_name() {
  local base="${1##*/}" ext stem
  ext="$(tr '[:upper:]' '[:lower:]' <<<"${base##*.}")"
  stem="$(tr '[:upper:]' '[:lower:]' <<<"${base%.*}" | tr -c 'a-z0-9._-' '-' | sed -E 's/^[^a-z0-9]+//; s/-+$//')"
  printf '%s.%s' "${stem:-image}" "$ext"
}

names=()
for f in "${images[@]}"; do
  [[ -f "$f" ]] || die "$f: no such file"
  case "$(tr '[:upper:]' '[:lower:]' <<<"${f##*.}")" in
    png) magic='89504e47' ;;
    jpg|jpeg) magic='ffd8ff' ;;
    *) die "$f: only .png, .jpg and .jpeg files" ;;
  esac
  [[ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" == "$magic"* ]] || die "$f: not a real PNG or JPEG file"
  size="$(wc -c <"$f")"
  ((size <= 10485760)) || die "$f: over 10 MB"
  ((size <= 1048576)) || echo "pr-screenshots: $f is over 1 MB; the site loads it as is (the first one on the market)" >&2
  name="$(safe_name "$f")"
  for n in "${names[@]}"; do [[ "$n" != "$name" ]] || die "two images named $name"; done
  names+=("$name")
done
((${#images[@]} <= 4)) || echo "pr-screenshots: the community site shows the first 4 images only" >&2

# Build the commit in a private index, on top of the remote branch if it exists.
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export GIT_INDEX_FILE="$tmpdir/index"
parent=""
if ((dry == 0)) && git ls-remote --exit-code --heads "$remote" "$branch" >/dev/null 2>&1; then
  git fetch -q "$remote" "refs/heads/$branch" || die "cannot fetch $branch from $remote"
  parent="$(git rev-parse FETCH_HEAD)"
  git read-tree "$parent"
else
  git read-tree --empty
fi
for i in "${!images[@]}"; do
  blob="$(git hash-object -w -- "${images[$i]}")"
  git update-index --add --cacheinfo "100644,$blob,${names[$i]}"
done
tree="$(git write-tree)"
msg="screenshots for ${branch#screenshots/}"
if [[ -n "$parent" ]]; then
  commit="$(git commit-tree "$tree" -p "$parent" -m "$msg")"
else
  commit="$(git commit-tree "$tree" -m "$msg")"
fi
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "the site needs a 40-character commit id, got $commit"
for name in "${names[@]}"; do
  url="https://raw.githubusercontent.com/$repo/$commit/$name"
  ((${#url} <= 300)) || die "$name: the link is over 300 characters, which the site ignores; use a shorter file name"
done

if ((dry == 0)); then
  # Never --force: older links must keep pointing at reachable commits.
  git push -q "$remote" "$commit:refs/heads/$branch" || die "push to $remote $branch refused"
  echo "pr-screenshots: pushed $branch to $remote ($commit)" >&2
else
  echo "pr-screenshots: dry run, nothing pushed. These links will never work: do not paste them." >&2
fi

echo "<details><summary>Screenshots</summary>"
echo
for name in "${names[@]}"; do
  echo "![${name%.*}](https://raw.githubusercontent.com/$repo/$commit/$name)"
done
echo
echo "</details>"
