#! /usr/bin/env python3
import json
import tempfile
from os import path
from os import chdir


def writer(file, outfile):
    def m(f):
        with open(f, 'r') as fp:
            data = json.loads(fp.read())
            depends = data.pop('depends')
            conflicts = data.pop('conflicts')
            resource = data.pop('resource')
            patches = data.pop('patches')
            try:
                marauder = data.pop('marauder')
            except KeyError:
                raise KeyError('JSON has no entry `marauder`')
            del data['install']
        # Self
        m.data = data
        m.depends = [x['depend'] for x in depends if not x['build-depend']]
        m.build = [x['depend'] for x in depends if x['build-depend']]
        m.conflicts = [x['conflict'] for x in conflicts]
        m.resource = resource
        m.patches = patches
        m.marauder = marauder

    m(file)

    # Print is used for newlines.

    with open(outfile, mode='w') as fp:
        for value in m.data.keys():
            if m.data[value]:
                print(f"{value}='{m.data[value]}'", file=fp)

        for value in ['depends', 'build', 'conflicts']:
            s = eval('m.' + value)
            if s:
                z = "('" + "' '".join(s) + "')"
                print(f'{value}={z}', file=fp)

        if m.resource:
            # Output
            # resource=('foo#http://example.com')
            # Execute: ${resource[0]//#/ }
            for value in m.resource:
                s += [f'{value["name"]}#{value["url"]}']
            z = "('" + "' '".join(s) + "')"
            print(f'resources={z}', file=fp)

        if m.patches:
            for value in m.patches:
                if not value['url']:  # == None
                    with tempfile.NamedTemporaryFile(mode='w', delete=False, dir='.', suffix='.patch') as patchfile:
                        for p in value['data']:
                            patchfile.write(p)  # Has newlines and tabs
                        n = path.basename(patchfile.name)
                    s += [f':local#{n}']
                # break  # Only one data patch can exist.
                else:
                    s += [f'p{value["strip"]}#{value["url"]}']
            if s:
                z = "('" + "' '".join(s) + "')"
                print(f'patches={z}', file=fp)

        if m.marauder:
            # Output:
            # brew(){
            #		./configure
            #		make install
            # }
            print('\nbrew(){', file=fp)
            s = '\t' + '\n\t'.join(m.marauder) + '\n}'
            print(s, file=fp)

if __name__ == "__main__":
    import sys
    argv = sys.argv[1:]
    if len(argv) == 0:
        print("usage: file.json")
        exit()
    file = path.realpath(argv[0])
    tempdir = tempfile.mkdtemp()
    chdir(tempdir)
    writer(file, 'LOOTFILE')
    print(f'Created {tempdir}/LOOTFILE')