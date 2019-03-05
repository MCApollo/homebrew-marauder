import re
import sys

keywords = re.compile(r"^(desc|homepage|url|mirror|bottle|patch|def|resource|depends_on|conflicts_with|__END__)")

regex_quoted = re.compile(r'["\'](.*?)["\']')
regex_resource = re.compile(r'resource "(.*?)" do')

def _reset():
    global result
    result = {
        "name": None,
        "description": None,
        "url": None,
        "mirror": None,
        "homepage": None,
        "depends": [],
        "resource": [],
        "conflicts": [],
        "patches": [],
        "install": []
    }


def _error(msg, err):
    print("ERROR: {} - {}".format(msg, err), file=sys.stderr)


def _name():
    t = _clean(next(line))
    try:
        t = t.split()[1]
    except IndexError as err:
        if "class" in t:
            _error("_name()", err)
            raise err
        else:
            pass
    result['name'] = t


def _patch():
    url = None
    strip = None
    data = None

    if x.endswith("__END__"):
        data = []
        while True:
            try:
                data.append(next(line))
            except StopIteration:
                break
        d = {"url": url, "data": data}
        result["patches"].append(d)
        return
    try:
        t = re.match(r'(?:patch) :p?(\d|DATA)', x).groups(0)[0]
    except AttributeError:
        """ `patch do` would be the case here, assume strip=1 """
        t = "1"
    if "DATA" in t:
        """ We'll get called later when __END__ appears """
        # print("Expecting DATA at EOF.")  # Debug line
        return
    else:
        strip = t
        while True:
            a = _clean(next(line))
            # print("----> {}".format(a))  # Debug
            if a.startswith("url"):
                try:
                    url = regex_quoted.findall(a)[0]
                except IndexError as err:
                    _error("IndexError in _patch()", err)
                    return -1
            if a.startswith("end"):
                break
        d = {"url": url, "strip": strip}
        result["patches"].append(d)


def _resource():
    name = None
    url = None
    if not regex_resource.match(x):
        return  # TEMP, CLEAN UP
    # Resource "XX" do
    try:
        name = regex_quoted.findall(x)[0]
    except IndexError as err:
        _error("IndexError in _resource() (name)", err)
        return -1
    while True:
        try:
            t = _clean(next(line))
        except StopIteration as err:
            _error("StopIteration in _resource()", err)
            break
        # print(t)  # debug
        if t.startswith("url"):
            try:
                url = regex_quoted.findall(t)[0]
            except IndexError as err:
                _error("IndexError in _resource() (url)", err)
                return -1
        if t.startswith("end"):
            break
    d = {"name": name, "url": url}
    result["resource"].append(d)
    return


def _homepage():
    try:
        homepage = regex_quoted.findall(x)[0]
        result['homepage'] = homepage
        return
    except IndexError as err:
        _error("IndexError in _homepage()", err)
        return -1


def _url():
    try:
        url = regex_quoted.findall(x)[0]
        if not result['url']:
            result['url'] = url
            return None
        else:
            return url
    except IndexError as err:
        _error("IndexError in _url()", err)
        return None


def _mirror():
    mirror = _url()
    if mirror:
        result['mirror'] = mirror
    else:
        return -1


def _bottle():
    return -1


def _description():
    try:
        description = regex_quoted.findall(_x)[0]
        result['description'] = description
    except IndexError as err:
        _error("IndexError in _description()", err)
        return -1
    return


def _clean(_line):
    """ Strips new lines and comments"""
    _line = _line.strip()
    if "# " in _line:
        _line = _line[:_line.index('#')]
    return _line


def _depends():
    name = None
    build = False  # Build Dependency
    try:
        a = None
        try:
            a = re.findall(r'depends_on :(\S*)', x)[0]
        except IndexError:
            pass
        if a:
            name = a
        else:
            name = regex_quoted.findall(x)[0]
    except IndexError as err:
        _error("IndexError in _depends(): line {}".format(x), err)
        return -1
    if x.endswith(":build"):
        build = True
    d = {'depend': name, 'build-depend': build}
    result["depends"].append(d)
    return


def _conflicts():
    name = None
    reason = None
    try:
        if ':because ' in x:
            t = x.split(':because ')[1]
            reason = regex_quoted.findall(t)[0]
        name = regex_quoted.findall(x)[0]
    except IndexError as err:
        _error("IndexError in _conflicts()", err)
        return -1
    d = {'conflict': name, 'reason': reason}
    result['conflicts'].append(d)
    return

def _install():
    grammar = re.compile(r'( do|if )')
    l = []
    c = 0
    while True:
        a = _clean(next(line))
        if grammar.match(a):
            c += 1
        elif a.startswith("end"):
            if c <= 0:
                break
            else:
                c -= 1
        l.append(a)
    result["install"] = l
    return


def _def():
    if "install" in x:
        _install()
    return -1


def _keywords(word):
    if word.startswith("desc") and not result['description']:
        _description()
    elif word.startswith("homepage") and not result['homepage']:
        _homepage()
    elif word.startswith("url") and not result['url']:
        _url()
    elif word.startswith("mirror") and not result['mirror']:
        _mirror()
    elif word.startswith("bottle"):
        _bottle()
    elif word.startswith("patch") or word.startswith("__END__"):
        _patch()
    elif word.startswith("resource"):
        _resource()
    elif word.startswith("depends_on"):
        _depends()
    elif word.startswith("conflicts_with"):
        _conflicts()
    elif word.startswith("def"):
        _def()
    else:
        return -1


def _parse(file):
    """ Reads the data """
    global line, x, _x
    # a = 0  # debug
    with open(file) as line:
        line = iter(line)
        while not result["name"]:
                _name()
        for x in line:
            _x = x  # Temp workaround for "#" in descriptions
            x = _clean(x)
            # a += 1  # debug
            # print("{} {}".format(a, x))  # Debug
            if keywords.match(x):
                # print("keywords match ({}) found! {}".format(keywords.search(x).group(1), x))  # DEBUG
                _keywords(keywords.search(x).group(1))


def parse(file):
    _reset()
    _parse(file)
    return result
