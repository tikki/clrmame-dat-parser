"""Parser
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

def _parse(toks):
    """_parse(tokens: seq<str>) -> seq<seq>"""
    key = None
    for tok in toks:
        if key is None:
            if tok is ')':
                break
            key = tok
        else:
            value = tok if tok is not '(' else tuple(_parse(toks))
            yield (key, value)
            key = None

def parse(lines):
    """parse(lines: seq<str>) -> seq<key: str, value: str>"""
    return _parse(_tokens(chain.from_iterable(line + "\n" for line in lines)))
