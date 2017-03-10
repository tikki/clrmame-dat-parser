"""Parser
"""

def _tokens(lines):
    """_tokens(lines: seq<str>) -> seq<str>"""
    spaces = " \t\r\n"
    delimiter = '"'
    is_delimited = False
    for line in lines:
        tok = ''
        for char in line:
            if is_delimited:
                if char == delimiter:
                    is_delimited = False
                else:
                    tok += char
            elif char == delimiter:
                is_delimited = True
            elif char in spaces:
                if tok:
                    yield tok
                    tok = ''
            else:
                tok += char
        if tok:
            yield tok

def _parse(toks):
    key = None
    value = None
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
    return _parse(_tokens(lines))
