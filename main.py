#!/usr/bin/env python3
import subprocess
import json
import os
import sys
import glob
import bullet as b
from bullet import colors


def refresh():
    print("\033c")
    refresh.height = os.get_terminal_size().lines
    refresh.width = os.get_terminal_size().columns


def prompt(items, prompt=None):
    refresh()
    prompt = prompt or "Choose a option."
    h = int(refresh.height/1.5)
    w = int(refresh.width/4)
    l = len(items)
    cli = b.ScrollBar(prompt=prompt,
                      pointer="👉",
                      choices=items,
                      align=5,
                      margin=2,
                      shift=0,
                      height=h,
                      pointer_color=colors.foreground["cyan"],
                      word_color=colors.foreground["white"],
                      word_on_switch=colors.foreground["white"],
                      background_color=colors.background["black"],
                      background_on_switch=colors.background["black"])
    result = cli.launch()
    return result


def _json(location=None, update=False):
    """ Pulls data from homebrew """
    from marauder import helpers as m
    from marauder import parser as p

    def version(url):
        """ Grabs version from a url """
        v = m.version(url) or r'1.0-u'  # Unknown
        return ''.join(v)

    def skip():
        """ Returns True if depend is a banned one."""
        nonlocal parsed
        s = ['python@2',
                'python',
                'go',
                'mono',
                'ruby',
                'x11',
                'xcode',
                'java',
                'rust',
                'osxfuse',
                'gtk+3',
                'zsh',
                'perl',
                'node']
        for keys in parsed['depends']:
            if any(keys['depend'] in depend for depend in s):
                return True
        return False

    # main
    location = location or "json-output/"
    url = r'https://github.com/Homebrew/homebrew-core.git'
    cmd = ['git', 'clone', url]

    cmd = subprocess.Popen(cmd)
    cmd.wait()
#    if cmd.returncode > 0:
#        raise ChildProcessError("git return code > 0")
    if not os.path.isdir(location):
        os.mkdir(location)

    files = sorted(glob.glob("homebrew-core/Formula/" + '*'))
    for f in files:
        path = os.path.realpath(f)
        n = os.path.basename(f)  # Strips path
        n = n[:-3] + '.json'  # hping.rb -> `path`/hping.json

        if not update:
            parsed = p.parse(path)  # Returns list
            if skip():
                # Banned dependency was found.
                continue
            # Adding new information:
            parsed['version'] = version(parsed['url'])
            #   Take the url and try to fhe version
            #   Git repos will be the latest release and current commit.
            parsed['install'] = [line for line in parsed['install'] if line != '']
            #   Strip empty lines.
        else:
            if not os.path.exists(location + n):
                continue
            with open(location + n, 'r') as infile:
                parsed = json.load(infile)
            d = p.parse(path)

            d['version'] = version(d['url'])
            # Change data.
            parsed['url'] = d['url']
            parsed['version'] = d['patches']
            parsed['patches'] = d['patches']
        # /* if not update */
        with open(location + n, 'w') as fp:
            json.dump(parsed, fp, indent=4)
            if update:
                print(f"Updated to {fp.name}")
            else:
                print(f"Wrote to {fp.name}")


def _convert(location=None, file=None):
    """ Editor to the json output """
    from marauder import convertto as convert  # Handles the converison to the makepkg-like format.
    from marauder import install  # Attempts to parse the `def install` data.
    import shutil  # for rmtree
    import tempfile
    import textwrap
    from time import sleep

    def editor():
        """ Guesses the default editor """
        env = os.getenv("EDITOR") or None
        default = "nano"  # I prefer nano, meh.
        if os.path.exists('/usr/bin/editor'):
            return "/usr/bin/editor"
        elif env:
            return env
        else:
            return default

    # Main
    location = location or "json-output/"

    if not file:
        x = [os.path.basename(x) for x in sorted(glob.glob(location + '*'))]
        file = location + prompt(items=x, prompt="Choose a file.")

    # Get Data
    with open(file, 'r') as infile:
        data = json.load(infile)
        data['install'] = install.parse(data['install'])
        _data = data  # Keep a copy of the old data.
        depends = ', '.join([x['depend'] for x in data['depends']])

    while True:
        # Print data to screen
        refresh()
        x = os.path.basename(file)
        print(f"File: {x}\t" +
              f"https://github.com/Homebrew/homebrew-core/blob/master/Formula/{x[:-5]}.rb")
        print(f"Depends: {depends}") if depends else "\n"

        print("\nLINES\t|" + (r'-' * (int(refresh.width/2))))
        for n, line in enumerate(data['install']):
            line = '\u001b[36m' + line + '\u001b[0m'
            wrap = textwrap.TextWrapper(subsequent_indent="\u001b[0m. \t|\t\u001b[36m",
                                        width=refresh.width)
            print(wrap.fill(f"{n}\t|\t{line}"))

        """
        name
        Depends: foo, bar
        
        LINES   | ----------------------------
        1       |   bin.install "x" 
        2       |   prefix.install "y"
        3       |   pkg:configure
        """
        print(f'\033[{refresh.height-8}H')
        choice = b.Bullet(choices=['1 - Edit.',
                                   '2 - Test.',
                                   '3 - Write.',
                                   '4 - Remove.',
                                   '5 - Quit.',
                                   '6 - Skip/Next.',
                                   '7 - Misc'],
                          prompt="Choose a option.",
                          bullet="★",
                          indent=1,
                          align=5,
                          margin=2,
                          pad_right=4,
                          bullet_color=colors.foreground["green"])
        choice = choice.launch()[:1]

        if choice == '1':    # Edit
            with tempfile.NamedTemporaryFile(mode='w+') as fp:
                for l in data['install']:
                    fp.write(f'{l}\n')
                fp.flush()
                subprocess.Popen([f"{editor()}", f"{fp.name}"]).wait()
                #   `nano` /tmp/tempfile.XXX
                fp.seek(0)
                data['install'] = [z for z in fp.read().split('\n') if z != '']
                #   We write each line with a newline, so split on newlines.
            continue
        elif choice == '2':  # Test
            with tempfile.NamedTemporaryFile(mode='w+') as fp:
                data['marauder'] = data['install']

                # Pushd
                cwd = os.getcwd()
                tempdir = tempfile.mkdtemp()
                os.chdir(tempdir)

                # Write data
                json.dump(data, fp)
                fp.flush()

                convert.writer(fp.name, 'LOOTFILE')

                p = subprocess.Popen("marauder -L LOOTFILE --homebrew --debug-failure".split()
                                     ).wait()
            os.chdir(cwd)  # popd
            shutil.rmtree(tempdir)
            continue
        elif choice == '3':  # Write
            data['marauder'] = data['install']
            data['install'] = _data['install']
            with open(file, 'w') as fp:
                json.dump(data, fp, indent=4)
                print(f'Wrote to {file}')
                sleep(1)
            continue
        elif choice == '4':  # Remove
            os.remove(file)
            break
        elif choice == '5':  # Quit
            exit()
        elif choice == '6':  # Skip
            return
        else:                # Misc
            choice = b.Bullet(choices=['1 - Add Depends.'],
                              prompt="\tMisc:",
                              bullet=">",
                              indent=2,
                              align=10,
                              margin=2,
                              pad_right=4,
                              bullet_color=colors.foreground["yellow"])
            choice = choice.launch()[:1]
            if choice == '1':   # Edit depends
                x = input("\n\t Enter a dependency: ")
                data['depends'].append(
                    {'depend': x.lower(), 'build-depend': False}
                )
                depends = ', '.join([x['depend'] for x in data['depends']])
            continue
    return


if __name__ == "__main__":
    c = ['1 - Download & convert to JSON.',   # To JSON
         '2 - Update JSON',
         '3 - Select and Edit JSON.',
         '4 - Edit JSON without marauder data.']
    path = "json-output/"
    choice = prompt(items=c, prompt="Select a action.")
    choice = choice[:1]

    if choice == '1':
        q = b.YesNo(prompt="Are you sure? ").launch()
        if not q:  # No
            exit()
        _json()
        exit()
    elif choice == '2':
        q = b.YesNo(prompt="Are you sure? ").launch()
        if not q:
            exit()
        _json(update=True)
        exit()
    elif choice == '3':
        _convert()
        exit()
    elif choice == '4':
        for m in sorted(glob.glob('json-output/*')):
            with open(m, 'r') as fp:
                if 'marauder' in json.load(fp):
                    continue
            _convert(file=m)

