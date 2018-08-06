"""Parser for strings in CLRMame Pro .dat format
"""

from itertools import chain
from typing import *

from .structs import *


Char = str
Token = str


def _tokens(chars: Iterable[Char]) -> Iterable[Token]:
    delimiters = '" \t\r\n'
    quot_mark = '"'
    is_quoted = False
    tok = ''
    for char in chars:
        if char is quot_mark:
            is_quoted = not is_quoted
            if is_quoted:
                continue
        if is_quoted or char not in delimiters:
            tok += char
        elif tok:
            yield tok
            tok = ''


Key = str
Value = str
SeqT = TypeVar('SeqT')
Seq = Callable[[Iterable], SeqT]


def _parse(toks: Iterable[Token], seq_type: Seq) -> Iterable[Tuple[Key, Union[SeqT, Value]]]:
    """_parse(tokens: seq<str>) -> seq<seq>"""
    key = None
    for tok in toks:
        if key is None:
            if tok is ')':
                break
            key = tok
        else:
            value: Union[SeqT, Value] = tok if tok is not '(' else seq_type(_parse(toks, seq_type))
            yield (key, value)
            key = None


AnyStruct = Union[Game, Rom, Header]


def _struct_decoder(pairs: Iterable[Tuple[Key, Union[AnyStruct, Value]]]) -> Iterable[Tuple[Key, Union[AnyStruct, Value]]]:
    typemap: Dict[Key, Type] = {'clrmamepro': Header, 'game': Game, 'rom': Rom}
    return tuple((key, val if key not in typemap else typemap[key].from_pairs(val)) for key, val in pairs)


def parse(lines: Iterable[str]) -> Iterable[Union[AnyStruct, Value]]:
    chars = chain.from_iterable(line + "\n" for line in lines)
    return (val for key, val in _struct_decoder(_parse(_tokens(chars), _struct_decoder)))


def parse_to_tuple(lines: Iterable[str]) -> Iterable[Tuple[Key, Union[Tuple, Value]]]:
    """parse(lines: seq<str>) -> seq<key: str, value: seq|str>"""
    chars = chain.from_iterable(line + "\n" for line in lines)
    return _parse(_tokens(chars), tuple)


def parse_to_dict(lines: Iterable[str]) -> Iterable[Dict[Key, Union[Dict, Value]]]:
    """parse.to_dict(lines: seq<str>) -> seq<dict>

    This is probably the function you want to use.
    Just be aware that it will overwrite duplicate keys with the last value,
    because that's how dicts work. :)
    """
    chars = chain.from_iterable(line + "\n" for line in lines)
    return ({key: val} for key, val in _parse(_tokens(chars), dict))


__all__ = 'parse', 'parse_to_dict', 'parse_to_tuple'
