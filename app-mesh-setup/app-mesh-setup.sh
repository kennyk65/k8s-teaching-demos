#!/bin/bash
TEMP_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`
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
    curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.9/2020-08-04/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin
    kubectl version --short --client
else
    echo Looks like kubectl is already installed.
fi

# Configure kubeconfig
echo Configuring kubeconfig file for cluster $CLUSTER_NAME
aws eks update-kubeconfig --name $CLUSTER_NAME

# eksctl
if ! command -v eksctl &> /dev/null
then
    echo Installing eksctl
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
    eksctl version
else
    echo Looks like eksctl is already installed.
fi

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

# Preupgrade check
echo checking your cluster
curl -o pre_upgrade_check.sh https://raw.githubusercontent.com/aws/eks-charts/master/stable/appmesh-controller/upgrade/pre_upgrade_check.sh
./pre_upgrade_check.sh


echo Adding Helm repository for EKS:
helm repo add eks https://aws.github.io/eks-charts

echo Adding AppMesh Controller Resource Definitions (CRDs)
kubectl apply -k "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master"

echo Creating appmesh-system namespace
kubectl create ns appmesh-system

echo Creating OIDC provider
eksctl utils associate-iam-oidc-provider \
    --region=$AWS_REGION \
    --cluster $CLUSTER_NAME \
    --approve

echo Creating IAM-linked service account
eksctl create iamserviceaccount \
    --cluster $CLUSTER_NAME \
    --namespace appmesh-system \
    --name appmesh-controller \
    --attach-policy-arn  arn:aws:iam::aws:policy/AWSCloudMapFullAccess,arn:aws:iam::aws:policy/AWSAppMeshFullAccess \
    --override-existing-serviceaccounts \
    --approve

echo Creating appmesh-controller via helm
helm upgrade -i appmesh-controller eks/appmesh-controller \
    --namespace appmesh-system \
    --set region=$AWS_REGION \
    --set serviceAccount.create=false \
    --set serviceAccount.name=appmesh-controller

kubectl get deployment appmesh-controller \
    -n appmesh-system \
    -o json  | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'









