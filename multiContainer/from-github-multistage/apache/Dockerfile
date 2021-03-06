FROM nextdom-base:latest-amd64 AS builder

ARG initShdef
ENV initSh=${initShdef:-init.sh}
ARG POSTINST_DEBUG
ARG BRANCHdef
ENV BRANCH=${BRANCHdef:-master}
ARG VERSIONdef
ENV VERSION=${VERSIONdef:-}
ARG PHPVERdef
ENV PHPVER=${PHPVERdef:-php7.4}
ARG URLGITdef
ENV URLGIT=${URLGITdef:-noGitUrl}
ARG TARdef
ENV TAR=${TARdef:-none}
ARG aptcacher
ARG MYSQL_HOSTNAME

RUN echo "builder param branch: ${BRANCH} / version: ${VERSION} / tarBall: ${TAR} / initSh: ${initSh} / phpVer: ${PHPVER} / git url: ${URLGIT} "

RUN if [ ! -z ${aptcacher} ]; then echo "Acquire::http::Proxy \"http://${aptcacher}:3142\";" >/etc/apt/apt.conf.d/01proxy ; \
    echo "Acquire::https::Proxy \"http://${aptcacher}:3142\";" >>/etc/apt/apt.conf.d/01proxy ; fi
WORKDIR /usr/share/nextdom/
COPY nextdom-core-${VERSION}.tar.gz /usr/share/nextdom/nextdom.tar.gz
RUN mkdir -p /usr/share/nextdom /var/www/html/ && \
    cd /usr/share/nextdom/ && \
    if [ "none" != "${TAR}" -a ! -f nextdom.tar.gz ]; then echo "dl tar + unzip"; wget -O nextdom.tar.gz ${TAR};ls -alH .;fi ;
    # if release version exists and not wanting a specific branch
RUN echo "Branch: ${BRANCH}; version: ${VERSION}"; \
    if [ -f nextdom.tar.gz ]; then if [ "${BRANCH}" != "master" ] || [ "${VERSION}" != ""  ]; then tar --strip-components=1 -zxvf nextdom.tar.gz ; fi;rm nextdom.tar.gz ;fi ;
RUN if [ "b" != "b${VERSION}" -a -z "$(ls -A .)" ]; then echo "cloning and checkouting tag: ${VERSION} / ${URLGIT}"; git clone --depth 1 -b master ${URLGIT} . ; git fetch --tags ; git checkout $VERSION;fi;
RUN if [ -n "${BRANCH}" -a -z "$(ls -A .)" ]; then echo "cloning and checkouting branch: ${BRANCH} / ${URLGIT}"; git clone --depth 1 -b ${BRANCH} ${URLGIT} . ; fi
RUN cd /usr/share/nextdom; if [  -z "$(ls -A .)" ]; then echo "cloning depot"; git clone --depth 1 -b ${BRANCH:-master} $URLGIT . ;fi;
RUN ls -alR && cat /usr/share/nextdom/assets/config/Nextdom_version
#temp correction
ADD install_docker.sh /usr/share/nextdom/install/
ADD postinst.sh /usr/share/nextdom/install/scripts/
ADD preinst.sh /usr/share/nextdom/install/scripts/
ADD utils.sh /usr/share/nextdom/install/scripts/
ADD config.sh /usr/share/nextdom/install/scripts/
ADD apache/supervisord.conf /usr/share/nextdom/install/

RUN /bin/bash -xe install/install_docker.sh

#FROM balenalib/amd64-debian:buster-run as prod
FROM nextdom-base:latest-amd64 AS prod

ARG aptcacher
ARG initShdef
ENV initSh=${initShdef:-init.sh}
ARG POSTINST_DEBUG
ARG BRANCHdef
ENV BRANCH=${BRANCHdef:-master}
ARG VERSIONdef
ENV VERSION=${VERSIONdef:-}
ARG PHPVERdef
ENV PHPVER=${PHPVERdef:-php7.4}
ARG URLGITdef
ENV URLGIT=${URLGITdef:-noGitUrl}
ARG PRODUCTIONdef
ENV PRODUCTION=${PRODUCTIONdef:-"true"}

ENV ROOT_PASSWORD TBD
ENV APACHE_HTTP_PORT 80
ENV APACHE_HTTPS_PORT 443
ENV SSH_PORT 22
ENV locale-gen fr_FR.UTF-8
ENV DEBIAN_FRONTEND noninteractive
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE DontWarn
ENV MYSQL_HOSTNAME notLocalhost
ENV MYSQL_PORT 3306

EXPOSE 80
EXPOSE 443

RUN echo "prod param branch: ${BRANCH} / version: ${VERSION} / tarBall: ${TAR} / initSh: ${initSh} / phpVer: ${PHPVER} / apt-cache: ${aptcacher} / git url: ${URLGIT}";
RUN if [ -n ${aptcacher} ]; then echo "Acquire::http::Proxy \"http://${aptcacher}:3142\";" >/etc/apt/apt.conf.d/01proxy && \
    echo "Acquire::https::Proxy \"http://${aptcacher}:3142\";" >>/etc/apt/apt.conf.d/01proxy ; fi
RUN apt-get update && apt-get install -y at wget supervisor mariadb-client ntp ca-certificates unzip \
    curl sudo cron tar wget ntpdate htop iotop iftop smbclient python python-pip \
    software-properties-common libexpat1 ssl-cert apt-transport-https && apt upgrade -y

COPY --from=builder /etc/php /etc/php
COPY --from=builder /etc/cron.d /etc/cron.d
COPY --from=builder /etc/apache2/ /etc/apache2
COPY --from=builder /etc/nextdom/ /etc/nextdom
COPY --chown=www-data:www-data --from=builder /var/lib/nextdom /var/lib/nextdom
COPY --chown=www-data:www-data --from=builder /usr/share/nextdom /usr/share/nextdom
# just to get postinst for later analysis
COPY --chown=www-data:www-data --from=builder /var/log/nextdom/install.log /var/log/nextdom/install.log

RUN rm -Rf /var/www/html && ln -s "/usr/share/nextdom" "/var/www/html" \
 && cat /usr/share/nextdom/assets/config/Nextdom_version;\
 cat /usr/share/nextdom/core/config/Nextdom_version
RUN echo "root:$ROOT_PASSWORD" | chpasswd ;
RUN apt-get clean autoclean ; apt-get autoremove --yes ; \
 if [ -f /etc/apt/apt.conf.d/01proxy ]; then rm /etc/apt/apt.conf.d/01proxy ;fi; \
 rm -rf /var/lib/apt/lists/* ; \
 mkdir -p /var/log/supervisor ; \
 update-rc.d apache2 remove; update-rc.d cron remove;exit 0

ADD apache/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ADD apache/${initSh} /root/init.sh
RUN echo "init: ${initSh}" \
    && usermod -a -G dialout,tty www-data ; echo "www-data ALL=(ALL) NOPASSWD: ALL" | tee -a /etc/sudoers \
    && a2enmod ssl rewrite && a2dissite 000-default default-ssl && a2ensite nextdom nextdom-ssl \
    && chmod +x /root/init.sh #\
   #&& cat /usr/share/nextdom/core/config/Nextdom_version
WORKDIR /usr/share/nextdom/
RUN git init . && git remote add origin https://github.com/NextDom/nextdom-core/

ENTRYPOINT ["/root/init.sh"]