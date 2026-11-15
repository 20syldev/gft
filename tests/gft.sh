#!/bin/bash
# Offline tests for gft, with a fake curl.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GFT="$ROOT/gft"
FILTER="${1:-}"

T=$(mktemp -d "${TMPDIR:-/tmp}/gft-tests.XXXXXX")
mkdir -p "$T/bin" "$T/home" "$T/fake" "$T/nogh"
cp "$ROOT/tests/fakecurl" "$T/bin/curl"
chmod +x "$T/bin/curl"
# A fixed platform, so that --detect gives the same answer everywhere.
cat > "$T/bin/uname" <<'EOF'
#!/bin/sh
case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; *) exec /usr/bin/uname "$@" ;; esac
EOF
chmod +x "$T/bin/uname"

export HOME="$T/home" FAKE_DIR="$T/fake" GFT_NO_SPINNER=1 GH_CONFIG_DIR="$T/nogh" GFT_CACHE_TTL=0
export PATH="$T/bin:$PATH"
unset GH_TOKEN GITHUB_TOKEN NO_COLOR GFT_PLAIN_TIMEOUT FAKE_SLEEP FAKE_LOG_ARGS
CACHE_N=0

pass=0 fail=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
ko() { echo "FAIL  $1"; fail=$((fail + 1)); [[ -z "${2:-}" ]] || echo "      $2"; }
# check "name" 'test expression'
check() {
    [[ -z "$FILTER" || "$1" == *"$FILTER"* ]] || return 0
    if eval "$2"; then ok "$1"; else ko "$1" "rc=$RC out=[$(head -c 300 <<<"$OUT")] err=[$(head -c 300 <<<"$ERR")]"; fi
}

# ─── helpers ─────────────────────────────────────────────────────────

# New cache folder and empty fake server: every scenario starts clean.
fresh() {
    CACHE_N=$((CACHE_N + 1))
    export GFT_CACHE_DIR="$T/cache.$CACHE_N"
    : > "$FAKE_DIR/map"
    : > "$FAKE_DIR/calls"
    : > "$FAKE_DIR/args"
    unset FAKE_SLEEP FAKE_LOG_ARGS GFT_PLAIN_TIMEOUT
    export GFT_CACHE_TTL=0
}

# map_add URL STATUS FILE [EFFECTIVE_URL]: sets the answer for URL, replacing an earlier one
map_add() {
    awk -F'\t' -v u="$1" '$1 != u' "$FAKE_DIR/map" > "$FAKE_DIR/map.new"
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}" >> "$FAKE_DIR/map.new"
    mv "$FAKE_DIR/map.new" "$FAKE_DIR/map"
}

# The pages of repository o/r with its latest release v2.0.0.
base() {
    fresh
    map_add https://github.com/o/r 200 -
    map_add https://github.com/o/r/releases/latest 200 - https://github.com/o/r/releases/tag/v2.0.0
}

# mk_releases FILE entry...: entry = TAG|TITLE|DATE|pre (TAG as written in the link)
mk_releases() {
    local file="$FAKE_DIR/$1" e tag title date pre
    shift
    {
        echo '<html><body>'
        for e in "$@"; do
            IFS='|' read -r tag title date pre <<< "$e"
            echo "  <section id=\"release-$tag\" aria-labelledby=\"hd-x\">"
            echo "    <span class=\"f1\"><a href=\"/o/r/releases/tag/$tag\" data-view-component=\"true\" class=\"Link--primary Link\">$title</a></span>"
            echo "    <relative-time class=\"no-wrap\" datetime=\"${date}T10:00:00Z\">x</relative-time>"
            [[ "$pre" != pre ]] || echo '    <span class="Label Label--warning Label--large">Pre-release</span>'
            echo '  </section>'
        done
        echo '</body></html>'
    } > "$file"
}

# mk_assets FILE TAG name...: names are written as in the links (already percent-encoded)
mk_assets() {
    local file="$FAKE_DIR/$1" tag="$2" n
    shift 2
    {
        for n in "$@"; do
            echo "<li class=\"Box-row\"><a href=\"/o/r/releases/download/$tag/$n\" rel=\"nofollow\" class=\"wb-break-all\"><span>$n</span></a></li>"
        done
    } > "$file"
}

# serve_file NAME TAG CONTENT: a downloadable asset with that content
serve_file() {
    mkdir -p "$FAKE_DIR/files"
    printf '%s' "$3" > "$FAKE_DIR/files/$1"
    map_add "https://github.com/o/r/releases/download/$2/$1" 200 "files/$1"
}

# run ARGS...: sets OUT ERR RC and ELAPSED; stdin is /dev/null, like tote
run() {
    local start=$SECONDS
    "$GFT" "$@" > "$T/out" 2> "$T/err" < /dev/null
    RC=$?
    ELAPSED=$((SECONDS - start))
    OUT=$(<"$T/out")
    ERR=$(<"$T/err")
}

has_esc() { grep -q $'\033' "$1"; }
NL=$'\n'
TAB=$'\t'

# ─── plain: releases ─────────────────────────────────────────────────

base
mk_releases releases.html "v2.0.0|Two|2026-03-02" "v1.5.0-rc.1|Candidate|2026-02-01|pre" "v1.0.0|One|2025-12-24"
map_add https://github.com/o/r/releases 200 releases.html
run --releases --plain -- o/r
check "plain releases: stable only, tab separated, newest first" \
    '[[ "$OUT" == "v2.0.0${TAB}2026-03-02${NL}v1.0.0${TAB}2025-12-24" && $RC -eq 0 ]]'
run --releases --plain --pre -- o/r
check "plain releases --pre: pre-release gets a third column" \
    '[[ "$OUT" == "v2.0.0${TAB}2026-03-02${NL}v1.5.0-rc.1${TAB}2026-02-01${TAB}prerelease${NL}v1.0.0${TAB}2025-12-24" ]]'
run --releases --plain --pre=false -- o/r
check "plain releases --pre=false behaves like no --pre" '[[ "$OUT" == "v2.0.0${TAB}2026-03-02${NL}v1.0.0${TAB}2025-12-24" ]]'
run --releases --plain -- o/r
check "plain: no ANSI on stdout or stderr" '! has_esc "$T/out" && ! has_esc "$T/err"'
check "plain: no 'Looking up', tip or title on stdout" '[[ "$OUT" != *Looking* && "$OUT" != *Tip* && "$OUT" != *Releases* ]]'
check "plain releases never use gh or the API (only github.com pages)" \
    '! grep -q "api.github.com" "$FAKE_DIR/calls"'

# ─── plain: assets ───────────────────────────────────────────────────

base
mk_assets assets.html v2.0.0 tool_linux_amd64.tar.gz tool_linux_amd64.deb tool_darwin_arm64.tar.gz checksums.txt tool_linux_amd64.tar.gz
map_add https://github.com/o/r/releases/expanded_assets/v2.0.0 200 assets.html
run --assets --plain -- o/r
check "plain assets: sorted, no duplicate" \
    '[[ "$OUT" == "checksums.txt${NL}tool_darwin_arm64.tar.gz${NL}tool_linux_amd64.deb${NL}tool_linux_amd64.tar.gz" && $RC -eq 0 ]]'
run --assets --detect --plain -- o/r
check "plain assets --detect: recommended first with a second column, no package or checksum" \
    '[[ "$OUT" == "tool_linux_amd64.tar.gz${TAB}recommended${NL}checksums.txt${NL}tool_darwin_arm64.tar.gz${NL}tool_linux_amd64.deb" ]]'
run --detect --plain -- o/r
check "plain --detect alone lists assets" '[[ "$OUT" == tool_linux_amd64.tar.gz${TAB}recommended* ]]'
map_add https://github.com/o/r/releases/expanded_assets/v1.0.0 200 assets.html
run --assets --plain -- o/r v1.0.0
check "plain assets with a tag" '[[ $RC -eq 0 && "$OUT" == checksums.txt* ]]'
base
mk_assets assets.html v2.0.0 "a%20b%2Bc.txt" "plain+plus.txt" "caf%C3%A9.bin"
map_add https://github.com/o/r/releases/expanded_assets/v2.0.0 200 assets.html
run --assets --plain -- o/r
check "plain assets: names are decoded" '[[ "$OUT" == "a b+c.txt${NL}café.bin${NL}plain+plus.txt" ]]'

# ─── plain: exit codes and silence ───────────────────────────────────

base
map_add https://github.com/o/r/releases 200 -
run --releases --plain -- o/r
check "plain: nothing to list is exit 0 with empty output" '[[ $RC -eq 0 && -z "$OUT" ]]'
base
mk_assets assets.html v2.0.0
map_add https://github.com/o/r/releases/expanded_assets/v2.0.0 200 assets.html
run --assets --plain -- o/r
check "plain assets: release without assets is exit 0, empty" '[[ $RC -eq 0 && -z "$OUT" ]]'
base
map_add https://github.com/o/r/releases/latest 200 - https://github.com/o/r/releases
map_add https://github.com/o/r/releases 200 -
run --assets --plain -- o/r
check "plain assets: repository without a release is exit 0, empty" '[[ $RC -eq 0 && -z "$OUT" ]]'
fresh
map_add https://github.com/o/r 404 -
run --releases --plain -- o/r
check "plain: unknown repository is exit 1, message on stderr only" '[[ $RC -eq 1 && -z "$OUT" && "$ERR" == *"not found"* ]] && ! has_esc "$T/err"'
fresh
map_add https://github.com/o/r 000 -
run --releases --plain -- o/r
check "plain: network error is exit 1, nothing on stdout" '[[ $RC -eq 1 && -z "$OUT" ]]'
base
map_add https://github.com/o/r/releases 000 -
run --releases --plain -- o/r
check "plain releases: page fetch failure is exit 1" '[[ $RC -eq 1 && -z "$OUT" && "$ERR" == *"could not fetch"* ]]'
base
map_add https://github.com/o/r/releases/expanded_assets/v2.0.0 404 -
run --assets --plain -- o/r
check "plain assets: unknown assets page is exit 1" '[[ $RC -eq 1 && -z "$OUT" ]]'
for args in "--plain -- o/r" "--plain --json --releases -- o/r" "--releases --assets --plain -- o/r" "--releases --plain --get x -- o/r" \
    "--releases --plain -q -- o/r" "--releases --plain --pre=maybe -- o/r" "--releases --plain --dir= -- o/r" "--releases --plain"; do
    base
    # shellcheck disable=SC2086
    run $args
    if [[ "$args" == *"--dir="* ]]; then want=1; else want=2; fi
    check "plain usage error '$args' is exit $want, stdout empty and no ANSI" \
        '[[ $RC -eq $want && -z "$OUT" ]] && ! has_esc "$T/out" && ! has_esc "$T/err"'
done
base
run --plain --nope --releases -- o/r
check "plain: an unknown option writes to stderr only, without ANSI, exit 2" \
    '[[ $RC -eq 2 && -z "$OUT" ]] && ! has_esc "$T/out" && ! has_esc "$T/err" && [[ "$ERR" == *"Unknown option"* ]]'
run --nope
check "without --plain an unknown option is still exit 1" '[[ $RC -eq 1 ]]'

# ─── plain: hostile names ────────────────────────────────────────────

base
many=()
for i in $(seq 1 230); do many+=("n$i|N$i|2026-01-01"); done
mk_releases releases.html \
    "ok1|A|2026-01-01" "ok1|A again|2026-01-01" "v1%1B%5B31mred|esc|2026-01-02" "a%E2%80%AEb|bidi|2026-01-02" \
    "z%E2%80%8Bw|zero width|2026-01-02" "n%00x|nul|2026-01-02" "t%09x|tab|2026-01-02" "x..y|range|2026-01-02" \
    "latest|l|2026-01-02" "main|m|2026-01-02" "master|ms|2026-01-02" "LATEST|L|2026-01-02" "bad%FFbyte|latin1|2026-01-02" \
    "nel%C2%85x|nel|2026-01-02" "bom%EF%BB%BFx|bom|2026-01-02" "nl%0Ax|newline|2026-01-02" "del%7Fx|del|2026-01-02" \
    "sep%E2%80%A8x|lsep|2026-01-02" "tagc%F3%A0%80%81x|tagchar|2026-01-02" "fine@7|ok|2026-01-03" "caf%C3%A9|ok|2026-01-04" \
    "${many[@]}"
map_add https://github.com/o/r/releases 200 releases.html
run --releases --plain -- o/r
check "hostile tags: only the harmless ones stay, in page order" \
    '[[ "$(head -3 <<<"$OUT" | cut -f1 | tr "\n" " ")" == "ok1 fine@7 café " && $RC -eq 0 ]]'
check "hostile tags: no control or format character reaches stdout" \
    '! LC_ALL=C grep -qP "[\x00-\x08\x0b-\x1f\x7f]|\xc2[\x80-\x9f\xad]|\xe2\x80[\x8b-\x8f\xa8-\xae]|\xef\xbb\xbf|\xf3\xa0" "$T/out" && ! grep -q "^v1" "$T/out"'
check "hostile tags: at most 200 lines" '[[ $(wc -l < "$T/out") -le 200 ]]'
check "hostile tags: 'latest', 'main', 'master' and ranges are dropped, in any case" \
    '! cut -f1 "$T/out" | grep -qixE "latest|main|master" && ! grep -q "\.\." "$T/out"'
check "hostile tags: no duplicate" '[[ $(cut -f1 "$T/out" | sort | uniq -d | wc -l) -eq 0 ]]'

base
mk_assets assets.html v2.0.0 good.bin "esc%1B%5B2Jx" "bidi%E2%80%AEx.exe" "zw%E2%80%8Bx" "tab%09x" "nul%00x" "bad%FF" "good.bin" "dir%2Fx" "ctl%0Ax"
map_add https://github.com/o/r/releases/expanded_assets/v2.0.0 200 assets.html
run --assets --plain -- o/r
check "hostile assets: only the harmless name stays, once (no slash, no control character)" \
    '[[ "$OUT" == "good.bin" ]]'
mk_assets assets.html v2.0.0 $(for i in $(seq 1 250); do echo "f$i.bin"; done)
run --assets --plain -- o/r
check "assets: 200 lines at most" '[[ $(wc -l < "$T/out") -eq 200 ]]'

# ─── plain: one global deadline, no error page cached ────────────────

base
mk_assets assets.html v2.0.0 a.bin
map_add https://github.com/o/r/releases/expanded_assets/v2.0.0 200 assets.html
export FAKE_SLEEP=2 FAKE_LOG_ARGS=1 GFT_PLAIN_TIMEOUT=3
run --assets --plain -- o/r
unset FAKE_SLEEP FAKE_LOG_ARGS GFT_PLAIN_TIMEOUT
check "plain deadline: the run ends near the limit, exit 1" '[[ $RC -eq 1 && $ELAPSED -le 4 ]]'
check "plain deadline: each curl gets only the time left" \
    '[[ $(sed -n "1s/max-time=\([0-9]*\).*/\1/p" "$FAKE_DIR/args") -eq 2 || $(sed -n "1s/max-time=\([0-9]*\).*/\1/p" "$FAKE_DIR/args") -eq 3 ]] && [[ $(sed -n "2s/max-time=\([0-9]*\)\..*/\1/p" "$FAKE_DIR/args") -le 1 ]]'

base
export GFT_CACHE_TTL=300
map_add https://github.com/o/r/releases 500 error.html
printf '<html>Unicorn</html>' > "$FAKE_DIR/error.html"
run --releases --plain -- o/r
check "error page: exit 1 and nothing cached" '[[ $RC -eq 1 && -z "$OUT" && ! -e "$GFT_CACHE_DIR" ]] || [[ $RC -eq 1 && -z "$(ls -A "$GFT_CACHE_DIR" 2>/dev/null)" ]]'
mk_releases releases.html "v2.0.0|Two|2026-03-02"
map_add https://github.com/o/r/releases 200 releases.html
run --releases --plain -- o/r
check "after an error page, the real page is read (the error was not cached)" '[[ "$OUT" == "v2.0.0${TAB}2026-03-02" ]]'
base
map_add https://github.com/o/r/releases/expanded_assets/v2.0.0 404 error.html
printf '<html>Not found</html>' > "$FAKE_DIR/error.html"
run o/r --assets
check "non-plain: an assets 404 page is not cached either" '[[ -z "$(ls -A "$GFT_CACHE_DIR" 2>/dev/null)" ]]'

# ─── cache folder ────────────────────────────────────────────────────

base
export GFT_CACHE_TTL=300
mk_releases releases.html "v2.0.0|Two|2026-03-02"
map_add https://github.com/o/r/releases 200 releases.html
run --releases --plain -- o/r
check "GFT_CACHE_DIR receives the cache entries" '[[ -n "$(ls "$GFT_CACHE_DIR")" && ! -e "$HOME/.config/gft/cache" ]]'
touch "$GFT_CACHE_DIR/keepme"
run --clear-cache
check "--clear-cache only removes cache entries from a custom folder" '[[ -e "$GFT_CACHE_DIR/keepme" && -z "$(ls "$GFT_CACHE_DIR" | grep https)" ]]'
export GFT_CACHE_DIR=/proc/gft-no-such/cache
run --releases --plain -- o/r
check "an unwritable cache prints nothing and does not fail the command" '[[ $RC -eq 0 && -z "$ERR" && "$OUT" == v2.0.0* ]]'
unset GFT_CACHE_DIR

# ─── --option=value and booleans ─────────────────────────────────────

base
mk_releases releases.html "v2.0.0|Two|2026-03-02"
map_add https://github.com/o/r/releases 200 releases.html
for v in true TRUE 1 yes on Yes false 0 no OFF; do
    run o/r -q --pre="$v" --no-cache="$v" --checksum="$v"
    check "boolean value '$v' is accepted" '[[ $RC -eq 0 && "$OUT" == v2.0.0 ]]'
done
for v in maybe "" 2 truee; do
    run o/r -q --pre="$v"
    check "boolean value '$v' is a usage error (2)" '[[ $RC -eq 2 ]]'
done
run o/r -q --no-cache=perhaps
check "--no-cache=perhaps is a usage error (2)" '[[ $RC -eq 2 ]]'
run o/r -q --verify=none
check "--verify=none is a usage error (2)" '[[ $RC -eq 2 ]]'
run o/r -q --source=rar
check "--source=rar keeps the 1.2 status 1" '[[ $RC -eq 1 ]]'
mkdir -p "$T/home/x"
run o/r --source=zip --dir="$T/missing"
check "--dir to a missing folder is refused" '[[ $RC -eq 1 && "$OUT$ERR" == *"not a writable folder"* ]]'

# ─── exact asset name, ambiguity ─────────────────────────────────────

base
names=(tool_linux_amd64 tool_linux_amd64.sig tool_linux_amd64.pem tool_linux_amd64.sbom.json "a%20b%2Bc.txt")
mk_assets assets.html v2.0.0 "${names[@]}"
map_add https://github.com/o/r/releases/expanded_assets/v2.0.0 200 assets.html
serve_file tool_linux_amd64 v2.0.0 BINARY
serve_file tool_linux_amd64.sig v2.0.0 SIG
serve_file "a%20b%2Bc.txt" v2.0.0 SPACED
D="$T/dl1"; mkdir -p "$D"
run o/r --asset=tool_linux_amd64 --dir="$D"
check "--asset: exact name among close names" '[[ $RC -eq 0 && "$(cat "$D/tool_linux_amd64")" == BINARY && ! -e "$D/tool_linux_amd64.sig" ]]'
run o/r --asset tool_linux_amd64.sig --dir "$D"
check "--asset NAME (separate form) works too" '[[ $RC -eq 0 && "$(cat "$D/tool_linux_amd64.sig")" == SIG ]]'
run o/r --asset="a b+c.txt" --dir="$D"
check "--asset: the name is the decoded one, saved under that name" '[[ $RC -eq 0 && "$(cat "$D/a b+c.txt")" == SPACED ]]'
run o/r --asset=tool_linux --dir="$D"
check "--asset: no substring match" '[[ $RC -eq 1 && "$OUT$ERR" == *"No asset named"* ]]'
run o/r --asset='tool_linux_amd6.' --dir="$D"
check "--asset: no regular expression" '[[ $RC -eq 1 ]]'
run o/r --asset=TOOL_LINUX_AMD64 --dir="$D"
check "--asset: case sensitive" '[[ $RC -eq 1 ]]'
for bad in "../x" ".hidden" "a/b" "" "a\\b" ".."; do
    run o/r --asset="$bad" --dir="$D"
    check "--asset='$bad' is refused (usage error 2)" '[[ $RC -eq 2 ]]'
done
run o/r --asset=x --get y --dir="$D"
check "--asset with --get is a usage error (2)" '[[ $RC -eq 2 ]]'
run o/r --get tool_linux_amd64 --dir="$D"
check "--get with several matches and no terminal: exit 2, list on stderr, no prompt" \
    '[[ $RC -eq 2 && "$ERR" == *"Multiple assets"* && "$ERR" == *tool_linux_amd64.pem* && "$ERR" == *"--asset=NAME"* ]]'
run o/r --get 'a%20b' --dir="$D"
check "--get keeps working with a single match (regex, unchanged)" '[[ $RC -eq 0 && -e "$D/a%20b%2Bc.txt" ]]'
run o/r --get 'tool_linux_amd64\.sig$' --dir="$D" --force
check "--get is still a case-insensitive basic regex" '[[ $RC -eq 0 ]]'

# ─── no silent overwrite, --force, -f ────────────────────────────────

D="$T/dl2"; mkdir -p "$D"
echo OLD > "$D/tool_linux_amd64"
run o/r --asset=tool_linux_amd64 --dir="$D"
check "no overwrite without --force: exit 1 and the file is untouched" '[[ $RC -eq 1 && "$(cat "$D/tool_linux_amd64")" == OLD && "$OUT$ERR" == *"--force"* ]]'
run o/r --asset=tool_linux_amd64 --dir="$D" --force
check "--force replaces the file" '[[ $RC -eq 0 && "$(cat "$D/tool_linux_amd64")" == BINARY ]]'
ln -s "$T/elsewhere" "$D/linked"
echo KEEP > "$T/elsewhere"
serve_file linked v2.0.0 NEW
mk_assets assets.html v2.0.0 linked
run o/r --asset=linked --dir="$D" --force
check "--force replaces a symlink itself, never writes through it" '[[ $RC -eq 0 && "$(cat "$T/elsewhere")" == KEEP && ! -L "$D/linked" && "$(cat "$D/linked")" == NEW ]]'
mk_assets assets.html v2.0.0 missing.bin
run o/r --asset=missing.bin --dir="$D"
check "a 404 body is never saved as the asset (curl -f)" '[[ $RC -eq 1 && ! -e "$D/missing.bin" && -z "$(ls "$D" | grep part)" ]]'
run o/r --get missing --dir="$D"
check "--get with a 404 download saves nothing" '[[ $RC -eq 1 && ! -e "$D/missing.bin" ]]'

base
map_add https://github.com/o/r/archive/refs/tags/v2.0.0.zip 200 files/src.zip
map_add https://github.com/o/r/archive/refs/tags/v2.0.0.tar.gz 200 files/src.zip
mkdir -p "$FAKE_DIR/files"; printf 'ZIPDATA' > "$FAKE_DIR/files/src.zip"
D="$T/dl3"; mkdir -p "$D"
run o/r --source zip --dir="$D"
check "--source zip: name is the tag" '[[ $RC -eq 0 && "$(cat "$D/v2.0.0.zip")" == ZIPDATA ]]'
run o/r --source zip --dir="$D"
check "--source: no overwrite" '[[ $RC -eq 1 ]]'
run o/r --source=tar --dir="$D"
check "--source=tar works and names .tar.gz" '[[ $RC -eq 0 && -e "$D/v2.0.0.tar.gz" ]]'
run o/r --source=zip --dir="$D" --force
check "--source with --force" '[[ $RC -eq 0 ]]'
map_add "https://github.com/o/r/archive/refs/tags/release/..%2F..%2Fx.zip" 200 files/src.zip
map_add "https://github.com/o/r/archive/refs/tags/release/1.0.zip" 200 files/src.zip
run o/r release/1.0 --source zip --dir="$D"
check "--source: a tag with a slash gives a harmless file name" '[[ $RC -eq 0 && -e "$D/release_1.0.zip" ]]'
map_add "https://github.com/o/r/archive/refs/tags/.hidden.zip" 200 files/src.zip
run o/r .hidden --source zip --dir="$D"
check "--source: no leading dot in the file name" '[[ $RC -eq 0 && -e "$D/hidden.zip" ]]'

# ─── --install ───────────────────────────────────────────────────────

base
mkdir -p "$T/pkg"
printf '#!/bin/sh\necho v1\n' > "$T/pkg/r"; chmod +x "$T/pkg/r"
tar czf "$FAKE_DIR/files-r1.tgz" -C "$T/pkg" r
printf '#!/bin/sh\necho v2\n' > "$T/pkg/r"
tar czf "$FAKE_DIR/files-r2.tgz" -C "$T/pkg" r
mk_assets assets.html v2.0.0 r_linux_amd64.deb r_linux_amd64.sha256 r_linux_amd64.tar.gz r_linux_amd64.rpm
map_add https://github.com/o/r/releases/expanded_assets/v2.0.0 200 assets.html
map_add https://github.com/o/r/releases/download/v2.0.0/r_linux_amd64.tar.gz 200 files-r1.tgz
map_add https://github.com/o/r/releases/download/v2.0.0/r_linux_amd64.deb 200 -
D="$T/bindir"; mkdir -p "$D"
run o/r --install --dir="$D"
check "--install: never picks a package or a checksum on its own" '[[ $RC -eq 0 && -x "$D/r" && "$("$D/r")" == v1 ]] && ! grep -q "\.deb" "$FAKE_DIR/calls"'
map_add https://github.com/o/r/releases/download/v2.0.0/r_linux_amd64.tar.gz 200 files-r2.tgz
run o/r --install --dir="$D"
check "--install replaces an installed binary without --force (update)" '[[ $RC -eq 0 && "$("$D/r")" == v2 ]]'
rm -f "$T/home/.local/bin/r" 2>/dev/null
run o/r --install --user
check "--install --user goes to ~/.local/bin, which is created" '[[ $RC -eq 0 && -x "$HOME/.local/bin/r" ]]'
run o/r --install --user --dir="$D"
check "--user with --dir is a usage error (2)" '[[ $RC -eq 2 ]]'
run o/r --user
check "--user without --install is a usage error (2)" '[[ $RC -eq 2 ]]'
run o/r --install --asset=r_linux_amd64.tar.gz --dir="$D"
check "--install --asset=NAME" '[[ $RC -eq 0 ]]'
run o/r --install --asset=r_linux --dir="$D"
check "--install --asset: no substring match" '[[ $RC -eq 1 && "$OUT$ERR" == *"No asset named"* ]]'
mk_assets assets.html v2.0.0 r_linux_amd64.deb r_linux_amd64.sha256 checksums.txt
run o/r --install --dir="$D"
check "--install: only packages and checksums means no suitable asset" '[[ $RC -eq 1 && "$OUT$ERR" == *"No suitable asset"* ]]'
mk_assets assets.html v2.0.0 r_linux_amd64.tar.gz
mkdir -p "$HOME/x"
run o/r --install --dir=~/x
check "--dir=~/x is expanded by gft itself" '[[ $RC -eq 0 && -x "$HOME/x/r" ]]'
run o/r --install --dir "~/x"
check "separate --dir '~/x' is not expanded (1.2 behaviour): refused as a missing folder" '[[ $RC -eq 1 ]]'

# ─── --checksum is strict ────────────────────────────────────────────

mk_dl() {
    base
    mk_assets assets.html v2.0.0 tool.bin "$@"
    map_add https://github.com/o/r/releases/expanded_assets/v2.0.0 200 assets.html
    serve_file tool.bin v2.0.0 CONTENT
    D="$T/ck.$RANDOM"; mkdir -p "$D"
}
SUM=$(printf 'CONTENT' | sha256sum | cut -d' ' -f1)
SUM512=$(printf 'CONTENT' | sha512sum | cut -d' ' -f1)
OTHER=$(printf 'OTHER' | sha256sum | cut -d' ' -f1)

mk_dl
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: no checksum file is a failure" '[[ $RC -ne 0 && "$OUT$ERR" == *"No checksum file"* ]]'
mk_dl checksums.txt
serve_file checksums.txt v2.0.0 "$OTHER  other.bin"
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: file missing from the list is a failure" '[[ $RC -ne 0 && "$OUT$ERR" == *"not in the checksum list"* ]]'
mk_dl checksums.txt
serve_file checksums.txt v2.0.0 "$SUM  tool.bin-extra"
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: 'tool.bin' does not take the line of 'tool.bin-extra'" '[[ $RC -ne 0 ]]'
mk_dl checksums.txt
serve_file checksums.txt v2.0.0 "$SUM  toolXbin"
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: the dot of the name is not a wildcard" '[[ $RC -ne 0 ]]'
mk_dl checksums.txt
serve_file checksums.txt v2.0.0 "$SUM  tool.bin"
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: a match passes, labelled integrity not authenticity" '[[ $RC -eq 0 && "$OUT" == *"Checksum verified"* && "$OUT" == *"integrity, not authenticity"* ]]'
mk_dl checksums.txt
serve_file checksums.txt v2.0.0 "$SUM *tool.bin"
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: the binary-mode star is removed" '[[ $RC -eq 0 ]]'
mk_dl checksums.txt
serve_file checksums.txt v2.0.0 "SHA256 (tool.bin) = $SUM"
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: BSD style lines" '[[ $RC -eq 0 ]]'
mk_dl checksums.txt
serve_file checksums.txt v2.0.0 "$(printf '%s  tool.bin\r\n' "$SUM")"
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: CRLF lists" '[[ $RC -eq 0 ]]'
mk_dl checksums.txt
serve_file checksums.txt v2.0.0 "$OTHER  tool.bin"
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: a mismatch fails and removes the download" '[[ $RC -ne 0 && ! -e "$D/tool.bin" && "$OUT$ERR" == *mismatch* ]]'
mk_dl checksums.txt
serve_file checksums.txt v2.0.0 "nothex  tool.bin"
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: a value that is not a hash is a failure" '[[ $RC -ne 0 ]]'
mk_dl tool.bin.sha256
serve_file tool.bin.sha256 v2.0.0 "$SUM"
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: a per-file .sha256 holding only the hash is accepted" '[[ $RC -eq 0 ]]'
mk_dl tool.bin.sha512
serve_file tool.bin.sha512 v2.0.0 "$SUM512  tool.bin"
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: a .sha512 file is verified with SHA-512 (it used to be preferred and never match)" '[[ $RC -eq 0 ]]'
mk_dl other.bin.sha256
serve_file other.bin.sha256 v2.0.0 "$SUM"
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: the checksum file of another file is never used" '[[ $RC -ne 0 ]]'
mk_dl checksums.txt
map_add https://github.com/o/r/releases/download/v2.0.0/checksums.txt 404 -
run o/r --asset=tool.bin --checksum --dir="$D"
check "checksum: an unreachable checksum file is a failure" '[[ $RC -ne 0 && "$OUT$ERR" == *"Could not download"* ]]'

# without sha256sum and shasum
NOSHA="$T/nosha"; mkdir -p "$NOSHA"
for c in bash sh awk gawk mawk sed grep tr cut head tail mktemp rm mv cp ln chmod mkdir cat date stat wc sort basename dirname find tar readlink id sleep env expr true false printf; do
    p=$(command -v "$c") && [[ "$p" == /* ]] && ln -sf "$p" "$NOSHA/$c"
done
cp "$T/bin/curl" "$NOSHA/curl"; cp "$T/bin/uname" "$NOSHA/uname"
mk_dl checksums.txt
serve_file checksums.txt v2.0.0 "$SUM  tool.bin"
OLDPATH=$PATH
PATH="$NOSHA"
run o/r --asset=tool.bin --checksum --dir="$D"
PATH=$OLDPATH
check "checksum: without sha256sum or shasum it fails instead of skipping" '[[ $RC -ne 0 && "$OUT$ERR" == *"cannot verify"* ]]'

mk_dl checksums.txt
serve_file checksums.txt v2.0.0 "$OTHER  r.bin"
mkdir -p "$T/pkg2"; printf '#!/bin/sh\n' > "$T/pkg2/r"; chmod +x "$T/pkg2/r"
tar czf "$FAKE_DIR/files-r3.tgz" -C "$T/pkg2" r
mk_assets assets.html v2.0.0 r_linux_amd64.tar.gz checksums.txt
map_add https://github.com/o/r/releases/download/v2.0.0/r_linux_amd64.tar.gz 200 files-r3.tgz
rm -f "$D/r"
run o/r --install --checksum --dir="$D"
check "--install --checksum: a failed check installs nothing" '[[ $RC -ne 0 && ! -e "$D/r" ]]'

# ─── compare, -q, protection of tags ─────────────────────────────────

base
mk_releases releases.html "astro%407.0.0|A7|2026-03-02" "astro%406.0.0|A6|2026-02-02" "astro%405.0.0|A5|2026-01-02"
map_add https://github.com/o/r/releases 200 releases.html
run -- o/r 'astro@5.0.0..astro@7.0.0'
check "compare: tags with an @ (percent-encoded on the page) are found" \
    '[[ "$OUT" == *astro@7.0.0* && "$OUT" == *astro@6.0.0* && "$OUT" == *astro@5.0.0* && "$OUT" != *"Could not find"* ]]'
run -- o/r 'astro%405.0.0..astro%407.0.0'
check "compare: percent-encoded arguments work as well" '[[ "$OUT" != *"Could not find"* ]]'
fresh
map_add https://github.com/o/r 200 -
map_add https://github.com/o/r/releases/latest 200 - https://github.com/o/r/releases
map_add https://github.com/o/r/releases 200 -
run -q -- o/r
check "-q without any release: 'No release found' on stderr, exit 1, nothing on stdout" '[[ $RC -eq 1 && -z "$OUT" && "$ERR" == *"No release found"* ]]'
run -q -- o/r v1.2.3
check "-q with an explicit tag still prints it" '[[ $RC -eq 0 && "$OUT" == v1.2.3 ]]'

base
mk_assets assets.html v2.0.0 a.bin
FAKEHOME="$T/guard"; mkdir -p "$FAKEHOME/.config/gft"; echo 9.9.9 > "$FAKEHOME/.config/gft/VERSION"; cp "$GFT" "$FAKEHOME/.config/gft/gft"
for t in --upgrade update delete uninstall stash --json --get --install; do
    HOME="$FAKEHOME" run -q -- o/r "$t"
    check "after --, the tag '$t' is a tag" '[[ "$OUT" == "'"$t"'" && $RC -eq 0 && -f "$FAKEHOME/.config/gft/gft" && "$(cat "$FAKEHOME/.config/gft/VERSION")" == 9.9.9 ]]'
done
HOME="$FAKEHOME" run -q -- update/x
check "-- update/x is a repository lookup, not an update" '[[ -f "$FAKEHOME/.config/gft/gft" ]]'

# ─── 1.2.2 stays the same for the old options ────────────────────────

OLD="$T/gft-1.2.2"
if git -C "$ROOT" show 1.2.2:gft > "$OLD" 2>/dev/null; then
    base
    mk_releases releases.html "v2.0.0|Two|2026-03-02" "v1.0.0|One|2025-12-24"
    map_add https://github.com/o/r/releases 200 releases.html
    mk_assets assets.html v2.0.0 tool_linux_amd64.tar.gz tool_darwin_arm64.tar.gz checksums.txt
    map_add https://github.com/o/r/releases/expanded_assets/v2.0.0 200 assets.html
    map_add https://github.com/o/r/releases/tag/v2.0.0 200 -
    for args in "o/r" "o/r -q" "o/r v1.0.0" "o/r --assets" "o/r --detect" "o/r --releases" "o/r v1.0.0..v2.0.0" "o/r --pre -q" "o/r --no-color --assets"; do
        # shellcheck disable=SC2086
        a=$(GFT_CACHE_DIR="$T/c.old" bash "$OLD" $args < /dev/null 2>&1)
        # shellcheck disable=SC2086
        b=$(GFT_CACHE_DIR="$T/c.new" bash "$GFT" $args < /dev/null 2>&1)
        rm -f "$T"/c.old/* "$T"/c.new/* 2>/dev/null
        RC=0 OUT="$a" ERR="$b"
        check "1.2.2 and now print the same for 'gft $args'" '[[ "$a" == "$b" ]]'
    done
else
    echo "SKIP  no tag 1.2.2 here: the comparison with the previous release is not run"
fi

echo
echo "$pass passed, $fail failed"
if [[ "${GFT_TESTS_CLEAN:-}" == 1 ]]; then
    rm -r -- "$T"
else
    echo "work folder: $T"
fi
[[ $fail -eq 0 ]]
