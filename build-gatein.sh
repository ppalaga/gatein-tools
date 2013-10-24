#!/bin/bash

# This script helps GateIn developers to perform common tasks
# such as:
#  - building and running
#  - with or without tests
#  - running WildFly and Tomcat in parallel
#  - give auditive feedback when long running tasks fail or finish
#  - starting a clean browser session in the right instant
#
# Typical usage:
#  - Build gatein quickly without tests, start WildFly/JBoss AS and open browser:
#
#      build-gatein.sh
#
#  - Build gatein with tests (takes more than 20min), start WildFly/JBoss AS and open browser:
#
#      build-gatein.sh -runTests
#
#  - Build gatein with tests (takes more than 20min), start WildFly/JBoss AS, start Tomcat
#    in parallel and open browser:
#
#      build-gatein.sh -runTests -runTomcat
#
#
# Prerequisistes (i.a.):
#  - mvn
#  - WildFly/JBoss AS, the version named in ${wildFlyVersion}, unpacked in ${serversDir}
#    (/opt by default)
#  - Optionaly, when running with -runTomcat, Tomcat, the version named in ${tomcatVersion},
#    unpacked in ${serversDir} (/opt by default)
#
# Compatibility:
#  - Developed and tested on Fedora with KDE
#  - Should also work on other *nix OSes
#  - OSX support is underway, patches are welcome


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
tomcatVersion="7.0.42"
urlPath="/portal/classic"

# import utils.sh
 . "$(dirname "$0")/utils.sh"

auto_detect_commands

# other defaults
# scratchDir is where we build and run the portal. We always overwrite if necessary, but we never
# clean up old build directories. You need to do it manually from time to time
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
        -deployments ) shift
            # A file containing script that is invoked before starting the AS
            # you can place commands to copy WARs and EARs to AS deployment folders there.
            deployments="$1"
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
asBuildOpt=""
if [ "$runTomcat" == "true" ]
then
    asBuildOpt="-Dtomcat${tomcatMajorVersion}.name=apache-tomcat-${tomcatVersion}"
else
    asBuildOpt="-Dgatein.dev=jbossas${wildFlyVersionArr[0]}${wildFlyVersionArr[1]}${wildFlyVersionArr[2]}"
fi

if [ "$espeak" == "echo" ]
then
    echo "You may want to install espeak or similar program for auditive feed back."
fi

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


mvnClean=""
if [ "$clean" == "true" ]
then
    mvnClean="clean"
else
    mvnClean=""
fi


if [ "$skipBuild" == "false" ]
then

    # copy sources
    rm -Rf "$buildDir"
    mkdir -p "$buildDir"
    cd "${srcRoot}"
    # we use tar to copy because cp does not have any option to exclude a directory from copying
    tar cf - --exclude=.git "${project}" | (cd "$buildDir" && tar xf - )

    # build
    cd "$buildDir/$project"

    rm -Rf "$wildFlyTarget"
    "$mvn" clean ${mvnSettingsOpt}
    "$mvn" install ${mvnSettingsOpt} --projects build-config || die "Clean failed"
    cd component
    "$mvn" install ${mvnSettingsOpt} ${skipTests} || die "Component build failed"
    cd ..
    "$mvn" install ${mvnSettingsOpt} -Dservers.dir=$serversDir ${asBuildOpt} ${mavenTestsSkip} || die "GateIn build failed"

fi


function on_server_start() {
    open_clean_chrome_session "${chromeProfileDir}" ${chromeUrls}
    ${espeak} "GateIn build finished"
}

function handle_warn() {
    line="$1"
    trimmedLine=$(echo "$line" | sed 's/^[0-9:., ]*WARN *\[[^]]*\] *([^)]*) *//')
    if [ -f "$chromeProfileDir/First Run" ]
    then
        if [ "${lastWarning}" != "${trimmedLine}" ]
        then
            # Yes, we want this to be very annoying ;)
            lastWarning="${trimmedLine}"
            ${espeak} "Warning ${trimmedLine}"
        fi
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
    ${console} "cd ${tomcatInstallDir}; bin/gatein.sh run"
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

if [ -f "${deployments}" ]
then
    . "${deployments}"
fi

rm -f "$chromeProfileDir/First Run"

cd "$wildFlyInstallDir/bin"
./standalone.sh -b 0.0.0.0 $wildFlyPortOffsetOpt \
    | act_on_pattern " started in " "on_server_start" \
    | act_on_pattern "ERROR" "${espeak} Error" \
    | act_on_pattern "WARN" 'handle_warn "$line"'

