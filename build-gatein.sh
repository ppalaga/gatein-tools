#!/bin/bash

# This script helps GateIn developers to perform common tasks
# such as:
#  - building and running
#  - with or without tests
#  - running WildFly and Tomcat in parallel
#  - give auditive feedback when long running tasks fail or finish
#  - starting a clean browser session in the right instant

set -e
set -x


# command line option defaults
skipBuild="false"
skipReinstall="false"
skipTests="-DskipTests"
mavenTestsSkip="-Dmaven.test.skip"
runTomcat="false"
serversDir="/opt"
wildFlyVersion="7.1.1.Final"
tomcatVersion="7.0.41"
urlPath="/portal/classic"

# command defaults
mvn="mvn"
espeak="espeak"
rsync="rsync"
chrome="google-chrome"
console="konsole"

# other defaults
scratchDir=~/scratch
srcRoot=~/git
project="gatein-portal"

# Java opts
JAVA_OPTS="-Xms64m -Xmx512m -XX:MaxPermSize=256m -Djava.net.preferIPv4Stack=true -Dorg.jboss.resolver.warning=true -Dsun.rmi.dgc.client.gcInterval=3600000 -Dsun.rmi.dgc.server.gcInterval=3600000"
JAVA_OPTS="$JAVA_OPTS -Djboss.modules.system.pkgs=$JBOSS_MODULES_SYSTEM_PKGS -Djava.awt.headless=true"
JAVA_OPTS="$JAVA_OPTS -Djboss.server.default.config=standalone.xml"
JAVA_OPTS="$JAVA_OPTS -Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=8000"
JAVA_OPTS="$JAVA_OPTS -Dexo.product.developing=true"

# eval the configuration file if it exists
configPath=~/.build-gatein.conf
if [ -f "${configPath}" ]
then
    . "${configPath}"
fi


while [ "$1" != "" ]; do
    case $1 in
        -skipBuild ) shift
            skipBuild="true"
            ;;
        -skipReinstall ) shift
            skipReinstall="true"
            ;;
        -runTests ) shift
            skipTests=""
            mavenTestsSkip=""
            ;;
        -wildFlyVersion ) shift
            wildFlyVersion="$1"
            shift
            ;;
        -tomcatVersion ) shift
            tomcatVersion="$1"
            shift
            ;;
        -runTomcat ) shift
            runTomcat="true"
            ;;
        -mvnSettings ) shift
            mvnSettings="$1"
            shift
            ;;
        -serversDir ) shift
            serversDir="$1"
            shift
            ;;
        -urlPath ) shift
            urlPath="$1"
            shift
            ;;
        * ) shift
    esac
done


cd "${srcRoot}/${project}"
branch="$(git rev-parse --abbrev-ref HEAD)"

# a crazy idea to be able to run multiple branches in parallel
#autoPortOffset=$(echo "${branch}" | md5sum | gawk '{print $1}' | base64 -d | hexdump  -d -n 1 | head -n 1  | gawk '{print $2}')


buildDir="${scratchDir}/${project}-${branch}/build"
wildFlyInstallDir="${scratchDir}/${project}-${branch}/wildFly"
chromeProfileDir="${scratchDir}/${project}-${branch}/chrome"

wildFlyVersionArr=( ${wildFlyVersion//./ } )
wildFlyMajorVersion="${wildFlyVersionArr[0]}"
wildFlyTarget="${buildDir}/${project}/packaging/jboss-as${wildFlyMajorVersion}/pkg/target"
wildFlyDir="jboss-as-${wildFlyVersion}"

wildFlyPortOffset="100"
wildFlyPortOffsetOpt="-Djboss.socket.binding.port-offset=${wildFlyPortOffset}"
wildFlyHttpPort=$((8080 + $wildFlyPortOffset))

tomcatInstallDir="${scratchDir}/${project}-${branch}/tomcat"
tomcatVersionArr=( ${tomcatVersion//./ } )
tomcatMajorVersion="${tomcatVersionArr[0]}"
tomcatTarget="${buildDir}/${project}/packaging/tomcat/tomcat${tomcatMajorVersion}/target"

tomcatPortOffset="0"
#tomcatPortOffsetOpt="-Djboss.socket.binding.port-offset=${tomcatPortOffset}"
tomcatHttpPort=$((8080 + $tomcatPortOffset))


chromeUrls="http://127.0.0.1:${wildFlyHttpPort}${urlPath}"
if [ "$runTomcat" == "true" ]
then
  chromeUrls="${chromeUrls} http://127.0.0.1:${tomcatHttpPort}${urlPath}"
fi

mvnSettingsOpt=""
if [ "$mvnSettings" != "" ]
then
    mvnSettingsOpt="--settings ${mvnSettings}"
fi

export JAVA_OPTS


function die() { "${espeak}" "$@" ; exit 1; }

mvnClean=""
rsyncDelete=""
if [ "$clean" == "true" ]
then
    mvnClean="clean"
    rsyncDelete="--delete"
else
    mvnClean=""
    rsyncDelete=""
fi


if [ "$skipBuild" == "false" ]
then

    # copy sources
    if [ ! -d "$buildDir" ]
    then
        mkdir -p "$buildDir"
    fi
    ${rsync} -a $rsyncDelete --exclude=.git "${srcRoot}/${project}" "$buildDir"

    # build
    cd "$buildDir/$project"

    rm -Rf "$wildFlyTarget"
    "$mvn" clean ${mvnSettingsOpt}
    "$mvn" install ${mvnSettingsOpt} --projects build-config || die "Clean failed"
    cd component
    "$mvn" install ${mvnSettingsOpt} ${skipTests} || die "Component build failed"
    cd ..
    "$mvn" install ${mvnSettingsOpt} -Dservers.dir=$serversDir ${mavenTestsSkip} || die "GateIn build failed"

fi


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

function on_server_start() {
    local chromePids="$(ps -o pid,args -e | grep "[c]hrome.*user-data-dir=$chromeProfileDir" | sed 's/^ *\([0-9]*\).*/\1/')"
    local attemptCount="0"
    echo -n "Trying to kill chrome with --user-data-dir=${chromeProfileDir}: "
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
    # Well it would be cleaner to start two isolated chrome instances for WildFly and Tomcat
    # but one browser for both shoudl work in most cases as well
    ${chrome} --no-default-browser-check "--user-data-dir=${chromeProfileDir}" ${chromeUrls} &> /dev/null &
    ${espeak} "GateIn build finished"
    wildFlyStarted="true"
}

function handle_warn() {
    line="$1"
    trimmedLine=$(echo "$line" | sed 's/^[0-9:., ]*//')
    if [ "$wildFlyStarted" == "true" ]
    then
        # Yes, we want this to be very annoying ;)
        ${espeak} "$trimmedLine"
    fi
}

function free_port() {
    local pid=$(netstat -tulpen | grep ":$1 " |awk '{print $9}' | cut -d'/' -f 1)
    if [ "${pid}" != "" ]
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

function run_tomcat() {
    free_port "${tomcatHttpPort}"
    if [ "$skipReinstall" == "false" ]
    then
        rm -Rf "$tomcatInstallDir"
        if [ ! -d "$tomcatInstallDir" ]
        then
            mkdir -p "$tomcatInstallDir"
        fi

        cp -R -t "$tomcatInstallDir" "$tomcatTarget/tomcat/"*

    fi
    # We have not taught tomcat to speak yet :)
    ${console} -e /bin/bash -c "cd ${tomcatInstallDir}; bin/gatein.sh run"
}

set +x
if [ "$runTomcat" == "true" ]
then
    run_tomcat
fi

free_port "${wildFlyHttpPort}"
if [ "$skipReinstall" == "false" ]
then
    rm -Rf "$wildFlyInstallDir"
    if [ ! -d "$wildFlyInstallDir" ]
    then
        mkdir -p "$wildFlyInstallDir"
    fi

    cp -R -t "$wildFlyInstallDir" "$wildFlyTarget/jboss/"*

fi

wildFlyStarted="false"
cd "$wildFlyInstallDir/bin"
./standalone.sh -b 0.0.0.0 $wildFlyPortOffsetOpt \
    | act_on_pattern " started in " "on_server_start" \
    | act_on_pattern "ERROR" "${espeak} Error" \
    | act_on_pattern "WARN" 'handle_warn "$line"'
