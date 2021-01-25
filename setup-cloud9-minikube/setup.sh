#!/bin/bash
cd ~

# Kubectl
if ! command -v kubectl &> /dev/null
then
    echo Installing Kubectl
    curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl    
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin
else
    echo Looks like kubectl is already installed.
fi
kubectl version --short --client

# helm
if ! command -v helm &> /dev/null
then
    echo Installing Helm
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    chmod go-r ~/.kube/config
else
    echo Looks like Helm is already installed.
fi

# minikube
if ! command -v minikube &> /dev/null
then
    echo Installing minikube
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube    
else
    echo Looks like minikube is already installed.
fi
minikube version


# Start minikube
minikube start --vm-driver=none
minikube status