#!/usr/bin/env bash

set -e

if [[ ! -x "$(command -v kubectl)" ]]; then
    echo "kubectl not found"
    exit 1
fi

if [[ ! -x "$(command -v helm)" ]]; then
    echo "helm not found"
    exit 1
fi

REPO_GIT_INIT_PATHS="cluster"
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_URL=${1:-git@github.com:stefanprodan/gitops-istio}
REPO_BRANCH=master
TEMP=${REPO_ROOT}/temp

rm -rf ${TEMP} && mkdir ${TEMP}

# 1. Add Flux repository to Helm repos
helm repo add fluxcd https://charts.fluxcd.io

echo ">>> Installing Flux for ${REPO_URL}"

# Create the fluxcd namespace
kubectl create ns flux || true

# Install Flux by providing your GitHub repository URL
helm upgrade -i flux fluxcd/flux --wait \
--set git.url=${REPO_URL} \
--set git.branch=${REPO_BRANCH} \
--set git.path=${REPO_GIT_INIT_PATHS} \
--set git.pollInterval=1m \
--set registry.pollInterval=1m \
--set sync.state=secret \
--set syncGarbageCollection.enabled=true \
--namespace flux


echo ">>> Installing Helm Operator"
kubectl apply -f https://raw.githubusercontent.com/fluxcd/helm-operator/master/deploy/crds.yaml
helm upgrade -i helm-operator fluxcd/helm-operator --wait \
--set git.ssh.secretName=flux-git-deploy \
--set helm.versions=v3 \
--namespace flux


echo ">>> GitHub deploy key"
kubectl -n flux logs deployment/flux | grep identity.pub | cut -d '"' -f2

# wait until flux is able to sync with repo
echo ">>> Waiting on user to add above deploy key to Github with write access"
until kubectl logs -n flux deployment/flux | grep event=refreshed
do
  sleep 5
done
echo ">>> Github deploy key is ready"

# Install linkerd
echo ">>> Waiting for linkerd to start"
# wait until flux is able to sync with repo
# Download linkerd cli
curl -sL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

# Then install linkerd on remote cluster
linkerd install | kubectl apply -f -
linkerd check

echo ">>> Linkerd  is ready"

echo ">>> Configuring Flux for ${REPO_URL}"
helm upgrade -i flux fluxcd/flux --wait \
--set git.url=${REPO_URL} \
--set git.branch=${REPO_BRANCH} \
--set git.path="" \
--set git.pollInterval=1m \
--set registry.pollInterval=1m \
--set sync.state=secret \
--set syncGarbageCollection.enabled=true \
--namespace flux


echo ">>> Configuring Flagger"
helm repo add flagger https://flagger.app
#Install Flagger's Canary CRD:
kubectl apply -f https://raw.githubusercontent.com/weaveworks/flagger/master/artifacts/flagger/crd.yaml

echo ">>> Install Flagger in the linkerd namespace" 
helm upgrade -i flagger flagger/flagger --wait \
--namespace linkerd \
--set crd.create=false \
--set metricsServer=http://linkerd-prometheus:9090 \
--set meshProvider=linkerd


echo ">>> Cluster bootstrap done!"