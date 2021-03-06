#!/usr/bin/env bash

set -e

#get script directory
localDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
#volume for mysql
VOLMYSQL=$(basename $PWD)_mysqldata-prod
#Keep volume if Y, recreate otherwise
KEEP=N
#use latest release
RELEASE=N
#Define dockerfile and compose
YML=docker-compose.yml
DKRFILE=${localDir}/apache/Dockerfile
ARMDKRFILE=${DKRFILE}.armhf
#get cpu architecture
ARCHI=$(dpkg --print-architecture)
#set image architecture to build, by default only x86
TARGETARCHI="x86"
#image to build
BUILDARM=N
BUILDX86=Y
#use git instead of git tarball =N
TAR=Y
#use or not apt-cacher
CACHER="N"
APTPROXY=""
#DOCKER cache
CACHE=""
#fonctions

# :ahkpuzr
usage() {
  echo -e "\n$0: [abcfhkprtuz]\n\twithout option, container is built from github sources for x86 and has no access to devices"
  echo -e "\ta\tBy defaut only own cpu architecture image is build, if set to all, x86 and armhf images will be build"
  echo -e "\tb\tif set, define nextdom branch to clone"
  echo -e "\tc\tif set, apt-cacher will be use when building image"
  echo -e "\tf\tif set, docker build cache is flushed"
  echo -e "\th\this help"
  echo -e "\tk\tcontainer volumes are not recreated, but reused ( keep previous data intact)"
  echo -e "\tp\tcontainer has access to all devices (privileged: not recommended)"
  echo -e "\tr\tif set, the last nextdom release will be build, instead of branch"
  echo -e "\tu\tcontainer has access to ttyUSB0"
  echo -e "\tz\tMake a zip of nextdom"
  exit 0
}

setBuildx() {
  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
  isArmReady=$(docker buildx ls | grep amd-arm0 | grep -c arm/v7)
  if [ $isArmReady -eq 0 ]; then
    docker buildx rm amd-arm 2>/dev/null
    docker buildx create --use --name amd-arm --platform=linux/amd64,linux/arm64,linux/386,linux/arm/v7,linux/arm/v6
    docker buildx inspect --bootstrap amd-arm
  fi
}

generateCert() {
  echo -e "<I> Creating SSL self-signed certificat in /etc/nextdom/ssl/"
  if [ ! -d "${SSLDIR}" ]; then
    mkdir -p ${SSLDIR}
  fi
  openssl genrsa -out ${SSLDIR}nextdom.key 2048 2>&1
  openssl req -new -key ${SSLDIR}nextdom.key -out ${SSLDIR}nextdom.csr -subj "/C=FR/ST=Paris/L=Paris/O=Global Security/OU=IT Department/CN=example.com" 2>&1
  openssl x509 -req -days 3650 -in ${SSLDIR}nextdom.csr -signkey ${SSLDIR}nextdom.key -out ${SSLDIR}nextdom.crt 2>&1
}

createVolumes() {
  for volname in ${VOLMYSQL}; do
    VOL2DELETE=$(docker volume ls -qf name=${volname})
    [[ ! -z ${VOL2DELETE} ]] && echo **deleting volume $(docker volume rm ${VOL2DELETE})
    echo *creating volume $(docker volume create ${volname})
  done
}

updateEnvWebRelease() {
  RELEASE=$1
  #fetch last release once to preserve api while testing
  #[[ ! -f a ]] && curl -sH "Authorization: token $(cat ../githubtoken.txt)" "https://api.github.com/repos/Sylvaner/nextdom-core/releases/latest" >a ; jsonGit=$(cat a)
  #fetch last release at each run
  jsonGit=$(curl -s "https://api.github.com/repos/Nextdom/nextdom-core/releases/latest")
  gitTag=$(echo $jsonGit | grep -oP "\"tag_name\": \"([^\"]*)\"" | cut -f4 -d'"')
  gitZipBall=$(echo -e $jsonGit | grep -oP "\"zipball_url\": \"([^\"]*)\"" | cut -f4 -d'"')
  gitTarBall=$(echo -e $jsonGit | grep -oP "\"tarball_url\": \"([^\"]*)\"" | cut -f4 -d'"')

  #By default remove Tag
  for file in envWeb .env; do
    sed -i 's/VERSION=.*//g' ${file}
    sed -i '/^$/d' ${file}
  done

  #If RELEASE is requested, then use last release
  if [[ "Y" == "${RELEASE}" ]]; then
    if [[ -z ${gitTag} ]]; then
      echo github api not available ? github release var is empty
      echo VERSION:$VERSION / gitTag:$gitTag
      exit 1
    fi
    if [ "N" != "${TAR}" ]; then
      if [ ! -f nextdom-core-${gitTag}.tar.gz ]; then
        rm -f nextdom-core-*.tar.gz
        wget -O nextdom-core-${gitTag}.tar.gz ${gitTarBall}
      fi
    fi
    echo -e "\nAdding latest release (${gitTag}) to envWeb"
    #echo gitTar: $gitTarBall
    echo "VERSION=${gitTag}" | tee -a envWeb
    echo "VERSION=${gitTag}" | tee -a .env
  else
    gitTarBall=""
    gitTag=""
    sed -i "/VERSION=/d" .env
    sed -i "/VERSION=/d" envWeb
  fi
}

generateArmHfDockerfile() {
  if [ "xarmhf" = "x${ARCHI}" ]; then
    sed 's#amd64-debian#armv7hf-debian#' ${DKRFILE} >${ARMDKRFILE}
    sed -i 's#amd64-debian#armv7hf-debian#' ${ARMDKRFILE}
  else
    #replace strecth amd for stretch  rmhf
    sed 's#FROM balenalib/amd64-debian:stretch-run as builder#FROM balenalib/armv7hf-debian:stretch-build as builder\
RUN [ "cross-build-start" ]#' ${DKRFILE} >${ARMDKRFILE}
    sed -i 's#FROM balenalib/amd64-debian:stretch-run as prod#RUN [ "cross-build-end" ]\
FROM balenalib/armv7hf-debian:stretch-run as prod\
RUN [ "cross-build-start" ]#' ${ARMDKRFILE}
    #replace strecth amd for stretch  rmhf
    #FROM balenalib/amd64-debian:buster-build as builder
    sed 's#FROM balenalib/amd64-debian:buster-build as builder#FROM balenalib/armv7hf-debian:buster-build as builder\
RUN [ "cross-build-start" ]#' ${DKRFILE} >${ARMDKRFILE}
    sed -i 's#FROM balenalib/amd64-debian:buster-run as prod#RUN [ "cross-build-end" ]\
FROM balenalib/armv7hf-debian:buster-run as prod\
RUN [ "cross-build-start" ]#' ${ARMDKRFILE}
    #' ${ARMDKRFILE}
    sed -i 's#FROM balenalib/amd64-debian:buster-run as prod#FROM balenalib/armv7hf-debian:buster-run as prod#' ${ARMDKRFILE}

    echo 'RUN [ "cross-build-end" ]' | tee -a ${ARMDKRFILE}
  fi
  echo "****** Check ARM docker file ********"
  grep -E "FROM|RUN \[" ${ARMDKRFILE}
  echo "*************************************"
}

setProxy() {
  iface=$(ls -l /sys/class/net/ | grep -v virtual)

  myIp=$(ifconfig wlp2s0 | grep "inet " | awk '{print $2}')
  APTPROXY="--build-arg aptcacher=${myIp}"
}

########################
#       Main
########################
source .env
source envMysql

#getOptions
while getopts ":ab:chfkprtuz" opt; do
  case $opt in
  a)
    echo "building only for x86 architecture"
    TARGETARCHI="x86"
    ;;
  b)
    BRANCH=$OPTARG
    echo "using branch ${BRANCH}"
    ;;
  c)
    echo "use apt-cacher (apt local cache)"
    CACHER="Y"
    setProxy
    ;;
  f)
    echo "flush docker cache"
    CACHE=" --no-cache"
    ;;
  h)
    usage
    ;;
  k)
    echo -e "\nkeep docker volume (database)"
    KEEP=Y
    ;;
  p)
    echo -e "\ndocker will have access to all devices\n"
    YML="docker-compose.yml -f docker-compose-privileged.yml"
    ;;
  r)
    echo -e "\nUse latest release"
    RELEASE=Y
    ;;
  u)
    echo -e "\n docker will have access to ttyUSB0\n"
    YML="docker-compose.yml -f docker-compose-devices.yml"
    ;;
  z)
    echo -e "\nMaking a zip in docker"
    ZIP=Y
    ;;
  t)
    echo -e "Use latest release tarBall, instead of git clone"
    TAR=Y
    RELEASE=Y
    ;;
  \?)
    echo "${ROUGE}Invalid option -$OPTARG${NORMAL}" >&2
    ;;
  esac
done

set -x

#generate auto-signed certificate
[[ ! -f ${SSLDIR}nextdom.key ]] && generateCert

updateEnvWebRelease ${RELEASE}

#if arm then build only arm image
if [ "${ARCHI}" == "armhf" ]; then
  echo -e "\nOnly ${ARCHI} will be build"
  YML=docker-compose-armhf.yml
  BUILDARM=Y
  BUILDX86=N
  TARGETARCHI="arm"
else
  echo -e "\n${ARCHI} will be build"
  # sinon build x86 image
  BUILDX86=Y
  # and armhf if needed
  [[ "${TARGETARCHI}" == "all" ]] && BUILDARM=Y && echo -e "\n and also armhf."
fi

#generate ARM dockerfile
[[ ! -f ${DKRFILE} ]] && echo -e "\nError, Dockerfile is not found\n" && exit 1
[[ -f ${ARMDKRFILE} ]] && rm ${ARMDKRFILE}
[[ "${BUILDARM}" == "Y" ]] && generateArmHfDockerfile

# extract local project to container volume
if [ "Y" == ${KEEP} ]; then
  # stop running container
  docker-compose -f ${YML} stop
else
  # stop container and remove volume
  docker-compose -f ${YML} down -v --remove-orphans
fi

# build
bVer=""
bbranch=" --build-arg BRANCHdef=master"
[[ ! -z ${gitTag} ]] && bVer=" --build-arg VERSIONdef=${gitTag}"
[[ -z ${gitTag} ]] && bbranch=" --build-arg BRANCHdef=${BRANCH}" && gitTarBall="" &&
  echo "using branch: ${BRANCH}, tag: $gitTag, URL:${URLGIT}, init: ${initSh} tarBall:${gitTarBall}"

#if on a amd64 architecture try to cross build armhf version
if [ "${ARCHI}" == "amd64" ] && [ "${TARGETARCHI}" == "all" ]; then
  YML2=docker-compose-armhf.yml
  BUILDARM=Y
fi

if [ "${TAR}" = 'N' ]; then gitTarBall=''; fi

#Build image according to architecture
[[ ${BUILDX86} == "Y" ]] && {
  # prepare parent image used for building and running
  #CACHE="--no-cache"
  [[ -z $(docker images -q nextdom-base) ]] && {
    DOCKER_BUILDKIT=1 docker build -f ${DKRFILE}.1 ${CACHE} --build-arg PHPVERdef=7.3 ${APTPROXY} -t nextdom-base:latest-amd64 .
    [[ $? -ne 0 ]] && (echo "Error, aborted building nextdom base" && exit)
    docker tag nextdom-base:latest-amd64 edgd1er/nextdom-base:latest-amd64
  }
  #CACHE="--no-cache"
  #build target build +prod
  DOCKER_BUILDKIT=1 docker build -f ${DKRFILE} ${CACHE} ${bbranch} ${bVer} --target builder --build-arg MYSQL_HOSTNAME=notLocalhost --build-arg URLGITdef=${URLGIT} --build-arg initShdef=${initSh} --build-arg TARdef=${gitTarBall} --build-arg PHPVERdef=7.3 ${APTPROXY} --build-arg MYSQL_HOSTNAME=notLocalhost --build-arg POSTINST_DEBUG=1 -t nextdom-web:latest-amd64 .
  DOCKER_BUILDKIT=1 docker build -f ${DKRFILE} ${CACHE} ${bbranch} ${bVer} --build-arg MYSQL_HOSTNAME=notLocalhost --build-arg URLGITdef=${URLGIT} --build-arg initShdef=${initSh} --build-arg TARdef=${gitTarBall} --build-arg PHPVERdef=7.3 ${APTPROXY} --build-arg MYSQL_HOSTNAME=notLocalhost --build-arg POSTINST_DEBUG=1 -t nextdom-web:latest-amd64 .
  #[[ $? -ne 0 ]] && ( echo "Error, aborted building nextdom-web:latest-amd64" && exit )
}

[[ ${BUILDARM} == "Y" ]] && (
  #docker build --target base --build-arg ${bVer} --build-arg BRANCHdef=master --build-arg URLGITdef=${URLGIT} --build-arg initShdef=${initSh} --build-arg TARdef=${gitTarBall} --build-arg PHPVERdef=7.3 -t nextdom-web:latest-armhf -f ${ARMDKRFILE} --build-arg http_proxy=http://${myIp}:3142/ --build-arg https_proxy=http://${myIp}:3142/ .
  docker build -f ${ARMDKRFILE} ${CACHE} ${bVer} --build-arg BRANCHdef=master --build-arg URLGITdef=${URLGIT} --build-arg initShdef=${initSh} --build-arg TARdef=${gitTarBall} --build-arg PHPVERdef=7.3 --build-arg aptcacher="${myIp}" --build-arg POSTINST_DEBUG=1 -t nextdom-web:latest-armhf .
  #[[ $? -ne 0 ]] && ( echo "Error, aborted building nextdom-web:latest-armhf" && exit )
)

#Place tags
[[ ${BUILDX86} == "Y" ]] && echo "tagging amd64 image" && docker tag nextdom-web:latest-amd64 edgd1er/nextdom-web:latest-amd64
[[ ${BUILDARM} == "Y" ]] && echo "tagging armhf image" && docker tag nextdom-web:latest-armhf edgd1er/nextdom-web:latest-armhf

# prepare volumes
docker-compose -f ${YML} up --no-start

if [ "Y" == "${ZIP}" ]; then
  echo zipping ${NEXTDOMTAR}
  docker run --rm -v $(pwd):/backup ubuntu bash -c "tar -zcf /backup/${NEXTDOMTAR} -C /var/www/html/ -C /etc/nextdom -C /var/lib/nextdom -C /usr/share/nextdom"
fi

docker-compose -f ${YML} up --remove-orphans
#disable sha2_password authentification
#docker-compose -f ${YML} exec mysql sed -i "s/# default/default/g" /etc/my.cnf
