from typing import *
import xml.etree.ElementTree as ET

from .structs import *


def parse(file) -> Iterable[Union[Header, Game]]:
    tree = ET.parse(file)
    root = tree.getroot()
    headerx = root.find('header')
    if headerx:
        header = Header()
        for slot in Header.__slots__:
            elem = headerx.find(slot)
            if elem is not None:
                setattr(header, slot, elem.text or '')
        yield header
    for gamex in root.findall('game'):
        game = Game()
        game.name = gamex.get('name')
        descriptionx = gamex.find('description')
        if descriptionx is not None:
            game.description = descriptionx.text or ''
        game.roms = tuple(Rom(**romx.attrib) for romx in gamex.findall('rom'))
        yield game
