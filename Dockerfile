FROM jenkins/jenkins:lts
# FROM jenkins/jenkins:2.184

ARG FOOTER_URL="https://jenkins.io"
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.footerURL=${FOOTER_URL} -Djava.util.logging=DEBUG" \
    JENKINS_CONFIG_HOME="/usr/share/jenkins" \
    TRY_UPGRADE_IF_NO_MARKER=true

ENV GOSU_VERSION="1.10" \
    TINI_VERSION="v0.16.1"

RUN echo 2.0 > /usr/share/jenkins/ref/jenkins.install.UpgradeWizard.state

USER root
RUN \
    apt-get update \
    && apt-get install -y \
      apt \
      apt-transport-https \
      bash \
      ca-certificates \
      curl \
      gnupg2 \
      jq \
      make \
      python-pip \
      python3-pip \
      software-properties-common \
    \
    && ARCH="$(dpkg --print-architecture | awk -F- '{ print $NF }')" \
    \
    && curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | apt-key add - \
    && add-apt-repository \
      "deb [arch=${ARCH}] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
      $(lsb_release -cs) \
      stable" \
    && apt-get update \
    && apt-get install -y \
      docker-ce \
    && adduser jenkins users \
    && adduser jenkins docker \
    \
    && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${ARCH}" \
    && chmod +x /usr/local/bin/gosu \
    && gosu nobody true \
    \
    && wget -O /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-${ARCH}" \
    && chmod +x /usr/local/bin/tini

RUN \
  mkdir -p \
    "${JENKINS_HOME}/.ssh/" \
    "${JENKINS_HOME}/config/" \
  || true \
  && chown jenkins:jenkins "${JENKINS_HOME}" -R \
  && ssh-keyscan -H github.com gitlab.com bitbucket.org >> /etc/ssh/ssh_known_hosts

RUN pip3 install ansible && ansible --version && ansible-galaxy install dev-sec.os-hardening && \
 printf -- "- hosts: 127.0.0.1\n  roles:\n    - dev-sec.os-hardening\n  vars:\n    - sysctl_config: []" \
 | tee /tmp/harden &&  ansible-playbook /tmp/harden --skip-tags "packages" \
 && pip3 uninstall --yes --quiet ansible

ARG CACHE_BUSTER=KEEP_CACHE

# install plugins
SHELL ["/bin/bash", "-c"]
COPY plugins-base.txt /usr/share/jenkins/ref/
RUN \
  ATTEMPTS=2 \
  /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins-base.txt \
  \
  && [[ ! -f /usr/share/jenkins/ref/plugins/failed-plugins.txt ]]


COPY plugins-extra.txt /usr/share/jenkins/ref/
RUN \
  ATTEMPTS=2 \
  /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins-extra.txt \
  \
  && [[ ! -f /usr/share/jenkins/ref/plugins/failed-plugins.txt ]]

#COPY init.groovy.d /usr/share/jenkins/ref/init.groovy.d/
COPY entrypoint.sh /entrypoint.sh

ENV CASC_JENKINS_CONFIG=/casc_config/cp-jenkins-export.yaml
COPY casc_config/ /casc_config/

ENTRYPOINT ["/entrypoint.sh"]
