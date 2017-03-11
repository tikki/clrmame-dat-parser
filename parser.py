"""Parser for strings in CLRMame Pro .dat format
"""

from itertools import chain

def _tokens(chars):
    """_tokens(chars: seq<char>) -> seq<str>"""
    delimiters = '" \t\r\n'
    quot_mark = '"'
    is_quoted = False
    tok = ""
    for char in chars:
        if char is quot_mark:
            is_quoted = not is_quoted
            if is_quoted:
                continue
        if is_quoted or char not in delimiters:
            tok += char
        elif tok:
            yield tok
            tok = ""

def _parse(toks, seq_type=tuple):
    """_parse(tokens: seq<str>) -> seq<seq>"""
    key = None
    for tok in toks:
        if key is None:
            if tok is ')':
                break
            key = tok
        else:
            value = tok if tok is not '(' else seq_type(_parse(toks, seq_type))
            yield (key, value)
            key = None

def parse(lines):
    """parse(lines: seq<str>) -> seq<key: str, value: seq|str>"""
    chars = chain.from_iterable(line + "\n" for line in lines)
    return _parse(_tokens(chars))

def _parse_to_dict(lines):
    """parse.to_dict(lines: seq<str>) -> seq<dict>

    This is probably the function you want to use.
    Just be aware that it will overwrite duplicate keys with the last value,
    because that's how dicts work. :)
    """
    chars = chain.from_iterable(line + "\n" for line in lines)
    return ({key: val} for key, val in _parse(_tokens(chars), dict))

parse.to_dict = _parse_to_dict
