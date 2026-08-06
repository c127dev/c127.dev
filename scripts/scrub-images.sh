#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Johan Alvarado
#
#   scripts/scrub-images.sh                  strip every image under static/images
#   scripts/scrub-images.sh check            report only, exit 1 if anything is dirty
#   scripts/scrub-images.sh [check] PATH...  limit to those files or directories
#
# Strips metadata only. Redact serials/MACs in the pixels before adding a photo.

set -euo pipefail

EXIF_IMAGE="${EXIF_IMAGE:-docker.io/library/alpine:3.21}"

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

MOUNT="$ROOT:/app:z"

log() { printf '\033[0;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33mwarn:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[0;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if command -v exiftool >/dev/null; then
    exif() { exiftool "$@"; }
elif command -v podman >/dev/null; then
    warn "no host exiftool; falling back to a container (slower)"
    exif() {
        podman run --rm -v "$MOUNT" -w /app "$EXIF_IMAGE" \
            sh -c 'apk add --no-cache exiftool >/dev/null 2>&1 && exec exiftool "$@"' exif "$@"
    }
else
    die "need exiftool (perl-image-exiftool) or podman"
fi

EXTS=(jpg jpeg png gif webp avif tif tiff heic)

cd "$ROOT"

tags() {
    exif -a -G1 -s -q -q -- "$1" |
        sed -n 's/^\[\([^]]*\)\][[:space:]]*\([^[:space:]]*\).*/\1:\2/p' |
        grep -vE '^(System|ExifTool|Composite):' |
        sort -u
}

collect() {
    local -n out=$1
    shift

    local roots=("$@")
    [[ ${#roots[@]} -eq 0 ]] && roots=("static/images")

    local root
    for root in "${roots[@]}"; do
        [[ -e "$root" ]] || die "no such path: $root"
    done

    local args=() ext
    for ext in "${EXTS[@]}"; do
        args+=(-iname "*.${ext}" -o)
    done
    unset 'args[${#args[@]}-1]'

    mapfile -d '' -t out < <(find "${roots[@]}" -type f \( "${args[@]}" \) -print0 | sort -z)

    local svgs
    svgs="$(find "${roots[@]}" -type f -iname '*.svg' | wc -l)"
    [[ "$svgs" -gt 0 ]] &&
        warn "$svgs SVG file(s) skipped - exiftool cannot scrub XML; check them by hand for editor metadata and remote references"

    return 0
}

run() {
    local write=$1
    shift

    local files=()
    collect files "$@"

    if [[ ${#files[@]} -eq 0 ]]; then
        log "no images found"
        return 0
    fi

    log "scanning ${#files[@]} image(s)"

    local tmp
    # Relative, inside the repo: the container sees it under /app. An absolute
    # host path makes every file report clean.
    tmp="$(mktemp -d .scrub.XXXXXX)"
    trap "rm -rf '$ROOT/$tmp'" EXIT

    local dirty=0 file copy removed
    for file in "${files[@]}"; do
        copy="$tmp/img"
        cp -- "$file" "$copy"
        # A failed strip leaves the copy unchanged, which reads as clean.
        exif -all= -overwrite_original -q -q -- "$copy" >/dev/null ||
            die "exiftool failed on $file"

        if cmp -s -- "$file" "$copy"; then
            rm -f -- "$copy"
            continue
        fi

        dirty=$((dirty + 1))

        removed="$(comm -23 <(tags "$file") <(tags "$copy") |
            cut -d: -f1 | sort -u | paste -sd, - | sed 's/,/, /g')"
        [[ -z "$removed" ]] && removed="(padding only)"

        printf '    %-46s %s\n' "$file" "$removed"

        if [[ "$write" == "1" ]]; then
            cat -- "$copy" >"$file"
        fi
        rm -f -- "$copy"
    done

    if [[ "$dirty" -eq 0 ]]; then
        log "clean - nothing to strip"
        return 0
    fi

    if [[ "$write" == "1" ]]; then
        log "stripped $dirty file(s)"
        return 0
    fi

    log "$dirty file(s) still carry metadata - run scripts/scrub-images.sh to strip"
    return 1
}

cmd="${1:-scrub}"
[[ $# -gt 0 ]] && shift

case "$cmd" in
    check)
        run 0 "$@"
        ;;
    scrub)
        run 1 "$@"
        ;;
    -h|--help|help)
        awk 'NR>4 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
        ;;
    -*)
        die "unknown option: $cmd (try: check, scrub, help)"
        ;;
    *)
        run 1 "$cmd" "$@"
        ;;
esac
