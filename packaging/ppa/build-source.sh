#!/usr/bin/env bash
# Build the Ubuntu source packages of gft for the Launchpad PPA, one per series.
#
#   build-source.sh [options] SERIES...
#   build-source.sh --version 1.2.2 jammy noble resolute
#   build-source.sh --dry-run noble
#
# Run by the maintainer only: debuild and dpkg-source delete their own temporary copies, and
# signing needs the passphrase of the OpenPGP key registered on Launchpad. Nothing is uploaded:
# the dput commands are printed at the end. Stable versions only: betas never go to the PPA,
# which keeps only the highest version per series.
#
# 1. Orig tarball: `git archive` of the tag VERSION (no "v"), made reproducible so that every
#    series and every later rebuild share the same gft_<version>.orig.tar.gz byte for byte.
#    An existing orig is reused, never rebuilt (Launchpad rejects a name with other content).
# 2. Per series: a fresh tree from that orig, debian/ from packaging/debian of the same tree,
#    one changelog entry with the version <upstream>-0ppa<N>~<YY.MM>.1, then `debuild -S -sa`.
# 3. The installed files are the ones of the GitHub .deb, except install-method (package=ppa).
#
# Options:
#   --version X   upstream version to package (default: the VERSION file of the ref, or of HEAD)
#   --ref REF     git ref to package (default: the tag X; with --dry-run: HEAD; otherwise only X's commit)
#   --out DIR     output directory, outside the checkout (default: /tmp/gft-ppa)
#   --dry-run     unsigned source packages (-us -uc) and no key needed, to check the build only
#   --no-build    prepare the orig and the trees only, run neither debuild nor dpkg-source
#
# Environment:
#   SIGN_KEY      OpenPGP key id or fingerprint that signs the uploads, registered on Launchpad
#                 (required unless --dry-run or --no-build; never stored in the repository)
#   GFT_SRC       gft git checkout (default: the one that holds this script)
#   MAINTAINER    changelog trailer, a user ID of SIGN_KEY (default: 20syldev <git@sylvain.sh>)
#   PPA_REV       N in 0ppaN: raise it to rebuild the same upstream version (default: 1)
#   PPA           upload target (default: ppa:20syldev/gft)
#   MESSAGE       changelog line (default: "New upstream release VERSION.")
#   SOURCE_DATE_EPOCH  file times in the orig (default: commit time of the ref); also the
#                 changelog date (default: now)
#
# No recursive delete: the script refuses to reuse an existing tree, and it never runs the
# debian/rules clean target (fresh tree, dpkg-buildpackage -nc).
set -euo pipefail

usage() {
    sed -n '2,39p' "$0" >&2
    exit 2
}
die() {
    echo "build-source.sh: $*" >&2
    exit 1
}

version="" ref="" out=/tmp/gft-ppa dry_run=0 no_build=0
series=()
while (($#)); do
    case $1 in
        --version | --ref | --out)
            (($# >= 2)) || die "$1 needs a value"
            case $1 in
                --version) version=$2 ;;
                --ref) ref=$2 ;;
                --out) out=$2 ;;
            esac
            shift 2
            ;;
        --dry-run) dry_run=1; shift ;;
        --no-build) no_build=1; shift ;;
        -h | --help) usage ;;
        -*) die "unknown option: $1" ;;
        *) series+=("$1"); shift ;;
    esac
done
((${#series[@]} > 0)) || usage

# No compiler constraint: the floor is debhelper-compat 13, so focal (debhelper 12) is out.
declare -A series_version=([jammy]=22.04 [noble]=24.04 [resolute]=26.04 [stonking]=26.10 [tenacious]=27.04)
for s in "${series[@]}"; do
    [[ -n ${series_version[$s]:-} ]] ||
        die "unsupported series '$s' (supported: ${!series_version[*]})"
done

src=$(cd "${GFT_SRC:-$(dirname "$0")/../..}" && pwd -P)
git -C "$src" rev-parse --git-dir >/dev/null 2>&1 || die "$src is not a git checkout"
if [[ -z $version ]]; then
    version=$(git -C "$src" show "${ref:-HEAD}:VERSION" 2>/dev/null | tr -d '[:space:]') ||
        die "no VERSION file in ${ref:-HEAD}: pass --version"
fi
version=${version#v}
[[ $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
    die "the version must be a stable SemVer without 'v' (1.2.2); betas are not published to the PPA: $version"
if [[ -z $ref ]]; then
    if [[ $dry_run == 1 ]]; then ref=HEAD; else ref=refs/tags/$version; fi
fi

ppa_rev=${PPA_REV:-1}
[[ $ppa_rev =~ ^[1-9][0-9]*$ ]] || die "PPA_REV must be a positive integer: $ppa_rev"
maintainer=${MAINTAINER:-20syldev <git@sylvain.sh>}
message=${MESSAGE:-New upstream release $version.}
ppa=${PPA:-ppa:20syldev/gft}
sign_key=${SIGN_KEY:-}
upstream=$version

mkdir -p "$out"
out=$(cd "$out" && pwd -P)
[[ -O $out ]] || die "$out is not owned by you: pass --out DIR"
case $out/ in
    "$src"/*) die "$out is inside the checkout: pass --out DIR outside $src" ;;
esac
orig=$out/gft_$upstream.orig.tar.gz

needed=(git tar gzip sha256sum)
[[ $no_build == 1 ]] || needed+=(debuild dpkg-source)
for cmd in "${needed[@]}"; do
    command -v "$cmd" >/dev/null || die "'$cmd' is required (git, tar, gzip, devscripts, dpkg-dev)"
done
git -C "$src" rev-parse --verify --quiet "$ref^{tree}" >/dev/null ||
    die "unknown git ref: $ref (tag the release first, or use --dry-run)"
if [[ $dry_run != 1 ]]; then
    tag_commit=$(git -C "$src" rev-parse --verify --quiet "refs/tags/$version^{commit}") ||
        die "no tag $version (tag the release first, or use --dry-run)"
    [[ $(git -C "$src" rev-parse "$ref^{commit}") == "$tag_commit" ]] ||
        die "$ref is not the commit of tag $version: only the tag is packaged (--dry-run takes any ref)"
fi
if [[ $dry_run != 1 && $no_build != 1 ]]; then
    [[ -n $sign_key ]] || die "set SIGN_KEY to the OpenPGP key id registered on Launchpad (or use --dry-run)"
    gpg --batch --list-secret-keys "$sign_key" >/dev/null 2>&1 ||
        die "secret key $sign_key not found (or use --dry-run for an unsigned check)"
fi

# ─── Orig tarball ────────────────────────────────────────────────────

want_ref=$(git -C "$src" rev-parse "$ref^{commit}")
if [[ -e $orig ]]; then
    [[ -f $orig.ref && $(<"$orig.ref") == "$want_ref" ]] ||
        die "$orig was not built from $ref ($want_ref): move it and $orig.ref away"
    echo "Reusing $orig (sha256 $(sha256sum "$orig" | cut -d ' ' -f 1))"
    echo "It must stay byte-identical to anything already uploaded for $upstream."
else
    stage=$out/orig
    tree=$stage/gft-$upstream
    [[ ! -e $tree ]] || die "$tree exists: move it away (nothing is deleted by this script)"
    epoch=${SOURCE_DATE_EPOCH:-$(git -C "$src" show -s --format=%ct "$ref^{commit}" 2>/dev/null || true)}
    [[ $epoch =~ ^[0-9]+$ ]] || die "set SOURCE_DATE_EPOCH ($ref is not a commit)"

    mkdir -p "$stage"
    git -C "$src" archive --format=tar --prefix="gft-$upstream/" "$ref" | tar -x -C "$stage"
    [[ $(tr -d '[:space:]' < "$tree/VERSION") == "$upstream" ]] ||
        die "the VERSION file of $ref is not $upstream"
    [[ $(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$tree/gft") == "$upstream" ]] ||
        die "VERSION= in the gft script of $ref is not $upstream"
    for f in gft gft.1 LICENSE completions/gft.bash completions/_gft \
        packaging/debian/control packaging/debian/rules packaging/debian/copyright \
        packaging/debian/changelog.in packaging/debian/gft.links packaging/debian/gft.manpages \
        packaging/debian/source/format; do
        [[ -f $tree/$f ]] || die "$ref has no $f"
    done

    # Reproducible: sorted names, fixed times, owners and modes, gzip without a timestamp.
    tar --sort=name --format=gnu --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
        --mode='u+rwX,go+rX,go-w' -C "$stage" -cf - "gft-$upstream" | gzip -n -9 > "$orig.tmp"
    mv "$orig.tmp" "$orig"
    printf '%s\n' "$want_ref" > "$orig.ref"
    echo "Created $orig (sha256 $(sha256sum "$orig" | cut -d ' ' -f 1))"
fi

# ─── One source package per series ───────────────────────────────────

changes=()
for s in "${series[@]}"; do
    full=$upstream-0ppa$ppa_rev~${series_version[$s]}.1
    work=$out/$s
    tree=$work/gft-$upstream
    [[ ! -e $tree ]] || die "$tree exists: move it away (nothing is deleted by this script)"
    mkdir -p "$work"
    [[ -e $work/$(basename "$orig") ]] || cp "$orig" "$work/"
    tar -xzf "$orig" -C "$work"

    # The templates come from the orig itself, so a rebuild at a tag is reproducible.
    tpl=$tree/packaging/debian
    mkdir "$tree/debian" "$tree/debian/source"
    for f in control rules copyright gft.links gft.manpages; do
        cp "$tpl/$f" "$tree/debian/$f"
    done
    cp "$tpl/source/format" "$tree/debian/source/format"
    chmod 0755 "$tree/debian/rules"
    printf 'install_method=apt\npackage=ppa\n' > "$tree/debian/install-method"

    date=$(date -R -u -d "@${SOURCE_DATE_EPOCH:-$(date +%s)}")
    entry=$(<"$tpl/changelog.in")
    entry=${entry//@VERSION@/$full}
    entry=${entry//@SERIES@/$s}
    entry=${entry//@MESSAGE@/"$message"}
    entry=${entry//@MAINTAINER@/"$maintainer"}
    entry=${entry//@DATE@/$date}
    printf '%s\n' "$entry" > "$tree/debian/changelog"

    echo
    if [[ $no_build == 1 ]]; then
        echo "=== $s: gft $full (tree prepared in $tree, nothing built)"
        continue
    fi

    # -S source only, -sa the orig in every upload, -d no build-dependency check here, -nc no clean.
    opts=(-S -sa -d -nc)
    if [[ $dry_run == 1 ]]; then
        opts+=(-us -uc)
    else
        opts+=("-k$sign_key")
    fi
    echo "=== $s: gft $full"
    (cd "$tree" && debuild "${opts[@]}")
    changes+=("$work/gft_${full}_source.changes")
done

# ─── Upload commands (printed, never run) ────────────────────────────

if [[ $no_build == 1 ]]; then
    echo
    echo "--no-build: nothing built, nothing to upload."
    exit 0
fi
echo
echo "Source packages ready. Nothing was uploaded."
if [[ $dry_run == 1 ]]; then
    echo "--dry-run: unsigned packages, Launchpad would reject them. Rebuild without it to upload."
fi
dputcf=$HOME/.dput.cf
if [[ -f $dputcf ]] && awk '
        /^\[/ { sec = $0 }
        sec == "[ppa]" && /^[ \t]*incoming[ \t]*[=:]/ && !/%\(ppa\)s/ { bad = 1 }
        END { exit !bad }' "$dputcf"; then
    echo
    echo "WARNING: $dputcf redefines [ppa] with a fixed 'incoming': 'dput $ppa' would go there,"
    echo "not to $ppa. Rename that section (for example to [gft]) before uploading."
fi
echo
echo "Upload (you run these; one Accepted or Rejected mail per upload, then build mails):"
for c in "${changes[@]}"; do
    printf '  dput %s %q\n' "$ppa" "$c"
done
