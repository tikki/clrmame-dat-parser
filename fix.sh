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

## runtime config

DRYRUN=  # set to `_debug` to activate dryrun mode
LOGLEVEL=2 # 0-3; 0: quiet, 1: error only, 2: info, 3: debug

## globals

RUNID=$(date '+%Y%m%d-%H%M%S')
SEARCHDIR=.
TARGETDIR=.
FIXDIR=.fix


# basic utility functions

## print funcs

_err() {
    if [ "$LOGLEVEL" -gt 0 ]; then
        echo >&2 "$(basename "$0"): error: $*"
    fi
}

_print() {
    if [ "$LOGLEVEL" -gt 1 ]; then
        echo "$*"
    fi
}

_debug() {
    if [ "$LOGLEVEL" -gt 2 ]; then
        /bin/echo >&2 "DEBUG: $*"
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

_psuffix() {
    printf '%s' "$1" | sed -nE 's#.*[^/](\.[^./]+)$#\1#p'
}

_move_file() {
    # Safely move a file.
    source="$1"
    target="$2"
    _debug "move: $source -> $target"
    if [ "$source" = "$target" ]; then
        _debug "move: nothing to do: $source"
        return 0
    fi
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
    if ! $DRYRUN mv -n "$source" "$target"; then
        _err "move: could not move file: $source -> $target"
        return 1
    fi
    sourcedir="$(dirname "$source")"
    _debug "move: deleting dir: $sourcedir"
    $DRYRUN rmdir "$sourcedir" 2>/dev/null
    return 0
}

_rmdupe() {
    keeppath="$1"
    dupepath="$2"
    _debug "rmdupe: $keeppath -> $dupepath"
    if [ ! -f "$keeppath" ]; then
        _err "rmdupe: no such file: $keeppath"
        return 1
    fi
    if [ ! -f "$dupepath" ]; then
        _err "rmdupe: no such file: $dupepath"
        return 1
    fi
    if [ "$keeppath" = "$dupepath" ]; then
        _debug "rmdupe: original = dupe: $keeppath"
        return 0
    fi
    keepsum=$(_cksum "$keeppath")
    dupesum=$(_cksum "$dupepath")
    if [ -z "$keepsum" ] || [ "$keepsum" != "$dupesum" ]; then
        _debug "rmdupe: content differs: $keepsum != $dupepath"
        return 1
    fi
    _debug "rmdupe: deleting file: $dupepath"
    if ! $DRYRUN rm "$dupepath"; then
        _err "rmdupe: could not delete file: $dupepath"
        return 1
    fi
    dupedir="$(dirname "$dupepath")"
    _debug "rmdupe: deleting dir: $dupedir"
    $DRYRUN rmdir "$dupedir" 2>/dev/null
    return 0
}


## zip helpers

_is_unpacked_zipfile() {
    # Check if the given path looks like it points to a unpacked zip file.
    [ ".zip" = "$(_psuffix "$1")" ] && [ -d "$1" ]
}

_is_zipfile() {
    # Check if the given path is a zip file.
    [ -n "$1" ] && [ -f "$1" ] &&
        "$ZIPINFO_BIN" $ZIPINFO_OPTS -h "$1" >/dev/null 2>&1
}

_is_alone_in_zipfile() {
    # Check if the given key is the only file in the zip file.
    zipfile="$1"
    key="$2"
    [ "$(printf '%s\n' "$key")" = "$("$ZIPINFO_BIN" $ZIPINFO_OPTS -1 "$zipfile")" ]
}

_guess_archive() {
    # Find (and print) a possible archive for the given path.
    fullpath="$1"
    check="$2"
    if [ -z "$check" ]; then
        check="_is_zipfile"
    fi
    subdir="$fullpath"
    while [ -n "$subdir" ] && [ "$subdir" != "/" ] && [ "$subdir" != "." ]; do
        if ! subdir="$(dirname "$subdir")"; then
            return 1
        fi
        contender="${subdir}.zip"
        if $check "$contender"; then
            printf '%s' "${contender}:/$(_withoutprefix "$fullpath" "$subdir/")"
            return 0
        fi
    done
    return 1
}

_archivepath() {
    # Return the archive part of the given path.
    printf '%s' "$1" | sed -nE 's#:/.+##p'
}

_archivekey() {
    # Return the key part of the given path.
    printf '%s' "$1" | sed -nE 's#.+:/##p'
}

_zip() {
    zipfile="$1"
    sourcedir="$2"
    _debug "zip: $sourcedir -> $zipfile"
    workdir=$(pwd)
    if ! $DRYRUN cd "$sourcedir"; then
        _err "zip: cannot change into dir: $sourcedir"
        return 1
    fi
    $DRYRUN "$ZIP_BIN" $ZIP_OPTS -m -T -MM -nw -0 -r "$zipfile" .
    cd "$workdir"
}

_trrntzip() {
    zipfile="$1"
    _debug "torrentzip: $zipfile"
    $DRYRUN "$TRRNTZIP_BIN" $TRRNTZIP_OPTS "$zipfile"
}

_unzip() {
    zipfile="$1"
    targetdir="$2"
    if ! $DRYRUN mkdir -p "$targetdir"; then
        _err "unzip: could not create target dir: $targetdir"
        return 1
    fi
    _debug "unzip: $zipfile -> $targetdir"
    if ! $DRYRUN "$UNZIP_BIN" $UNZIP_OPTS "$zipfile" -d "$targetdir"; then
        _err "unzip: cannot unzip file: $zipfile"
        return 1
    fi
}

_unzip_and_delete() {
    zipfile="$1"
    targetdir="$2"
    if ! _unzip "$zipfile" "$targetdir"; then
        return 1
    fi
    _debug "unzip and delete: deleted: $zipfile"
    if ! $DRYRUN rm "$zipfile"; then
        _err "unzip: cannot remove file: $zipfile"
        return 1
    fi
}

_autounarchive() {
    # Return the given path patched to point to implicitly unpacked archives.
    # The patched paths always win over the plain paths.
    # At the end of all actions the patched paths should be merged down onto
    # the target dir.
    path="$1"
    _debug "autounarchive: patching: $path"
    archive="$(_archivepath "$path")"
    if [ -n "$archive" ]; then
        if [ ! -f "$archive" ]; then
            _err "autounarchive: archive missing: $archive"
            return 1
        fi
        archivename="$(_withoutprefix "$archive" "$SEARCHDIR/")"
        patchdir="$FIXDIR/$archivename"
        if [ -f "$archive" ] && ! _unzip_and_delete "$archive" "$patchdir"; then
            return 1
        fi
        if [ ! -d "$patchdir" ]; then
            _err "autounarchive: archive dir missing: $archive -> $patchdir"
            return 1
        fi
        _debug "autounarchive: unzipped: $archive -> $patchdir"
        patched="$patchdir/$(_archivekey "$path")"
    else
        archivepath="$(_guess_archive "$path")"
        if [ -n "$archivepath" ]; then
            _debug "autounarchive: found archive: $path -> $archivepath"
            _autounarchive "$archivepath"
            return $?
        fi
        archivename=$(_withoutprefix "$path" "$SEARCHDIR/")
        patchpath="$FIXDIR/$archivename"
        archivepath="$(_guess_archive "$patchpath" _is_unpacked_zipfile)"
        if [ -n "$archivepath" ]; then
            _debug "autounarchive: found patch archive: $path -> $archivepath"
            patched="$(_archivepath "$archivepath")/$(_archivekey "$archivepath")"
        else
            patched="$path"
        fi
    fi
    _debug "autounarchive: patched path: $path -> $patched"
    printf '%s' "$patched"
}


# main

_mmove() {
    # Transparently move a file across the file system and zip files.
    source="$1"
    target="$2"
    if [ "$source" = "$target" ]; then
        return 0
    fi
    realsource="$(_autounarchive "$source")"
    if [ -z "$realsource" ]; then
        return 1
    fi
    realtarget="$(_autounarchive "$target")"
    if [ -z "$realtarget" ]; then
        return 1
    fi
    _move_file "$realsource" "$realtarget"
}

_rezip_fixdir() {
    if [ ! -d "$FIXDIR" ]; then
        return
    fi
    find "$FIXDIR" -type d -name '*.zip' |
    while read -r patchdir; do
        patchdir="$(realpath "$patchdir")"
        target="$TARGETDIR/$(_withoutprefix "$patchdir" "$FIXDIR/")"
        if ! _zip "$target" "$patchdir"; then
            _err "rezip: could not create zip: $patchdir -> $target"
            continue
        fi
        $DRYRUN rmdir -p "$patchdir" 2>/dev/null
        if ! _trrntzip "$target"; then
            _err "rezip: could not torrentzip zip: $target"
        fi
    done
    $DRYRUN rmdir -p "$FIXDIR" 2>/dev/null
}

_hide_unknown() {
    infopath="$1"
    basedir="$(dirname "$infopath")"
    unknownbase="${basedir}/.unknown"
    unknowndir="${unknownbase}/${RUNID}"
    unknowndir_created=0

    _print "# Hide unknown files in $unknowndir"
    sed -nE 's/^unknown: //p' "$infopath" |
    while read -r unknownfile; do
        if [ -z "$unknownfile" ] ||
           [ "$unknownfile" = "$infopath" ] ||
           _startswith "$unknownfile" "$unknownbase/" ||
           [ "$unknownfile" = "$unknownbase" ]; then
            continue
        fi
        archive="$(_archivepath "$unknownfile")"
        if [ -z "$archive" ]; then
            sourcefile="$unknownfile"
        else
            sourcefile="$archive"
        fi
        if [ ! -f "$sourcefile" ]; then
            _err "unknown: file not found: $sourcefile"
            continue
        fi
        if [ -n "$archive" ] && _is_zipfile "$archive" &&
           _is_alone_in_zipfile "$archive" "$(_archivekey "$unknownfile")"; then
            # Short circuit mmove's autounarchiving, should save some resources
            # on larger zip files.
            _debug "unknown: file is alone, moving as a whole: $unknownfile"
            unknownfile="$archive"
        fi
        unknowntarget="$unknowndir/$(_withoutprefix "$unknownfile" "$basedir/")"
        if [ -f "$unknowntarget" ]; then
            _rmdupe "$unknowntarget" "$unknownfile"
            continue
        fi
        if [ $unknowndir_created = 0 ]; then
            $DRYRUN mkdir -p "$unknowndir"
            unknowndir_created=1
        fi
        _print "unknown: $unknownfile -> $unknowntarget"
        _mmove "$unknownfile" "$unknowntarget"
    done
}

_arg() {
    # Return a positional argument from a colon-separated list, e.g.:
    # "foo: bar:/qoo: boo" -> 0: "foo", 1: "bar:/qoo", 2: "boo"
    pos="$1"
    text="$2"
    printf '%s' "$text" |
        sed -nE "s#^([^:]+(:/[^:]+)?: ){${pos}}([^:]+(:/[^:]+)?).*#\\3#p"
}

_collect_found() {
    infopath="$1"
    basedir="$(dirname "$infopath")"
    _print "# Collect found files in $basedir"

    grep -E '^rename(: .+){3}$' "$infopath" |
    while read -r found; do
        source="$(_arg 1 "$found")"
        gamename="$(_arg 2 "$found")"
        romname="$(_arg 3 "$found")"
        target="$basedir/$gamename/$romname"
        _print "rename: $source -> $target"
        _mmove "$source" "$target"
    done
    _rezip_fixdir
    return 0
}

_main() {
    infopath=$(realpath "$1")
    if [ ! -f "$infopath" ]; then
        _err "fix: no such file: $infopath"
        exit 1
    fi
    SEARCHDIR="$(dirname "$infopath")"
    TARGETDIR="$SEARCHDIR"
    FIXDIR="$TARGETDIR/.fix/$RUNID"
    _hide_unknown "$infopath"
    _collect_found "$infopath"
}
_main "$@"
