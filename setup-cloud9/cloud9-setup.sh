#!/bin/bash
TEMP_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`
TEMP_ACCOUNT=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep accountId|awk -F\" '{print $4}'`
TEMP_ROLEARN=arn:aws:iam::$TEMP_ACCOUNT:role/EksClusterCreatorRole
read -p 'Enter cluster name [primary]: ' CLUSTER_NAME
read -p 'Enter region ['${TEMP_REGION}']: ' AWS_REGION
read -p 'Enter Role ARN of cluster creator ['${TEMP_ROLEARN}']: ' AWS_ROLEARN
CLUSTER_NAME=${CLUSTER_NAME:-primary}
AWS_REGION=${AWS_REGION:-${TEMP_REGION}}
AWS_ROLEARN=${AWS_ROLEARN:-${TEMP_ROLEARN}}

# Set region
echo Setting region to $AWS_REGION
aws configure set region $AWS_REGION

# Kubectl
if ! command -v kubectl &> /dev/null
then
    echo Installing Kubectl
    curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.21.2/2021-07-05/bin/linux/amd64/kubectl    
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin
else
    echo Looks like kubectl is already installed.
fi
kubectl version --short --client

# Configure kubeconfig
echo Configuring kubeconfig file for cluster $CLUSTER_NAME
aws eks update-kubeconfig --name $CLUSTER_NAME --role-arn $AWS_ROLEARN --alias admin --region $AWS_REGION
#aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

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
