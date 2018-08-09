from typing import Any, Iterable, Sequence, Tuple


class _Slotted:

    def __init__(self, **kwargs):
        for slot in self.__slots__:
            setattr(self, slot, kwargs.get(slot))

    @classmethod
    def from_pairs(Class, pairs: Iterable[Tuple[str, Any]]):
        return Class(**dict(pairs))

    def as_dict(self):
        return {slot: getattr(self, slot) for slot in self.__slots__}

    def __repr__(self):
        args = ', '.join(f'{slot}={getattr(self, slot)!r}'
                         for slot in self.__slots__)
        return f'{self.__class__.__name__}({args})'

    def _json_(self):
        return self.as_dict()


class Rom(_Slotted):
    name: str
    size: int
    crc: str
    md5: str
    sha1: str
    status: str

    __slots__ = 'name', 'size', 'crc', 'md5', 'sha1', 'status'

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        if 'flags' in kwargs and 'status' not in kwargs:
            self.status = kwargs['flags']

    @property
    def flags(self):
        return self.status

    @flags.setter
    def flags(self, value):
        self.status = value


class Game(_Slotted):
    name: str
    description: str
    roms: Sequence[Rom]

    __slots__ = 'name', 'description', 'roms'

    @classmethod
    def from_pairs(Class, pairs: Iterable[Tuple[str, Any]]):
        self = Class()
        roms = []
        for key, value in pairs:
            if key == 'rom':
                roms.append(value)
            elif key in self.__slots__:
                setattr(self, key, value)
        if roms:
            self.roms = tuple(roms)
        return self


class Header(_Slotted):
    name: str
    description: str
    version: str
    author: str
    homepage: str
    url: str

    __slots__ = 'name', 'description', 'version', 'author', 'homepage', 'url'


__all__ = 'Rom', 'Game', 'Header'
