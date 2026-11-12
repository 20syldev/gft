#!/usr/bin/env bash
# Build the gft .deb with nfpm, reproducibly, and lint it.
#
#   packaging/build-deb.sh [--kind deb|apt] [--out DIR] [--allow-dirty]
#
# The version is the VERSION file, which must equal the VERSION= line of the gft script.
#   --kind deb   the file attached to the GitHub release (default): the marker says package=deb.
#   --kind apt   the file served by the maintainer's signed apt repository: package=apt.
#                The two kinds differ only by the marker /usr/share/gft/install-method.
#   --out DIR    where gft_<version>_all.deb is written (default: dist). An existing file is
#                never overwritten.
#   --allow-dirty  build from a tree with uncommitted changes or, for apt, an untagged commit
#                (tests only: such a package is not reproducible).
# Needs nfpm (https://nfpm.goreleaser.com); lintian runs when installed (required when CI=true).
# Every file gets the time SOURCE_DATE_EPOCH, or the commit time of HEAD. Prints the .deb path.
set -euo pipefail

kind=deb
out=dist
allow_dirty=0

usage() {
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

die() {
    echo "build-deb: $*" >&2
    exit 1
}

while (($# > 0)); do
    case $1 in
        --kind)
            [[ $# -ge 2 ]] || die "--kind needs a value (deb or apt)"
            kind=$2
            shift 2
            ;;
        --out)
            [[ $# -ge 2 ]] || die "--out needs a directory"
            out=$2
            shift 2
            ;;
        --allow-dirty)
            allow_dirty=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage
            die "unknown argument: $1"
            ;;
    esac
done

case $kind in
    deb | apt) ;;
    *) die "--kind must be deb or apt, not '$kind'" ;;
esac

root=$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

# Version: the VERSION file, strict X.Y.Z, equal to the one the script prints.
[[ -f VERSION ]] || die "VERSION is missing"
version=$(tr -d '[:space:]' < VERSION)
re_version='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
[[ $version =~ $re_version ]] || die "VERSION '$version' is not X.Y.Z"
script_version=$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' gft | head -n 1)
[[ $script_version == "$version" ]] ||
    die "VERSION is $version but the VERSION= line of gft is '$script_version'"

for f in gft gft.1 completions/gft.bash completions/_gft LICENSE packaging/nfpm.yaml packaging/deb/lintian-overrides; do
    [[ -f $f ]] || die "$f is missing"
done
command -v nfpm > /dev/null 2>&1 || die "nfpm is not installed (see packaging/RELEASING.md)"

# Timestamp: SOURCE_DATE_EPOCH, else the commit time of HEAD.
if [[ -z ${SOURCE_DATE_EPOCH:-} ]]; then
    SOURCE_DATE_EPOCH=$(git log -1 --format=%ct 2> /dev/null) ||
        die "not a git checkout: set SOURCE_DATE_EPOCH"
fi
[[ $SOURCE_DATE_EPOCH =~ ^[0-9]+$ ]] || die "SOURCE_DATE_EPOCH '$SOURCE_DATE_EPOCH' is not a number"

# Only committed files are released; an apt package comes from the tagged commit.
if ((allow_dirty == 0)) && git rev-parse --git-dir > /dev/null 2>&1; then
    dirty=$(git status --porcelain -- VERSION gft gft.1 completions LICENSE packaging/nfpm.yaml packaging/deb)
    [[ -z $dirty ]] || die "uncommitted changes in the files of the package (--allow-dirty for a test):
$dirty"
    if [[ $kind == apt ]]; then
        tagged=$(git rev-parse -q --verify "refs/tags/$version^{commit}" || true)
        [[ -n $tagged && $tagged == "$(git rev-parse HEAD)" ]] ||
            die "HEAD is not the commit tagged $version: check it out before building the apt package"
    fi
fi

mkdir -p -- "$out"
deb=$(cd "$out" && pwd)/gft_${version}_all.deb
[[ ! -e $deb ]] || die "$deb already exists: remove it or choose another --out"

stage=$(mktemp -d "${TMPDIR:-/tmp}/gft-stage.XXXXXX")
trap 'rm -f "$stage/gft.1.gz" "$stage/install-method" "$stage/gft_${version}_all.deb"; rmdir "$stage" 2> /dev/null || true' EXIT

# Man page: gzip -n keeps neither a name nor a time, so the bytes depend on the page only.
gzip -9n -c gft.1 > "$stage/gft.1.gz"
gzip -t "$stage/gft.1.gz"
# The marker read by gft: two lines, nothing else.
printf 'install_method=apt\npackage=%s\n' "$kind" > "$stage/install-method"

export GFT_VERSION=$version GFT_STAGE=$stage SOURCE_DATE_EPOCH TZ=UTC LC_ALL=C
echo "build-deb: gft $version ($kind), nfpm $(nfpm --version | grep -Eom1 '[0-9]+\.[0-9]+\.[0-9]+' || echo unknown)" >&2
staged=$stage/gft_${version}_all.deb
nfpm package --config packaging/nfpm.yaml --packager deb --target "$staged" >&2
[[ -f $staged ]] || die "nfpm did not write $staged"

if command -v lintian > /dev/null 2>&1; then
    lintian -I --pedantic --fail-on error,warning --tag-display-limit 0 "$staged" >&2
elif [[ ${CI:-} == true ]]; then
    die "lintian is not installed"
else
    echo "build-deb: lintian is not installed, not linted" >&2
fi

# Only a linted package reaches the output folder.
mv -- "$staged" "$deb"
echo "$deb"
