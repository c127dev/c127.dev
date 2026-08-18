#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Johan Alvarado
#
#   ./build.sh              build to public/, zip to dist/
#   ./build.sh serve        dev server with live reload on :1111
#   ./build.sh check        validate links, write nothing
#   ./build.sh clean        remove public/ and dist/
#   ./build.sh deploy       build for SITE_URL, publish to Cloudflare Workers
#
#   BASE_URL=https://example.com ./build.sh   absolute URLs in sitemap/feed
#   MINIFY=0 ./build.sh                       skip CSS/JS minification

set -euo pipefail

ZOLA_IMAGE="${ZOLA_IMAGE:-ghcr.io/getzola/zola:v0.21.0}"
ZIP_IMAGE="${ZIP_IMAGE:-docker.io/library/alpine:3.21}"
MINIFY_IMAGE="${MINIFY_IMAGE:-docker.io/tdewolff/minify:v2.24.14}"
WRANGLER_IMAGE="${WRANGLER_IMAGE:-docker.io/library/node:22-alpine}"
WRANGLER_VERSION="${WRANGLER_VERSION:-4.123.0}"
CONTAINER_NAME="zola-dev"
PORT="${PORT:-1111}"
LIVERELOAD_PORT="${LIVERELOAD_PORT:-1024}"

SITE_URL="${SITE_URL:-https://www.c127.dev}"

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DIST="$ROOT/dist"
NAME="$(basename "$ROOT")"

MOUNT="$ROOT:/app:z"

log() { printf '\033[0;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[0;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v podman >/dev/null || die "podman not found"

zola() { podman run --rm -v "$MOUNT" -w /app "$ZOLA_IMAGE" "$@"; }

load_env() {
    [[ -f "$ROOT/.env" ]] || return 0

    local mode
    mode="$(stat -c '%a' "$ROOT/.env")"
    [[ "$mode" == "600" ]] || log "warning: .env is mode $mode, want 600"

    set -a
    # shellcheck source=/dev/null
    . "$ROOT/.env"
    set +a
}

WRANGLER_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/c127.dev/wrangler"

wrangler() {
    mkdir -p "$WRANGLER_CACHE/npm" "$WRANGLER_CACHE/state"

    local -a run=(
        --rm -i
        -v "$MOUNT"
        -w /app
        -v "$WRANGLER_CACHE/npm:/root/.npm:z"
        -v "$WRANGLER_CACHE/state:/root/.config:z"
    )

    [[ -t 0 ]] && run+=(-t)

    local var
    for var in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID; do
        [[ -n "${!var:-}" ]] && run+=(-e "$var")
    done

    podman run "${run[@]}" "$WRANGLER_IMAGE" \
        npx --yes "wrangler@$WRANGLER_VERSION" "$@"
}

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

cmd_deploy() {
    [[ -f "$ROOT/wrangler.jsonc" ]] || die "wrangler.jsonc not found"

    load_env
    [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]] || die \
        "CLOUDFLARE_API_TOKEN is not set - put it in .env (mode 600) or export it"

    export BASE_URL="${BASE_URL:-$SITE_URL}"
    cmd_build

    log "deploying $BASE_URL"
    wrangler deploy
}

case "${1:-build}" in
    build)  cmd_build ;;
    serve)  cmd_serve ;;
    check)  cmd_check ;;
    clean)  cmd_clean ;;
    deploy) cmd_deploy ;;
    -h|--help|help)
        awk 'NR>4 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
        ;;
    *) die "unknown command: $1 (try: build, serve, check, clean, deploy)" ;;
esac
