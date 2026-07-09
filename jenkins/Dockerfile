FROM jenkins/jenkins:lts-jdk21

ARG KUBECTL_VERSION

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       lsb-release \
       ca-certificates \
       curl \
       gnupg \
       git \
       jq \
       python3 \
       python3-pip \
       python3-venv \
       wget \
       apt-transport-https \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL \
       https://download.docker.com/linux/debian/gpg \
       -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
       > /etc/apt/sources.list.d/docker.list \
    && wget -qO - \
       https://aquasecurity.github.io/trivy-repo/deb/public.key \
       | gpg --dearmor \
       -o /usr/share/keyrings/trivy.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
       > /etc/apt/sources.list.d/trivy.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       docker-ce-cli \
       trivy \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN test -n "${KUBECTL_VERSION}" \
    && ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL \
       -o /tmp/kubectl \
       "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
    && curl -fsSL \
       -o /tmp/kubectl.sha256 \
       "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl.sha256" \
    && echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" \
       | sha256sum --check \
    && install \
       -o root \
       -g root \
       -m 0755 \
       /tmp/kubectl \
       /usr/local/bin/kubectl \
    && rm -f \
       /tmp/kubectl \
       /tmp/kubectl.sha256 \
    && kubectl version --client

USER jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

RUN jenkins-plugin-cli \
    --plugin-file /usr/share/jenkins/ref/plugins.txt
