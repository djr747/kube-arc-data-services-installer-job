FROM bitnami/azure-cli:latest

ARG DEBIAN_FRONTEND=noninteractive

USER root

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install apt-transport-https gnupg -y && \
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list && \
    curl -s https://baltocdn.com/helm/signing.asc | gpg --dearmor | apt-key add - && \
    echo "deb [arch=$(dpkg --print-architecture)] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list && \
    apt-get update && \
    apt-get install kubectl helm jq nano -y && \
    apt-get -y remove apt-transport-https gnupg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -g 1001 -r container-user && \
    useradd --no-log-init -u 1001 -r -m -g container-user container-user && \
    chown -R 1001:1001 /home/container-user && \
    usermod -d /home/container-user container-user

COPY ./src/scripts /home/container-user

USER container-user

WORKDIR /home/container-user

ENV HOME=/home/container-user

RUN az extension add --name k8s-extension && \
    az extension add --name connectedk8s && \
    az extension add --name k8s-configuration && \
    az extension add --name customlocation && \
    az extension add --name arcdata 

#ENTRYPOINT ["tail", "-f", "/dev/null"]

ENTRYPOINT ["./install-arc-data-services.sh"]

