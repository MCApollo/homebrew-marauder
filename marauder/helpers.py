import os
from io import BytesIO
import re
import tarfile
import zipfile
from urllib.request import urlopen
import sys

default = re.compile(r'(?:([0-9]+(?:[.-_][0-9]+)+))')  # Version()

""" Get commonprefix of a remote archive """
def tar(url=None):
    r = urlopen(url)
    file = BytesIO(r.read())
    tar = tarfile.open(fileobj=file, mode='r')
    result = os.path.commonprefix(tar.getnames())
    file.close()
    return result

def zip(url=None):
    r = urlopen(url)
    file = BytesIO(r.read())
    zip = zipfile.ZipFile(file, mode='r')
    result = os.path.commonprefix(zip.namelist())
    file.close()
    return result

""" Takes URL string and guesses version """
def version(url):
    filename = os.path.basename(url)
    version = default.findall(filename)
    if not version:
        version = default.findall(url)  # Try the whole URL
        if version:
            return version[0]
        version = re.findall(r'(.+)?[-v_](:?[0-9]+)', filename)  # v40 or program-83 for example.
        if version:
            return version[0]
        if url.endswith(".git"):
            # print(f"Finding version for {url}", file=sys.stderr)
            latest_release = os.popen(
                f"git ls-remote --tags {url} 2>/dev/null | sort -Vk2 | awk 'END{{ print $2 }}' | grep -oE '[0-9]+(\\.[0-9]+)+'"
            ).read().strip()
            latest_commit = os.popen(
                f"git ls-remote --tags {url} 2>/dev/null | sort -Vk2 | awk 'END{{ print $1 }}'"
            ).read().strip()
            if latest_release and latest_commit:
                version = f"{latest_release}-git-{latest_commit[:8]}"
            elif latest_commit:
                version = f"1.0-git-{latest_commit[:8]}"
            else:
                return None
            return version

        if not version:  # If still no result.
            return None
    return version[0]
