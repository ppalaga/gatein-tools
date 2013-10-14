# A set of utility routines in a separate file, to be able to include them easily

# Autodetect commands
function auto_detect_commands() {
    # command defaults
    mvn="mvn"
    chrome="google-chrome"

    # some command autodetection
    if hash espeak 2>/dev/null; then
        espeak="espeak"
    elif hash speak 2>/dev/null; then
        espeak="speak"
    else
        espeak="echo"
    fi

    # terminal emulator
    if hash konsole 2>/dev/null; then
        console="konsole -e /bin/bash -c"
    elif hash gnome-terminal 2>/dev/null; then
        console="gnome-terminal -e /bin/bash -c"
    elif hash xterm 2>/dev/null; then
        console="xterm -e /bin/bash -c"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        console="osx_terminal"
    fi
}

# Say why and exit.
#
# Parameters:
#   $1 a message to say
#
# Environment:
#   ${espeak} - a program to give an auditive speech feedback.
#
function die() {
    "${espeak}" "$@"
    exit 1
}

# A simple utility to perform a given action when there appears a match for a given
# regular expression in the stdin.
#
# Parameters:
#   $1 regex
#   $2 action  - a command to execute when regex matches a line in stdin
#
function act_on_pattern() {
    regex="$1"
    action="$2"
    while IFS= read line
    do
        echo "$line"
        if [[ "$line" =~ $regex ]]
        then
          eval "$action"
        fi
    done
}

# Kills the process listening on a given port
#
# Parameters:
#   $1 portNumber
#
function free_port() {
    local pid=$(netstat -tulpen | grep ":$1 " |awk '{print $9}' | cut -d'/' -f 1)
    if [[ "${pid}" != "" && "${pid}" != "-" ]]
    then
        kill ${pid} > /dev/null 2>&1
        echo -n "Waiting for PID ${pid} to free port $1"
        while [[ ( -d /proc/${pid} ) && ( -z `grep zombie /proc/${pid}/status` ) ]]; do
            echo -n "."
            sleep 0.2
        done
        echo ""
    fi
}

# First kills all processes that contain chromeProfileDir in their full command and
# then opens a new Chrome session using the given profile directora and URL.
#
# Parameters:
#   $1 chromeProfileDir - directory that will be deleted and re-creared
#   $@ URLs to open
#
# Environment:
#   ${espeak} - a program to give an auditive speech feedback.
#   ${chrome} - Chrome executable.
#
function open_clean_chrome_session() {
    local chromeProfileDir="$1"
    shift

    local chromePids="$(ps -o pid,args -e | grep "[c]hrome.*user-data-dir=$chromeProfileDir" | sed 's/^ *\([0-9]*\).*/\1/')"
    local attemptCount="0"
    echo -n "Killing chrome with --user-data-dir=${chromeProfileDir}: "
    while [[ -n "$chromePids" && "${attemptCount}" -lt 25 ]]
    do
        kill -9 $chromePids
        sleep 0.2
        echo -n "."
        attemptCount=$((1 + $attemptCount))
        chromePids="$(ps -o pid,args -e | grep "[c]hrome.*user-data-dir=$chromeProfileDir" | sed 's/^ *\([0-9]*\).*/\1/')"
    done
    echo
    rm -Rf "$chromeProfileDir"
    mkdir -p "$chromeProfileDir"
    touch "$chromeProfileDir/First Run"
    ${chrome} --no-default-browser-check "--user-data-dir=${chromeProfileDir}" "$@" &> /dev/null &
}

# Execute a command in a new terminal window on OSX.
#
# Parameters:
#   $1 one or more semicolon-separated commands
function osx_terminal() {
    osascript -e 'tell application "Terminal" to do script "'"$1"'"'
}
