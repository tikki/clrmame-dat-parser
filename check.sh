#!/bin/sh

_err() {
    echo >&2 "$(basename "$0"): error: $*"
}

DATPATH=$1
if [ ! -f "$DATPATH" ]; then
    _err "no such file: $DATPATH"
    exit 1
fi

BASEPATH="$(dirname "$(dirname "$DATPATH")")"
DATNAME="$(basename "$DATPATH")"
DATBASENAME=$(printf '%s' "$DATNAME" | sed -nE 's/([^\(]+) .*/\1/p')
DATDATE=$(printf '%s' "$DATNAME" | sed -nE 's/.* \(([-0-9]+)\).*/\1/p')
ROMSPATH="$BASEPATH/$DATBASENAME"
INFOPATH="$ROMSPATH/.nointro-$DATDATE"

if [ ! -d "$ROMSPATH" ]; then
    _err "missing roms directory: $ROMSPATH"
    exit 1
fi

PYTHONPATH=. bin/check "$DATPATH" "$ROMSPATH" |
    grep -vE '^unknown: .+/\.(nointro-[-0-9]+|unknown/[-0-9]+/.+)$' |
    tee "$INFOPATH"

echo "info: written to $INFOPATH"
