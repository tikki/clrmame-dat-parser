#!/bin/sh

DATPATH=$1
if [ ! -f "$DATPATH" ]; then
    echo >&2 "no such file: $DATPATH"
    exit 1
fi

BASEPATH="$(dirname "$(dirname "$DATPATH")")"
DATNAME="$(basename "$DATPATH")"
DATBASENAME=$(printf '%s' "$DATNAME" | sed -nE 's/([^\(]+) .*/\1/p')
DATDATE=$(printf '%s' "$DATNAME" | sed -nE 's/.* \(([-0-9]+)\).*/\1/p')
ROMSPATH="$BASEPATH/$DATBASENAME"
INFOPATH="$ROMSPATH/.nointro-$DATDATE"

if [ ! -d "$ROMSPATH" ]; then
    echo >&2 "error: missing roms directory: $ROMSPATH"
    exit 1
fi

PYTHONPATH=. bin/check "$DATPATH" "$ROMSPATH" | tee "$INFOPATH"

echo "info: written to $INFOPATH"
