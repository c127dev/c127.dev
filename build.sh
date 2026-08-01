#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Johan Alvarado
#
#   ./build.sh              build to public/, zip to dist/
#   ./build.sh serve        dev server with live reload on :1111
#   ./build.sh check        validate links, write nothing
#   ./build.sh clean        remove public/ and dist/
#
#   BASE_URL=https://example.com ./build.sh   absolute URLs in sitemap/feed
#   MINIFY=0 ./build.sh                       skip CSS/JS minification

set -euo pipefail

ZOLA_IMAGE="${ZOLA_IMAGE:-ghcr.io/getzola/zola:v0.21.0}"
ZIP_IMAGE="${ZIP_IMAGE:-docker.io/library/alpine:3.21}"
MINIFY_IMAGE="${MINIFY_IMAGE:-docker.io/tdewolff/minify:v2.24.14}"
CONTAINER_NAME="zola-dev"
PORT="${PORT:-1111}"
LIVERELOAD_PORT="${LIVERELOAD_PORT:-1024}"

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DIST="$ROOT/dist"
NAME="$(basename "$ROOT")"

MOUNT="$ROOT:/app:z"

log() { printf '\033[0;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[0;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v podman >/dev/null || die "podman not found"

zola() { podman run --rm -v "$MOUNT" -w /app "$ZOLA_IMAGE" "$@"; }

# Not markdown.lazy_async_image: in Zola 0.21 it blanks every heading id.
lazy_img() {
    local count
    count="$(find "$ROOT/public" -type f -name '*.html' \
        -exec grep -l '<img ' {} + | wc -l)"

    [[ "$count" -eq 0 ]] && return 0

    log "deferring images in $count file(s)"
    find "$ROOT/public" -type f -name '*.html' -exec python3 - {} + <<'PY'
import re, sys

IMG = re.compile(r'<img\b(?![^>]*\bloading=)')

for path in sys.argv[1:]:
    with open(path, encoding='utf-8') as fh:
        html = fh.read()

    seen = False
    def sub(m):
        global seen
        if not seen:
            seen = True
            return m.group(0)
        return '<img loading=lazy decoding=async'

    out = IMG.sub(sub, html)
    if out != html:
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(out)
PY
}

minify() {
    [[ "${MINIFY:-1}" == "1" ]] || { log "minify disabled (MINIFY=0)"; return 0; }

    local files=()
    # One path per arg: minify v2.24 drops positional inputs under --match.
    mapfile -t files < <(cd "$ROOT/public" && find . -type f \
        \( -name '*.css' -o -name '*.js' \) ! -name '*.min.js' \
        -printf '/app/public/%P\n')

    [[ "${#files[@]}" -eq 0 ]] && return 0

    log "minifying ${#files[@]} css/js file(s)"
    podman run --rm -v "$MOUNT" "$MINIFY_IMAGE" --inplace "${files[@]}"
}

cmd_build() {
    rm -rf "$ROOT/public"

    if [[ -n "${BASE_URL:-}" ]]; then
        log "building for $BASE_URL"
        zola build --base-url "$BASE_URL"
    else
        log "building (base_url from config.toml)"
        zola build
    fi

    lazy_img

    minify

    mkdir -p "$DIST"
    local stamp archive
    stamp="$(date +%Y%m%d-%H%M%S)"
    archive="$DIST/${NAME}-${stamp}.zip"

    log "packing $(basename "$archive")"
    if command -v zip >/dev/null; then
        (cd "$ROOT/public" && zip -qr -X "$archive" .)
    else
        podman run --rm -v "$MOUNT" -w /app/public "$ZIP_IMAGE" \
            sh -c "apk add --no-cache zip >/dev/null && zip -qr -X /app/dist/$(basename "$archive") ."
    fi

    ln -sfn "$(basename "$archive")" "$DIST/${NAME}-latest.zip"

    log "$(du -h "$archive" | cut -f1)  $archive"
    log "sha256 $(sha256sum "$archive" | cut -d' ' -f1)"
}

cmd_serve() {
    podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    log "serving on http://localhost:$PORT  (ctrl-c to stop)"
    podman run --rm -it --name "$CONTAINER_NAME" \
        -v "$MOUNT" -w /app \
        -p "$PORT:1111" -p "$LIVERELOAD_PORT:1024" \
        "$ZOLA_IMAGE" serve \
        --interface 0.0.0.0 --port 1111 --base-url /
}

cmd_check() {
    log "checking"
    zola check
}

cmd_clean() {
    log "removing public/ and dist/"
    rm -rf "$ROOT/public" "$DIST"
}

case "${1:-build}" in
    build)  cmd_build ;;
    serve)  cmd_serve ;;
    check)  cmd_check ;;
    clean)  cmd_clean ;;
    -h|--help|help)
        awk 'NR>4 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
        ;;
    *) die "unknown command: $1 (try: build, serve, check, clean)" ;;
esac
