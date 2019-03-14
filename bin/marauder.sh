#!/usr/bin/env bash

# Based off makepkg

# Marauder - Build System for iOS
# Steals binaries from builds

unset CD_PATH
trap "sleep 3" TERM EXIT # For reading errors until _clean_up gets created.


# Anything that this script itself uses start with the prefix `_`
_colorize(){
    # Makepkg uses tput if it exists, but stick with ansi color codes.
    _BLACK="\033[0;30m"
    _RED="\033[0;31m"
    _GREEN="\033[0;32m"
    _YELLOW="\033[0;33m"
    _BLUE="\033[0;34m"
    _PURPLE="\033[0;35m"
    _CYAN="\033[0;36m"
    _WHITE="\033[0;37m"
    # High Intensity
    _HBLACK="\033[1;100m"
    _HRED="\033[1;101m"
    _HGREEN="\033[1;102m"
    _HYELLOW="\033[1;103m"
    _HBLUE="\033[1;104m"
    _HPURPLE="\033[1;105m"
    _HCYAN="\033[1;106m"
    _HWHITE="\033[1;107m"


    _MESSAGE="\033[3;0m"
    _RESET="\033[0m"
}

_exit_codes(){
    _EXIT_INTERNAL='3'  # We messed up.
    _EXIT_BUILD='2'     # The build messed up.
    _EXIT_USER='1'      # The user messed up.
    _EXIT_FAKEROOT='50' # Fakeroot message to us that it failed building the package.
}

_error(){
    msg="$@"
    printf 1>&2 "$_RED%s$RESET: $_BLACK%s$_RESET\n" "ERROR" "$msg"
}

_warning(){
    msg="$@"
    printf 1>&2 "$_YELLOW%s$RESET: $_BLUE%s\n" "WARNING" "$msg"
}

_message(){
    msg="$@"
    printf 1>&2 "$_MESSAGE%s$_RESET: $_BLACK%s$_RESET\n" "MESSAGE" "$msg"
}

_cd(){
    if ! cd "$@"; then
        _error "Failed to cd into $@"
        exit $_EXIT_INTERNAL
    fi
}

_source(){
    shopt -u extglob
    if ! source "$@"; then
        _error "Failed to source $@"
        exit $_EXIT_INTERNAL
    fi
}

_run_func(){
    [[ -z $1 ]] && return -1

    if command -v "$1" &>/dev/null && ! declare -f "$1" &>/dev/null; then
        _error "_run_func \`$1\` is a command, refusing."
        return -1
    fi

    local _functions=$1f
    local _args=()
    local shellopts=$(shopt -p)

    shift

    while (( $# )); do
        _args+=("$1")
        shift
    done

    "${_function}" "${_args[@]}"

    # Restore shell opts
    eval "$shellopts"
}

_run_func_safe(){
    local restoretrap
    local _function

    set -e; set -E

    restoretrap=$(trap -p ERR)

    [[ -z $restoretrap ]] && restoretrap="trap -- ERR"
	_function=$1

	trap "{ _error \"_run_func_safe - $_function\"; exit $_EXIT_INTERNAL; }" ERR

	_run_func $_function

	eval $restoretrap

	set +e; set +E
}

_download(){
    # Vars that can passed:
	local url=("$1")
	local proto="${url#*::}"
	local filename="${url##*/}"
	local clone=0 # Don't try to extract a git dir.
	local cmd=""

	[[ $url = *://*.git ]] && proto="git"
	# TODO: Fix this:
	# For now, seperate the url variable. $url should be the url and everything else is a argument to the command
	# Meant for git really:
	# url='https://example.com/example.git --branch foobar'

	case "$proto" in
		git)	filename=${filename%%.git}; cmd=("git" "clone" "$url" "$filename" "${url[@]:1}"); clone=1 ;;
		http*)	cmd=("wget" "$url" "-O" "$filename") ;;
		ftp*)	cmd=("wget" "$url" "-O" "$filename") ;;
		svn)	cmd=("svn" "co" "$url" "$filename"); clone=1 ;;
	esac

    echo "${cmd[@]}" 1>&2 # stderr because we need stdout to talk to the caller.
	if ! ${cmd[@]} 1>&2; then
		_error "Failed at ${cmd[@]}"
		exit ${_EXIT_INTERNAL}
	fi

	[[ ! -f "${filename}" ]] && \
		_warning "_download() - Missing ${filename}"

	filename=(${filename})
	if (( ${clone} )); then
		printf '%s %s' "${filename[0]}" "git"
	else
		printf '%s' "${filename[0]}"
	fi
	return
}

_extract(){
	local file=($1) # Break up spaces
	# TODO: Fix the way we do git clones
	[[ "${file[1]}" == "git" ]] && \
		{ printf "${file[0]}"; return; }

	local cmd=""
	local ext=${file##*.}
	local file_type=$(file -bizL "$file")
	local ret=0
	local commonprefix=''

	case "$file_type" in
		*application/x-tar*|*application/zip*|*application/x-zip*|*application/x-cpio*)
			case "$ext" in
				zip) cmd="unzip" ;;
				*) cmd="tar" ;;
			esac ;;
		*application/x-gzip*)
			case "$ext" in
				gz|z|Z) cmd="gzip" ;;
				*) ret=1 ;;
			esac ;;
		*application/x-bzip*)
			case "$ext" in
				bz2|bz) cmd="bzip2" ;;
				*) ret=1 ;;
			esac ;;
		*application/x-xz*)
			case "$ext" in
				xz) cmd="xz" ;;
				*) ret=1 ;;
			esac ;;
		*)
			# See if bsdtar can recognize the file
			if tar -taf "$file" -q '*' &>/dev/null; then
				cmd="tar"
			else
				ret=1
			fi ;;
	esac

	case "${cmd}" in
		tar) ${cmd} -xaf $file || ret=$?; ;;
		unzip) ${cmd} -qo "$file" || ret=$? ;;
		gzip|bzip2|xz) rm -f -- "${file%.*}" || : ;
			${cmd} -dcf "$file" > "${file%.*}" || ret=$?
			;;
	esac

	if command -v python3 &>/dev/null; then
	    case "${cmd}" in
	        tar)    commonprefix="$(python3 -c "import tarfile, os; print(os.path.commonprefix(tarfile.open(name=\"$file\", mode='r').getnames()))")" ;;
	        unzip)  commonprefix="$(python3 -c "import zipfile, os; print(os.path.commonprefix(zipfile.ZipFile(file=\"$file\", mode='r').namelist()))")" ;;
	    esac
	else
	    [[ $cmd == "tar" ]] && \
	        commonprefix="$(tar --list -f $file | head -n 1)"
	fi

	(( ret )) && \
		{ _error "Failed to extract $file ($ret)" "cmd -> ${cmd}" "file -> ${file}"; exit ${_EXIT_INTERNAL}; }

    printf "$commonprefix"
	return
}

_usage(){
cat << EOF
Marauder - Build System.

    Options: ${0##*/} {args}

        -L|--lootfile   /file/      - Read and build from \$file
        --config        /file/      - Read config from \$file
        --maintainer    "string"    - Use \$string as the maintainer
        --dpkg-args     "string"    - Gives \$string to dpkg-deb
        --no-clean                  - Don't remove \$build-directory
        --no-deb                    - Don't create a debian package.
        --color                     - Give messages color
        --config-example            - Print a config
        --debug-failure             - Spawn a shell to troubleshoot build issues.

    Defaults:
        config: ~/.marauder

EOF
}

_config_example(){
_message "Generating config..."
cat << EOF
# CONFIG START
# Needed vars:
HOST="$(curl 'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess' 2>/dev/null | bash)"
MAINTAINER="MCApollo <34170230+MCApollo@users.noreply.github.com>"
TARGET="aarch64-apple-darwin17"
architecture='iphoneos-arm'

# Paths
BUILDDIR=\${TMPDIR:-/tmp}
PKGDIR=\${PWD}

# Options

NAMEPREFIX='com.mc' # nnn -> com.mc.nnn
PKGPREFIX='/usr/local'
# DESCRIPTION='XXX, the place of Y' # Gives a tagline to all descriptions
# DPKGDEB_ARGS='-Zlzma'

# custom functions:
# custom() gets called before building.

CMAKE_TOOLCHAIN_FILE=\${HOME}/toolchain-arm64.cmake
SDK=\${HOME}/toolchain/SDK

custom(){

	pkg:configsub(){
		f=\${1:-config.sub}
		rm \$1 || return 1
		curl 'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub' -o \$1
		chmod +x \$1
	}

	pkg:extrainclude(){
		echo "-I\$HOME/iPhone-include"
	}

	pkg:configure(){
		cfg=( "\${PKG_CONF:-./configure}"	\\
			--build="\${HOST}"		\\
			--host="\${TARGET}"		\\
			--sysconfdir=/etc		\\
			\${SHARED:---enable-shared}	\\
			\${STATIC:---disable-static}	\\
			"\$@" )
		echo "\${cfg[@]}"
		"\${cfg[@]}"
	}

	pkg:patch(){
		for diff in \${srcdir}/*.diff \${srcdir}/*.patch; do
			if ! [[ -e \${diff} ]]; then
				continue
			fi
			patch -p\${1:-1} < "\${diff}"
		done
	}

	pkg:cmake(){
		cm=(	cmake		\\
			-DCMAKE_TOOLCHAIN_FILE="\${CMAKE_TOOLCHAIN}"	\\
			"\$@" )
		echo "\${cm[@]}"
		"\${cm[@]}"
	}

	pkg:setenv(){
			export CC=\${TARGET}-clang
			export LD=\${TARGET}-ld
			export CXX=\${TARGET}-clang++
			export STRIP=\${TARGET}-strip
			export AR=\${TARGET}-ar
			export RANLIB=\${TARGET}-ranlib
			export CCTOOLS_CLANG_AS_TARGET_TRIPLE=arm64-\${TARGET#*-}
			export AS=\${TARGET}-as
	}

	pkg:make(){
		make CC=\${TARGET}-clang LD=\${TARGET}-ld CXX=\${TARGET}-clang++ STRIP=\${TARGET}-strip "\$@"
	}
}

finalizepkg(){
	if (( STRIP )); then
		find -type f | while read binary; do
			x="\$(file \$binary)"
			case "\$x" in
				*': Mach-O'*'executable') ;;
				*) continue ;;
			esac
			\${TARGET}-strip -S - \$binary # Debug symbols
		done
	fi

	find -type f -exec ldid -S\$HOME/signme {} 2> /dev/null \\;
	find -type f -iname '.ldid*' -exec rm -f {} 2> /dev/null \\;

}
export -f custom
export -f finalizepkg

EOF
}

_brew_commands(){
    PKGPREFIX=${PKGPREFIX:-'/usr/local'}
    # Set sub commands for brew
    function ENV.deparallelize(){
        return
    }

    function ENV.ncurses_define(){
        return
    }

    function bin.install(){
        mkdir -p ${pkgdir}/${PKGPREFIX}/bin
        cp -r "$@" ${pkgdir}${PKGPREFIX}/bin
    }

    function man1.install(){
        mkdir -p ${pkgdir}${PKGPREFIX}/share/man1
        cp -r "$@" ${pkgdir}${PKGPREFIX}/share/man1
    }

    function prefix.install(){
        mkdir -p ${pkgdir}${PKGPREFIX}/share/
        cp -r "$@" ${pkgdir}${PKGPREFIX}/share/
    }

    function lib.install(){
        mkdir -p ${pkgdir}${PKGPREFIX}/lib
        cp -r "$@" ${pkgdir}${PKGPREFIX}/lib
    }

    function include.install(){
        mkdir -p ${pkgdir}${PKGPREFIX}/include
        cp -r "$@" ${pkgdir}${PKGPREFIX}/include
    }

    function pkgshare.install(){
        mkdir -p ${pkgdir}${PKGPREFIX}/share/${name,,}
        cp -r "$@" ${pkgdir}${PKGPREFIX}/share/${name,,}
    }

    function share.install(){
        mkdir -p ${pkgdir}${PKGPREFIX}/share/${name,,}
        cp -r "$@" ${pkgdir}${PKGPREFIX}/share/${name,,}
    }

    function doc.install(){
        mkdir -p ${pkgdir}${PKGPREFIX}/share/${name,,}
        cp -r "$@" ${pkgdir}${PKGPREFIX}/share/${name,,}
    }

    function etc.install(){
        mkdir -p ${pkgdir}/etc
        cp -r "$@" ${pkgdir}/etc/
    }
}

# ----------------------------

umask 0022 # Sane umask

_exit_codes # Set exit codes

# Color should be exempt from being unset.
unset pkgdir srcdir                 \
        BUILDDIR PKGDIR _CONFIG   \
        PKGPREFIX MAINTAINER        \
        DPKGDEB_ARGS                \
        NODEB   NOCLEAN             \
        _BUILDFILE                  \
        BREW INFAKEROOT             \
        LOOTDIR DEBUG_SHELL

# Buildfile sets these.
unset name version desc section       \
        author url priority homepage tags   \
        license depends makedepends conflict

declare -r ARGS="$@" # In case we need fakeroot.

while (( $# )); do
    case "$1" in
        # User
        -h|--help)  _usage; exit                ;;
        --config-example) _config_example; exit ;;
        # Public args:
        -L|--lootfile)  shift; _BUILDFILE="$1"  ;;
        --config)       shift; _CONFIG="$1"     ;;
        --maintainer)   shift; MAINTAINER="$1"  ;;
        --dpkg-args)    shift; DPKGDEB_ARGS="$1" ;;
        --no-clean)            NOCLEAN=1        ;;
        --no-deb)              NODEB=1          ;;
        --color)               COLOR=1          ;;
        # Debug
        --debug-failure)       DEBUG_SHELL=1; NODEB=1 ;;
            # Will spawn a shell on exit code, meant for debugging so no output binaries.
        # Private args:
        --fakeroot)            INFAKEROOT=1     ;;
        --env)          shift; _ENV=($@); break ;;
        --homebrew)            BREW=1           ;;
        # --fakeroot    - We're inside fakeroot, only run the pkg step.
        # --homebrew    - Execute brew() only and create dummy commands.
    esac
    shift
done

if [[ $UID == 0 ]] && ! (( $INFAKEROOT )); then
    _error "UID is 0, but --fakeroot is missing." \
    "If you're running as root, then don't."
    exit $_EXIT_USER
elif [[ $UID != 0 ]]; then
    # Keep this because we might need it for fakeroot
    _PWD=${PWD}
elif (( $INFAKEROOT )); then
    # _env=("$PKGDIR" "$BUILDDIR" "$_BUILDFILE" "$EXTRACTDIR" "$_CONFIG" "$_TMPD")
    PKGDIR=${_ENV[0]}
    BUILDDIR=${_ENV[1]}
    _BUILDFILE=${_ENV[2]}
    EXTRACTDIR=${_ENV[3]}
    _CONFIG=${_ENV[4]}
    _TMPD=${_ENV[5]}
fi

if (( BREW )); then
    # EXTRACTDIR would never be set, breaking fakeroot's $_ENV
    EXTRACTDIR=${EXTRACTDIR:-'None'}
fi

# Defaults
(( $COLOR )) && _colorize

[[ -z $_CONFIG ]] \
    && _CONFIG="${HOME}/.marauder"
_CONFIG="$(realpath $_CONFIG)"

[[ -z $_BUILDFILE ]] \
    && { _warning "Missing buildfile. Trying \`./LOOTFILE\`";
         _BUILDFILE="${PWD}/LOOTFILE"; }
_BUILDFILE="$(realpath $_BUILDFILE)"

# Keep note of where the buildfile is.
declare -r LOOTDIR="`dirname $_BUILDFILE`"
readonly _BUILDFILE  # Do not let `source` change this.

# Checking

if [[ ! -e $_BUILDFILE ]]; then
    _error "Missing build file. Use --help for help."
    exit ${_EXIT_USER}
else
    _source "$_BUILDFILE"
    if ! (( BREW )); then
        if declare -f brew &>/dev/null; then
            _error "brew() function in file, but --homebrew wasn't given."
            exit ${_EXIT_USER}
        fi
    fi
fi

if [[ ! -e $_CONFIG ]]; then
    _error "Missing config. Use --help for help."
    exit ${_EXIT_USER}
else
    _source "$_CONFIG"
fi

for var in 'name' 'version' 'url' 'description'; do
    [[ -z $var ]] && \
        { _error "Missing $var in $_BUILDFILE.";
         exit ${_EXIT_USER} ; }
     unset var  # Prevents bleeding variables.
done

# The config file can set these.
[[ -z $PKGDIR ]] && \
    PKGDIR="${PWD}"
[[ -z $BUILDDIR ]] && \
    { BUILDDIR="$(mktemp -d 2>/dev/null || mktemp -d -t "tmpdir")";
    _TMPD=1; }

# /tmp/name-version
declare -r srcdir="${BUILDDIR:-/nonexist}/${name}-${version}"
declare -r pkgdir="${PKGDIR:-/nonexist}/${name}-${version}"
declare -r _TMPD=${_TMPD:-0} # is it a mktemp directory?
mkdir -p "$srcdir"
mkdir -p "$pkgdir"/DEBIAN

# Function is declared here because of vars
_clean_up(){
    if (( ${DEBUG_SHELL:-0} && ${2:-0} )) && [[ ! -z ${EXTRACTDIR} ]]; then
        # If DEBUG_SHELL was given, this is (non crtl-c) trap exit, and if extractdir is not empty.
        _message "Dropping a shell as requested."
        _message "CRLT-D or run \`exit\` to exit the shell."
        _message "pwd: $PWD."
        _message "config: ${_CONFIG}, buildfile: ${_BUILDFILE}"
         /bin/bash --rcfile <(echo "PS1='(marauder): '") -i
         _message "Bye!"
    fi

    if ! (( $NOCLEAN )); then
        if (( $TMPD )); then
            # mktemp most likely created this directory
            _message "Removing mktemp directory ${BUILDDIR}"
            rm -rf -- "${BUILDDIR}"
        else
            rm -rf -- "${srcdir}"
	fi
        if (( $1 )); then # trap exit
            rm -rf -- "${pkgdir}"
        fi
    fi
} # Called on exit or failure

_patches(){  # brew() needs this.
    pushd ${srcdir}/${EXTRACTDIR} &>/dev/null
    for (( i=0; i<${#patches[*]}; i++)); do
        x=(${patches[$1]//#/ })
        _message "Patching ${x[1]}..."
        if [[ ${x[0]} == ':local' ]]; then
            for (( z=1; z<4; z++ )); do
                # Patch will prompt if it detects a tty
                echo "patch -p${z} < ${srcdir}/${x[1]}"
                if patch -p${z} < ${srcdir}/${x[1]} &>/dev/null; then
                    rm ${srcdir}/${x[1]} || :
                    break
                else
                    _error "patch ${x[1]} failed to stick. -p ${z}"
                fi
                _error "Failed to patch local patch"
		sleep 3
                exit ${_EXIT_INTERNAL};
            done
        else
            file=`realpath $(_download ${x[1]})`
            file=${file:-*.diff*} # If all goes wrong, this should catch it.
            file=${file:-*.patch*}
            echo "patch -${x[0]} < ${file}"
            # ${x[0]} will be 'p[0-9]'
            [[ ! -f ${file} ]] && \
            	_warning "${file} is missing!"
            patch -${x[0]} < ${file} &>/dev/null || \
                { _error "Failed to apply patch ${file##*/}"; sleep 3; exit ${_EXIT_INTERNAL}; }
           rm ${file} || :
        fi
    done
    popd &>/dev/null
}

trap "_clean_up 1" INT
trap "_clean_up 1 2" TERM EXIT
set -e

if ! (( INFAKEROOT || BREW )); then

# Execute
mkdir -p "$srcdir"

_cd "$srcdir"
_message "Getting URL ${url}"
EXTRACTDIR=$(_extract "$(_download $url)")

for file in ${LOOTDIR:-nonexist}/*; do
    if [[ -f ${file} && ${file} =~ .+\.(diff|patch|tar+|zip|sh)$ ]]; then
        cp ${file} ${srcdir}
    fi
done

for func in 'custom' 'prepare' 'build'; do # Order matters.
    if ! declare -f $func >/dev/null; then
        continue
    fi

    _cd "$srcdir"/"${EXTRACTDIR}"

    _run_func_safe "$func"
    unset func
done

else # (( INFAKEROOT || BREW ))
    if declare -f "custom" &>/dev/null; then
        cd $srcdir
        _run_func_safe "custom"
    fi

    if (( BREW && INFAKEROOT )); then
        _run_func_safe "_brew_commands"  # Sub functions for homebrew

    for file in ${LOOTDIR:-nonexist}/*; do
        if [[ -f ${file} && ${file} =~ .+\.(diff|patch|tar+|zip|sh)$ ]]; then
            cp ${file} ${srcdir}
        fi
    done

        EXTRACTDIR=$(_extract "$(_download $url 2>/dev/null)")
        _patches
        _cd "${srcdir}"/"${EXTRACTDIR}"
        _run_func_safe "brew"

    fi

    if declare -f "package" &>/dev/null; then
        # Homebrew wouldn't have package()
        _cd "${srcdir}"/"${EXTRACTDIR}"
        _run_func_safe "package"
    fi
fi # end (( INFAKEROOT || BREW ))

if [[ $UID != 0 ]]; then
    _message "Using fakeroot to install and package."
    _cd ${_PWD}
    _env=("$PKGDIR" "$BUILDDIR" "$_BUILDFILE" "$EXTRACTDIR" "$_CONFIG" "$_TMPD")

    set +e
    trap - INT TERM EXIT
    fakeroot -- bash -$- -- "${BASH_SOURCE[0]}" --fakeroot $ARGS --env "${_env[@]}" || err=$?
    (( $err )) && { _error "Something went wrong with fakeroot! Exit code: $err";
        exit ${_EXIT_FAKEROOT}; }
    exit 0
fi

# Package
CONTROL="${pkgdir}/DEBIAN/control"

# find -mindepth 1 -path "./marauder"  -prune -o -print
if [ ! "$(find "${pkgdir}" -type f)" ]; then
    _error "${pkgdir} is empty!"
    exit ${_EXIT_BUILD}
fi

# <- Copy any scripts.

for script in 'postinst' 'preinst' 'postrm' 'prerm' '_extrainst'; do
    if test -f ${LOOTDIR:-nonexist}/${script}; then
        cp -- ${LOOTDIR:-nonexist}/${script} "$pkgdir"/DEBIAN/
        chmod +x "$pkgdir"/DEBIAN/"$script"
    fi
    unset script
done

# <- Control file

if [[ ! -z ${NAMEPREFIX} ]]; then
    # NAMEPREFIX can be set to prefix the package name.
    # A name of `nnn` would become com.foo.nnn for example
    package="${NAMEPREFIX}.${name,,}"
    # Assume the conflicts are for the NAMEPREFIX
    # Packages with ':' are left alone.
    for ((x=0; x<${#depends[*]}; x++)); do
	if [[ ${depends[$x]} =~ ^:+ ]]; then
		depends[$x]=${depends[$x]//:/}
		continue
	else
		depends[$x]="${NAMEPREFIX}.${depends[$x]}"
	fi
    done
    for ((x=0; x<${#conflicts[*]}; x++)); do
        if [[ ${conflicts[$x]} =~ ^:+ ]]; then
		conflicts[$x]=${conflicts[$x]//:/}
                continue
        else
                conflicts[$x]="${NAMEPREFIX}.${depends[$x]}"
        fi
    done
else
    package="${name,,}"
fi

# TODO: Prepend on dpkg.

if [[ ! -z ${DESCRIPTION} ]]; then
   # Config can set this to give a tagline to all packages
   description="${DESCRIPTION}\n\t${description}" # On purpose.
fi

# Save a headace here by going with the lowercase name.
[[ ! -z ${MAINTAINER} ]] && \
    maintainer="${MAINTAINER}"
priority="${priority:-optional}"
# Because of $_control
_control=('package' 'name' 'version' 'section'
           'author' 'maintainer' 'priority' 'architecture'
           'homepage' 'tags' 'depends' 'conflicts'
           'predepends' 'replaces'
           'description')

printf '' > ${CONTROL}
for var in ${_control[@]}; do
	if ! test -z $var; then
		if [[ "$(eval echo \$$var)" == '' ]]; then
			# Empty var
			continue
		elif [[ "$(eval echo \${!$var[*]})" != '0' ]]; then
			# Loop for array
			printf -- "%s: "  "${var^}" >> $CONTROL
			_var="$(eval echo "\${$var[@]}")"
			printf -- '%s\n' "${_var[@]// /, }" >> $CONTROL
		else
			printf -- '%s\n' "${var^}: $(eval echo -e "\$$var")" >> $CONTROL
		fi
	fi
done

# <- Run dpkg

if declare -f finalizepkg &>/dev/null; then
    # Custom function that the config can set.
    # Let the config strip and codesign files.
    _cd $pkgdir
    _run_func_safe "finalizepkg"
fi

if (( NODEB )); then
    _message "Outputed to $pkgdir" \
    "Not running dpkg-deb as requested."
else
    _message "Building debian package to ${PKGDIR}"
    dpkg-deb -b ${DPKGDEB_ARGS} -- "${pkgdir}" "${PKGDIR}"
fi


trap - INT TERM EXIT
if ! (( $NOCLEAN )); then
	if (( ${_TMPD} )); then
		_message "Removing mktemp directory ${BUILDDIR}"
		rm -rf -- "${BUILDDIR}"
	else
		rm -rf -- "${srcdir}"
	fi
fi

if (( $DEBUG_SHELL )); then
    _warning "Rerun without --debug-failure for binaries."
    rm -rf -- "${srcdir}"
    rm -rf -- "${pkgdir}"
fi

exit 0
