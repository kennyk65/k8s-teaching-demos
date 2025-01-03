#!/bin/bash
TEMP_REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region -s)
read -p 'Enter cluster name [primary]: ' CLUSTER_NAME
read -p 'Enter region ['${TEMP_REGION}']: ' AWS_REGION
CLUSTER_NAME=${CLUSTER_NAME:-primary}
AWS_REGION=${AWS_REGION:-${TEMP_REGION}}

# Set region
echo Setting region to $AWS_REGION
aws configure set region $AWS_REGION

# Kubectl
if ! command -v kubectl &> /dev/null
then
    echo Installing Kubectl
    # curl --silent -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.28.3/2023-11-14/bin/linux/amd64/kubectl
    curl --silent -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.31.0/2024-09-12/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin
else
    echo Looks like kubectl is already installed.
fi
kubectl version --short --client

# Configure kubeconfig
echo Configuring kubeconfig file for cluster $CLUSTER_NAME
aws eks update-kubeconfig --name $CLUSTER_NAME --alias admin --region $AWS_REGION

# eksctl
if ! command -v eksctl &> /dev/null
then
    echo Installing eksctl
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
else
    echo Looks like eksctl is already installed.
fi
eksctl version

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

# Display your current identity in the log 
echo Displaying current identity
aws sts get-caller-identity 
