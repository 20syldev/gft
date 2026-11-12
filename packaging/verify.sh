#!/usr/bin/env bash
# Verify the files of a gft release, the way a user checks a download.
#
#   packaging/verify.sh [--unsigned] [--kind deb|apt] [--pubkey FILE] [<dist-dir>]
#
#   <dist-dir>     default: dist
#   --unsigned     check the .deb only (CI dry run, nothing is signed)
#   --kind K       the package= value the marker must hold (default: deb, the GitHub release)
#   --pubkey FILE  the minisign public key (default: packaging/minisign.pub)
# Needs dpkg-deb and, unless --unsigned, minisign 0.10 or later. Stops at the first failure:
#   - the folder holds gft_<version>_all.deb and, signed, gft_<version>_checksums.txt with its
#     .minisig, and nothing else; the version is the VERSION file of this checkout;
#   - the signature verifies, prehashed, against the public key, and its trusted comment holds
#     project, version, tag, channel, timestamp and file, tab separated;
#   - the checksums file lists the .deb alone and sha256sum -c accepts it;
#   - the package fields, its exact list of files, modes and owners, and the marker are right;
#   - the files are the ones of this checkout (script, completions, man page, licence);
#   - the extracted gfv runs, reports its version, and "gfv update" refuses because of the marker.
# The tag is taken from GITHUB_REF_NAME when it is set (CI), otherwise it is the version.
set -euo pipefail

signed=1
kind=deb
root=$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pubkey=$root/packaging/minisign.pub
dist=

fail() {
    echo "verify: $*" >&2
    exit 1
}

while (($# > 0)); do
    case $1 in
        --unsigned)
            signed=0
            shift
            ;;
        --kind)
            [[ $# -ge 2 ]] || fail "--kind needs a value"
            kind=$2
            shift 2
            ;;
        --pubkey)
            [[ $# -ge 2 ]] || fail "--pubkey needs a file"
            pubkey=$2
            shift 2
            ;;
        -h | --help)
            sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*) fail "unknown option: $1" ;;
        *)
            [[ -z $dist ]] || fail "one directory only"
            dist=$1
            shift
            ;;
    esac
done
dist=${dist:-dist}
case $kind in
    deb | apt) ;;
    *) fail "--kind must be deb or apt" ;;
esac
[[ -d $dist ]] || fail "$dist is not a directory"
dist=$(cd "$dist" && pwd)
command -v dpkg-deb > /dev/null 2>&1 || fail "dpkg-deb is not installed"

# The files of the folder, and the version they carry.
shopt -s nullglob dotglob
files=("$dist"/*)
shopt -u nullglob dotglob
debs=("$dist"/gft_*_all.deb)
((${#debs[@]} == 1)) || fail "expected one gft_<version>_all.deb in $dist, found ${#debs[@]}"
debname=${debs[0]##*/}
deb=$dist/$debname
version=${debname#gft_}
version=${version%_all.deb}
re_version='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
[[ $version =~ $re_version ]] || fail "$debname: '$version' is not an X.Y.Z version"
[[ $version == "$(tr -d '[:space:]' < "$root/VERSION")" ]] || fail "$debname does not match the VERSION file"

tab=$'\t'
sums=$dist/gft_${version}_checksums.txt
sumsname=${sums##*/}
sig=$sums.minisig
if ((signed)); then
    ((${#files[@]} == 3)) || fail "expected $debname, $sumsname and $sumsname.minisig in $dist, found ${#files[@]} files"
    [[ -f $sums ]] || fail "$sumsname is missing"
    [[ -f $sig ]] || fail "$sumsname.minisig is missing"
    command -v minisign > /dev/null 2>&1 || fail "minisign is not installed"
    [[ -s $pubkey ]] || fail "the public key $pubkey is missing: the maintainer commits it as packaging/minisign.pub"

    comment=$(minisign -V -H -Q -p "$pubkey" -x "$sig" -m "$sums" 2> /dev/null) ||
        fail "$sumsname.minisig does not verify against $pubkey"
    tag=${GITHUB_REF_NAME:-$version}
    want="project:gft${tab}version:$version${tab}tag:$tag${tab}channel:stable${tab}timestamp:"
    rest=${comment#"$want"}
    [[ $rest != "$comment" && $rest =~ ^[0-9]+${tab}file:$sumsname$ ]] ||
        fail "unexpected trusted comment: $comment"

    [[ $(wc -l < "$sums") -eq 1 && $(grep -c -E "^[0-9a-f]{64}  $debname\$" "$sums") -eq 1 ]] ||
        fail "$sumsname must list $debname alone"
    (cd "$dist" && sha256sum --strict -c "$sumsname" > /dev/null) || fail "sha256sum -c failed"
else
    ((${#files[@]} == 1)) || fail "expected $debname alone in $dist, found ${#files[@]} files"
fi
[[ $debname != *"~"* ]] || fail "a \"~\" in the file name $debname"

# Package fields.
field() { dpkg-deb -f "$deb" "$1"; }
[[ $(field Package) == gft ]] || fail "Package is '$(field Package)', expected gft"
[[ $(field Version) == "$version-1" ]] || fail "Version is '$(field Version)', expected $version-1"
[[ $(field Architecture) == all ]] || fail "Architecture is '$(field Architecture)', expected all"
[[ $(field Maintainer) == "20syldev <git@sylvain.sh>" ]] || fail "unexpected Maintainer: $(field Maintainer)"
[[ $(field Depends) == "curl, mawk | gawk" ]] || fail "unexpected Depends: $(field Depends)"

# The exact list of files with their type, mode and owner, directories left aside.
listing=$(dpkg-deb -c "$deb" | while read -r perm owner _ _ _ path rest; do
    [[ $perm == d* ]] || echo "$perm $owner ${path#./}${rest:+ $rest}"
done | LC_ALL=C sort -k3,3)
expected="-rwxr-xr-x root/root usr/bin/gft
lrwxrwxrwx root/root usr/bin/gfv -> gft
-rw-r--r-- root/root usr/share/bash-completion/completions/gft
lrwxrwxrwx root/root usr/share/bash-completion/completions/gfv -> gft
-rw-r--r-- root/root usr/share/doc/gft/copyright
-rw-r--r-- root/root usr/share/gft/install-method
-rw-r--r-- root/root usr/share/lintian/overrides/gft
-rw-r--r-- root/root usr/share/man/man1/gft.1.gz
lrwxrwxrwx root/root usr/share/man/man1/gfv.1.gz -> gft.1.gz
-rw-r--r-- root/root usr/share/zsh/vendor-completions/_gft"
expected=$(printf '%s\n' "$expected" | LC_ALL=C sort -k3,3)
if [[ $listing != "$expected" ]]; then
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$listing") >&2 || true
    fail "the files of $debname are not the expected ones (see the diff above)"
fi

# Read one file of the package, whether its names start with "./" or not.
names=$(dpkg-deb --fsys-tarfile "$deb" | tar -tf -)
resolve() { grep -x -F -e "$1" -e "./$1" <<< "$names" | head -n 1; }
member() { dpkg-deb --fsys-tarfile "$deb" | tar -xOf - "$(resolve "$1")"; }
[[ $(member usr/share/gft/install-method) == $'install_method=apt\npackage='$kind ]] ||
    fail "the marker is not 'install_method=apt' then 'package=$kind'"
member usr/bin/gft | cmp -s - "$root/gft" || fail "usr/bin/gft is not the gft of this checkout"
member usr/share/bash-completion/completions/gft | cmp -s - "$root/completions/gft.bash" ||
    fail "the bash completion is not the one of this checkout"
member usr/share/zsh/vendor-completions/_gft | cmp -s - "$root/completions/_gft" ||
    fail "the zsh completion is not the one of this checkout"
member usr/share/doc/gft/copyright | cmp -s - "$root/LICENSE" || fail "the copyright is not LICENSE"
member usr/share/man/man1/gft.1.gz | gzip -dc | cmp -s - "$root/gft.1" ||
    fail "the man page is not gft.1 of this checkout"
member usr/share/lintian/overrides/gft | cmp -s - "$root/packaging/deb/lintian-overrides" ||
    fail "the lintian override is not the one of this checkout"

# Run the packaged script from a scratch copy of its own layout, with an empty HOME.
work=$(mktemp -d "${TMPDIR:-/tmp}/gft-verify.XXXXXX")
cleanup() {
    rm -f "$work/usr/bin/gft" "$work/usr/bin/gfv" "$work/usr/share/gft/install-method"
    rmdir "$work/usr/bin" "$work/usr/share/gft" "$work/usr/share" "$work/usr" "$work/home" "$work" 2> /dev/null ||
        echo "verify: left in $work" >&2
}
trap cleanup EXIT
mkdir "$work/home"
dpkg-deb --fsys-tarfile "$deb" | tar -x -m -C "$work" \
    "$(resolve usr/bin/gft)" "$(resolve usr/bin/gfv)" "$(resolve usr/share/gft/install-method)"
run() { env -i HOME="$work/home" PATH=/usr/bin:/bin GFT_NO_SPINNER=1 "$work/usr/bin/gfv" "$@" < /dev/null 2>&1; }

first=$(run --version) || fail "gfv --version failed"
[[ $first == "gft $version" ]] || fail "gfv --version says '$first', expected 'gft $version'"

# The marker must stop the self-update, which would otherwise rewrite files under HOME.
rc=0
out=$(run update) || rc=$?
((rc == 1)) || fail "gfv update exited $rc, expected 1"
if [[ $kind == deb ]]; then
    hint="sudo apt install ./gft_"
else
    hint="sudo apt update && sudo apt upgrade gft"
fi
[[ $out == *"$hint"* ]] || fail "gfv update does not print '$hint'"
[[ -z $(ls -A "$work/home") ]] || fail "gfv update wrote into HOME"

note=
((signed)) && note=", $sumsname signed and checked"
echo "verify: $debname ok (package=$kind, files, marker, gfv runs and refuses to update$note)"
