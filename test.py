"""Test parser
"""

from parser import parse

def _test():
    given = """
    entity (
        name "Name 1 (Info)"
        description "Description 1"
        rom ( name "ROM Name 1" size 1048576 crc BB71B532 md5 BCF1218706E9B547EAB9E4BE58D54E2 sha1 5478015A91442E56BD76AF39447BCA365E06C272 flags verified )
    )
    entity (
        name
        "Name  2"
        description
        "Description 2"
    )
    """
    expected = (
        ('entity', (
            ('name', 'Name 1 (Info)'),
            ('description', 'Description 1'),
            ('rom', (
                ('name', 'ROM Name 1'),
                ('size', '1048576'),
                ('crc', 'BB71B532'),
                ('md5', 'BCF1218706E9B547EAB9E4BE58D54E2'),
                ('sha1', '5478015A91442E56BD76AF39447BCA365E06C272'),
                ('flags', 'verified'),
            )),
        )),
        ('entity', (
            ('name', 'Name  2'),
            ('description', 'Description 2'),
        )),
    )
    result = tuple(parse(given.split("\n")))
    assert str(expected) == str(result)

if __name__ == '__main__':
    _test()
