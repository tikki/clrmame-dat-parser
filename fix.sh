#!/bin/sh

# config

## binary paths

SHASUM_BIN=shasum
SHASUM_OPTS=
TRRNTZIP_BIN=trrntzip
TRRNTZIP_OPTS="-L -g"
UNZIP_BIN=unzip
UNZIP_OPTS=-qq
ZIP_BIN=zip
ZIP_OPTS=-q
ZIPINFO_BIN=unzip
ZIPINFO_OPTS=-Z
ZIPNOTE_BIN=zipnote
ZIPNOTE_OPTS=

## runtime config

DRYRUN= # set to something like /bin/echo to activate dryrun mode
QUIET=


# basic utility functions

## print funcs

_err() {
    if [ "$QUIET" != "1" ]; then
        echo >&2 "$(basename "$0"): error: $*"
    fi
}

_print() {
    if [ "$QUIET" != "1" ]; then
        echo "$*"
    fi
}


## string funcs

_slen() {
    printf '%s' "$1" | wc -m | sed 's/^ *//'
}

_shead() {
    # printf '%s' "$1" | head -c "$2" # breaks for multibyte chars
    printf '%s' "$1" | cut -c "-$2"
}

_startswith() {
    # printf '%s' "$1" | grep -q "^$2"
    text="$1"
    prefix="$2"
    [ "$prefix" = "$(_shead "$text" "$(_slen "$prefix")")" ]
}

_withoutprefix() {
    text="$1"
    prefix="$2"
    plen="$(_slen "$prefix")"
    if [ "$prefix" = "$(_shead "$text" "$plen")" ]; then
        printf '%s' "$text" | cut -c "$((plen + 1))-"
    fi
}


## file/path funcs

_cksum() {
    "$SHASUM_BIN" $SHASUM_OPTS "$1" |
        sed -nE 's/^([a-f0-9]{40})  .*/shasum:\1/p'
}

_pathext() {
    printf '%s' "$1" | sed -nE 's#.*[^/](\.[^./]+)$#\1#p'
}

_move_file() {
    # Safely move a file.
    source="$1"
    target="$2"
    if [ ! -f "$source" ]; then
        _err "move: source file is missing: $source"
        return 1
    fi
    targetdir="$(dirname "$target")"
    if ! $DRYRUN mkdir -p "$targetdir"; then
        _err "move: could not create target dir: $targetdir"
        return 1
    fi
    if [ -f "$target" ]; then
        if _rmdupe "$target" "$source"; then
            return 0
        fi
        return 1
    fi
    $DRYRUN mv -n "$source" "$target"
}

_rmdupe() {
    keeppath="$1"
    dupepath="$2"
    if [ ! -f "$keeppath" ]; then
        _err "rmdupe: no such file: $keeppath"
        return 1
    fi
    if [ ! -f "$dupepath" ]; then
        _err "rmdupe: no such file: $dupepath"
        return 1
    fi
    if [ "$keeppath" = "$dupepath" ]; then
        return 0
    fi
    keepsum=$(_cksum "$keeppath")
    dupesum=$(_cksum "$dupepath")
    if [ -z "$keepsum" ] || [ "$keepsum" != "$dupesum" ]; then
        _err "rmdupe: content differs: $dupepath"
        return 1
    fi
    if ! $DRYRUN rm "$dupepath"; then
        _err "rmdupe: could not delete file: $dupepath"
        return 1
    fi
    $DRYRUN rmdir "$(dirname "$dupepath")" 2>/dev/null
    return 0
}


## zip helpers

_is_zipfile() {
    # Check if the given path is a zip file.
    path="$1"
    [ ".zip" = "$(_pathext "$path")" ] && [ -f "$path" ] &&
        "$ZIPINFO_BIN" $ZIPINFO_OPTS -h "$path" >/dev/null 2>&1
}

_is_in_zipfile() {
    # Check if the given key/in-archive-path exists in the zip file.
    zipfile="$1"
    key="$2"
    "$ZIPINFO_BIN" $ZIPINFO_OPTS "$zipfile" "$key" >/dev/null 2>&1
}

_find_zipfile() {
    # Find (and print) the zip file from the given path.
    path="$1"
    while [ -n "$path" ] && [ "$path" != "/" ] && [ "$path" != "." ]; do
        if _is_zipfile "$path"; then
            printf '%s' "$path"
            return 0
        fi
        if ! path="$(dirname "$path")"; then
            return 1
        fi
    done
    return 1
}

_extract_from_zipfile() {
    # Extract a file to the given location.
    zipfile="$1"
    key="$2"
    target="$3"
    if [ -e "$target" ]; then
        _err "extract from zip: target already exists: $target"
        return 1
    fi
    if ! $DRYRUN mkdir -p "$(dirname "$target")" || ! $DRYRUN touch "$target"; then
        _err "extract from zip: cannot create target: $target"
        return 1
    fi
    if [ -n "$DRYRUN" ]; then
        $DRYRUN "$UNZIP_BIN" $UNZIP_OPTS -p "$zipfile" "$key" \> "$target"
    else
        "$UNZIP_BIN" $UNZIP_OPTS -p "$zipfile" "$key" > "$target"
    fi
}

_rename_in_zipfile() {
    # Rename a file inside a zip file.
    zipfile="$1"
    source="$2"
    target="$3"
    if [ -n "$DRYRUN" ]; then
        $DRYRUN printf '@ %s\n@=%s\n' "$source" "$target" '|'
            $DRYRUN "$ZIPNOTE_BIN" $ZIPNOTE_OPTS -w "$zipfile"
    else
        printf '@ %s\n@=%s\n' "$source" "$target" |
            "$ZIPNOTE_BIN" $ZIPNOTE_OPTS -w "$zipfile"
    fi
}

_remove_from_zipfile() {
    # Remove a file from a zip file, deleting the zip file if it becomes empty.
    zipfile="$1"
    key="$2"
    if [ "$(printf '%s\n' "$key")" = "$("$ZIPINFO_BIN" $ZIPINFO_OPTS -1 "$zipfile")" ]; then
        $DRYRUN rm "$zipfile"
    else
        $DRYRUN "$ZIP_BIN" $ZIP_OPTS -d "$zipfile" "$key"
    fi
}

_move_from_zipfile() {
    # Extract and remove a file from a zip file.
    zipfile="$1"
    key="$2"
    target="$3"
    if ! _extract_from_zipfile "$zipfile" "$key" "$target"; then
        _err "move from zip: could not extract from zip: $zipfile: $key: $target"
        return 1
    fi
    if ! _remove_from_zipfile "$zipfile" "$key"; then
        _err "move from zip: could not remove from zip: $zipfile: $key"
        rm -f "$target"
        return 1
    fi
}

_move_into_zipfile() {
    # Move a file into a zip file with the given target name/key.
    zipfile="$1"
    source="$2"
    key="$3"
    tmpbase="$(dirname "$zipfile")"
    if [ -n "$DRYRUN" ]; then
        tmpdir=/tmp
    else
        tmpdir="$(mktemp -qd "$tmpbase/.fix.$(basename "$zipfile").XXXXXX")"
    fi
    if [ -z "$tmpdir" ]; then
        _err "move into zip: could not create temp dir in: $tmpbase"
        return 1
    fi
    keydir="$tmpdir/$(dirname "$key")"
    if ! $DRYRUN mkdir -p "$keydir"; then
        _err "move into zip: could not create key struct in: $keydir"
        return 1
    fi
    if ! $DRYRUN mv -n "$source" "$keydir/$key"; then
        _err "move into zip: could not move file: $source"
        return 1
    fi
    $DRYRUN pushd "$tmpdir"
    $DRYRUN "$ZIP_BIN" $ZIP_OPTS -m -T -MM -nw -0 "$zipfile" "$key"
    $DRYRUN popd
    if [ -n "$tmpdir" ]; then
        $DRYRUN rmdir -p "$tmpdir"
    fi
}

_move_across_zipfiles() {
    # todo: test & fix
    source="$1"
    skey="$2"
    target="$3"
    tkey="$4"
    if [ "$source" = "$target" ]; then
        _rename_in_zipfile "$source" "$skey" "$tkey"
        return $?
    fi
    if [ "$skey" = "$tkey" ]; then
        $DRYRUN "$ZIP_BIN" $ZIP_OPTS "$source" "$skey" --copy --out "$target"
        return $?
    fi
    tmpbase="$(dirname "$target")"
    tmpfile="$(mktemp -qu "$tmpbase/.fix.$(basename "$target").XXXXXX")"
    if [ -z "$tmpfile" ]; then
        _err "move across zip: could not create temp file"
        return 1
    fi
    if ! _extract_from_zipfile "$source" "$skey" "$tmpfile"; then
        _err "move across zip: could not extract file: $source: $skey"
        return 1
    fi
    _move_into_zipfile "$target" "$tmpfile" "$tkey"
}


# main

_mmove() {
    # Transparently move a file across the file system and zip files.
    source="$1"
    target="$2"
    sarchive="$(_find_zipfile "$source")"
    tarchive="$(_find_zipfile "$target")"
    if [ -z "$sarchive" ]; then
        # {file} -> ...
        if [ -z "$tarchive" ]; then
            # ... -> {file}
            _move_file "$source" "$target"
        else
            # ... -> {archive}
            key="$(_withoutprefix "$target" "$tarchive/")"
            _move_into_zipfile "$tarchive" "$source" "$key"
        fi
    else
        # {archive} -> ...
        if [ -z "$tarchive" ]; then
            # ... -> {file}
            key="$(_withoutprefix "$source" "$sarchive/")"
            _move_from_zipfile "$sarchive" "$key" "$target"
        else
            # ... -> {archive}
            skey="$(_withoutprefix "$source" "$sarchive/")"
            tkey="$(_withoutprefix "$target" "$tarchive/")"
            _move_across_zipfiles "$sarchive" "$skey" "$tarchive" "$tkey"
        fi
    fi
}

_trrntzip() {
    zipfile="$1"
    $DRYRUN "$TRRNTZIP_BIN" $TRRNTZIP_OPTS "$zipfile"
}

_hide_unknown() {
    infopath="$1"
    basedir="$(dirname "$infopath")"
    now=$(date '+%Y%m%d-%H%M%S')
    unknownbase="${basedir}/.unknown"
    unknowndir="${unknownbase}/${now}"
    unknowndir_made=0

    _print "# Hide unknown files in $unknowndir"
    sed -nE 's/^unknown: //p' "$infopath" |
    while read -r unknownfile; do
        if [ -z "$unknownfile" ] ||
           _startswith "$unknownfile" "$unknownbase" ||
           [ "$unknownfile" = "$infopath" ] ||
           [ "$(dirname "$unknownfile")" = "$unknowndir" ]; then
            continue
        fi
        unknowntarget="$unknowndir/$(basename "$unknownfile")"
        # todo: keep dir structure
        if [ -f "$unknowntarget" ]; then
            _rmdupe "$unknowntarget" "$unknownfile"
            continue
        fi
        if [ $unknowndir_made = 0 ]; then
            $DRYRUN mkdir -p "$unknowndir"
            unknowndir_made=1
        fi
        $DRYRUN mv -n "$unknownfile" "$unknowndir/"
    done
}

_arg() {
    # Return a positional argument from a colon-separated list, e.g.:
    # "foo: bar: boo" -> 0: "foo", 1: "bar", 2: "boo"
    pos="$1"
    text="$2"
    printf '%s' "$text" | sed -nE "s/^(([^:]+)(: |\$)){${pos}}(\$|[^:]+).*/\\4/p"
}

_collect_found() {
    infopath="$1"
    basedir="$(dirname "$infopath")"
    _print "# Collect found files in $basedir"

    grep -E '^rename(: [^:]+){2}$' "$infopath" |
    while read -r found; do
        source="$(_arg 1 "$found")"
        target="$(_arg 2 "$found")"
        _mmove "$source" "$target"
    done
}

_main() {
    infopath=$(realpath "$1")
    if [ ! -f "$infopath" ]; then
        _err "fix: no such file: $infopath"
        exit 1
    fi
    _hide_unknown "$infopath"
    _collect_found "$infopath"
}
_main "$@"
