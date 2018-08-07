#!/bin/sh

_err() {
    echo >&2 "error: $*"
}

INFOPATH=$(realpath "$1")
if [ ! -f "$INFOPATH" ]; then
    _err "no such file: $INFOPATH"
    exit 1
fi

BASEPATH="$(dirname "$INFOPATH")"
UNKNOWNBASE="$BASEPATH/.unknown"

_cksum() {
    shasum "$1" | sed -nE 's/^([a-f0-9]{40})  .*/shasum:\1/p'
}

_rmdupe() {
    keeppath="$1"
    dupepath="$2"
    if [ ! -f "$keeppath" ] ||
       [ ! -f "$dupepath" ] ||
       [ "$keeppath" = "$dupepath" ]; then
        return 1
    fi
    keepsum=$(_cksum "$keeppath")
    dupesum=$(_cksum "$dupepath")
    if [ -z "$keepsum" ] || [ "$keepsum" != "$dupesum" ]; then
        return 1
    fi
    rm "$dupepath"
}

_try_rmdupe() {
    keeppath="$1"
    dupepath="$2"
    if ! _rmdupe "$keeppath" "$dupepath"; then
        _err "cannot dedupe file: $dupepath"
        return 1
    fi
}

_hide_unknown() {
    echo "# Hide unknown files in $UNKNOWNBASE"

    mkdir -p "$UNKNOWNBASE"
    sed -nE 's/^unknown: //p' "$INFOPATH" |
    while read -r unknownsource; do
        if [ -z "$unknownsource" ] ||
           [ "$unknownsource" = "$UNKNOWNBASE" ] ||
           [ "$unknownsource" = "$INFOPATH" ] ||
           [ "$(dirname "$unknownsource")" = "$UNKNOWNBASE" ]; then
            continue
        fi
        unknowntarget="$UNKNOWNBASE/$(basename "$unknownsource")"
        if [ -f "$unknowntarget" ]; then
            _try_rmdupe "$unknowntarget" "$unknownsource"
            continue
        fi
        mv -nv "$unknownsource" "$UNKNOWNBASE/"
    done
}

_ext() {
    printf '%s' "$1" | sed -nE 's/.*[^\/]+(\.[^.\/]+)$/\1/p'
}

_arg() {
    pos="$1"
    text="$2"
    printf '%s' "$text" | sed -nE "s/^(([^:]+)(: |\$)){${pos}}(\$|[^:]+).*/\\4/p"
}

_try_move() {
    source="$1"
    target="$2"
    if [ ! -f "$source" ]; then
        _err "source file missing: $source"
        return 1
    fi
    targetdir="$(dirname "$target")"
    if ! mkdir -p "$targetdir"; then
        return 1
    fi
    if [ -f "$target" ]; then
        if _try_rmdupe "$target" "$source"; then
            return 0
        fi
        return 1
    fi
    mv -nv "$source" "$target"
}

_collect_found() {
    echo "# Collect found files in $BASEPATH"

    grep -E '^rename(: [^:]+){2}$' "$INFOPATH" |
    while read -r found; do
        sourcepath="$(_arg 1 "$found")"
        targetpath="$(_arg 2 "$found")"
        sourcedir="$(dirname "$sourcepath")"
        targetdir="$(dirname "$targetpath")"
        dirext="$(_ext "$sourcedir")"
        if [ "$dirext" = ".zip" ] && [ -f "$sourcedir" ]; then
            _err "zipped roms are not yet supported: $sourcepath"
        else
            _try_move "$sourcepath" "$targetpath"
        fi
    done
}

_main() {
    _hide_unknown
    _collect_found
}
_main
