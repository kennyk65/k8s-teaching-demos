#!/bin/bash
read -p 'Enter cluster name [MyCluster]: ' Cluster
read -p 'Enter region [us-west-2]: ' Region
Cluster=${Cluster:-MyCluster}
Region=${Region:-us-west-2}

# eksctl
echo Installing eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version

# Kubectl
echo Installing Kubectl
curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.9/2020-08-04/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin
kubectl version --short --client

# Set region
echo Setting region to $Region
aws configure set region $Region

# Display your current identity in the log 
echo Displaying current identity
aws sts get-caller-identity 

# Configure kubeconfig
echo Configuring kubeconfig file for cluster $Cluster
aws eks update-kubeconfig --name $Cluster

# Helm.  Must be installed after .kube/config exists.
echo Installing Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
chmod go-r ~/.kube/config
