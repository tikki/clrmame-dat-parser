"""Parser
"""

def _tokens(lines):
    """_tokens(lines: seq<str>) -> seq<str>"""
    for line in lines:
        # tok = ''
        # for c in line:
        #     tok += c
        for tok in line.split():
            if tok:
                yield tok

def _parse(toks):
    key = None
    value = None
    mode = 'key' # val, val:str, rst
    for tok in toks:
        if mode is 'key':
            if tok is ')':
                break
            key = tok
            mode = 'val'
        elif mode is 'val':
            if tok.startswith('"'):
                mode = 'val:str'
                tok = tok[1:]
                value = []
            elif tok is '(':
                mode = 'rst'
                value = tuple(_parse(toks))
            else:
                mode = 'rst'
                value = tok
        if mode is 'val:str':
            if tok.endswith('"'):
                mode = 'rst'
                tok = tok[:-1]
            value.append(tok)
            if mode is 'rst':
                value = ' '.join(value)
        if mode is 'rst':
            yield (key, value)
            mode = 'key'

def parse(lines):
    """parse(lines: seq<str>) -> seq<key: str, value: str>"""
    return _parse(_tokens(lines))
