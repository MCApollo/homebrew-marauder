#!/usr/bin/env python3
import re
import csv
import sys


# FIXME 18 Errors - 18/02

def _variable(word):

    def ENV():
        # Easier to parse & handle this way.
        ENV.cc  = '$TARGET-clang'
        ENV.ld  = '$TARGET-ld'
        ENV.cxx = '$TARGET-clang++'
        ENV.cflags  = '${PKGCFLAGS}'
        ENV.ldflags = '${PKGLDFLAGS}'
        ENV.cxxflags = '${PKGCXXFLAGS}'
        ENV.cppflags = '${PKGCPPFLAGS}'
    ENV()

    prefix  = '$PKGPREFIX'
    man     = '$PKGPREFIX'  + '/share/man'
    pkgshare = '$PKGPREFIX' + '/share'
    lib     = '$PKGPREFIX'  + '/lib'
    share   = '$PKGREFIX'   + '/share'

    sysconfig = '/etc'
    bin       = '$PKGPREFIX' + 'bin'

    include = '$SDK' + '/usr/include'

    b = ['ENV', 'prefix', 'man', 'pkgshare', 'lib', 'include']

    w = ''.join(word)
    try:
        if not any([x for x in b if w.startswith(x)]):
            return False  # Prevent code execution
        word = eval(w)
    except NameError:
        return False
    except AttributeError:
        print(f'WARNING: {w} needs to be defined.', file=sys.stderr)
        # raise
        return False

    return word



def _system():
    """ Handles strings like: system "make", "install """

    def _configure():
        nonlocal l
        banned = [#'--disable-debug',
                    '--prefix=',
                    '--man=',
                    '--mandir=',
                    '--localstatedir=',
                    '--sysconfdir=',
                    '--infodir=',
                    '--datadir']
        regex = re.compile(f"{'|'.join(banned)}*")
        track = ''
        for x in l:
            if not any([a for a in x.split() if regex.search(a)]):
                track += f' {x}'

        l = track.strip()
        try:
            conf = re.search('(^.+/configure)', l).group(1)
        except AttributeError:
            print("ERROR: configure - AttributeError - NoneType has no attribute 'group'", file=sys.stderr)
            conf = l[0]
        if conf == './configure':
            l = l.replace(conf, f"pkg:configure")
        else:
            l = l.replace(conf, f"PKG_CONF={conf} pkg:configure")

    def _make():
        nonlocal l
        l = ' '.join(l)
        l = l.replace('install', 'DESTDIR=$pkgdir install', 1)
#        if  == 'make':  # if the line is just `make`
#            l = l.replace('make', 'pkg:make')  # Hand it to pkg:make for the args

    def _cmake():
        nonlocal l
        l = ' '.join(l)
        l = l.replace(r'*std_cmake_args', r'-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}')


    l = re.sub(r'^system', '', g_line).strip()
    l = list(csv.reader([l], quotechar='"', skipinitialspace=True))[0]

    # Convert #{variable} to a bash variable.
    variable = [k for k, p in enumerate(l) if re.findall(r'#{(?:[A-Za-z0-9.]+)}', p)]
    if variable:
        for p in variable:
            n = re.findall(r'#{([A-Za-z0-9.]+)}', l[p])
            k = _variable(n)
            if not k:
                continue  # _variable() returned False for some reason.
            l[p] = l[p].replace(f"#{{{''.join(n)}}}", f'{k}')

    if 'configure' in l[0]:
        _configure()
    elif 'cmake' in l[0]:
        _cmake()
    elif 'make' in l[0]:
        _make()
    else:
        l = ' '.join(l)

    return l


def _inreplace():
    # TODO: inreplace |s|, let replace be a bash function, so remove any shell characters.
    return -1

def _clean(file):
    """ Cleans up input for parsing """
    file = iter(file)

    def list():
        # FIXME: 2 Formulas will error out here - ['inreplace %w[configure Makefile], for example.
        nonlocal x
        if re.search(r'%[A-Za-z]\[', x):
            track = x
            if x.endswith("]") or '].each' in x:
                return track
            else:
                while True:
                    l = next(file)
                    track += f'{l}'
                    if re.search(r'^\]\.?', l):
                        break
                    track += ' '
            return track
        return False

    def newlines():
        nonlocal x
        if not x.endswith(','):
            return False
        line = x
        l = x
        while True:
            if not line.endswith(','):
                break
            line = next(file)
            l += f' {line}'
        return l

    out = []
    for x in file:
        _list = list()
        if _list:
            out += [_list]
        else:
            _newline = newlines()
            if _newline:
                out += [_newline]
            else:
                out += [x]
    return out


def parse(file=None):
    try:
        data = _clean(file)
    except StopIteration:
        print(f'ERROR: parse - StopIteration - {file}', file=sys.stderr)
        return None  # Error
    global g_line  # Global line
    n = []
    for g_line in data:
        if g_line.endswith('if build.head?'):
            continue  # Doesn't support head.
        elif g_line.startswith("system"):
            n += [_system()]
        elif g_line.startswith("mkdir"):
            try:
                cd = re.findall(r'\"(.+?)\"', g_line)[0]
            except IndexError:
                # TODO - Fix index error
                print("ERROR: parse - IndexError - cd regex failed", file=sys.stderr)
                n += [g_line]
                continue
            n += [re.sub('do$', f'&& cd {cd}', g_line)]
        elif g_line.startswith("cd"):
            n += [re.sub('do$', '', g_line)]
        else:
            n += [g_line]

    return n

"""
if __name__ == '__main__':

    test = ['system "./configure", "--disable-debug", "--disable-dependency-tracking",', '"--program-prefix=b", "--prefix=#{prefix}", "--man=#{man}", "CC=#{ENV.cc}"', 'system "make", "install"']
    #test = ['args = %W[', 'EXTRA_CFLAGS=-std=gnu89', 'LZ4_SUPPORT=1', 'LZMA_XZ_SUPPORT=1', 'LZO_DIR=#{Formula["lzo"].opt_prefix}', 'LZO_SUPPORT=1', 'XATTR_SUPPORT=0', 'XZ_DIR=#{Formula["xz"].opt_prefix}', 'XZ_SUPPORT=1', ']', 'cd "squashfs-tools" do', 'system "make", *args', 'bin.install %w[mksquashfs unsquashfs]']
    data = parse(test)
    print(data)
    if 1:
        import json, sys, os
        for fp in sys.argv[1:]:
            with open(os.path.abspath(fp), 'r') as input:
                data = json.load(input)
            if len(data['install']) < 5:
                #print(fp)
                print(parse(data['install']))
"""
