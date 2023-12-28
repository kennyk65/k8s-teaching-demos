#!/bin/bash
INSTANCE_ID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
TEMP_REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region -s)
TEMP_ACCOUNT=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep accountId|awk -F\" '{print $4}'`
TEMP_ROLEARN=arn:aws:iam::$TEMP_ACCOUNT:role/EksClusterCreatorRole
read -p 'Enter cluster name [primary]: ' CLUSTER_NAME
read -p 'Enter region ['${TEMP_REGION}']: ' AWS_REGION
read -p 'Enter Role ARN of cluster creator ['${TEMP_ROLEARN}']: ' AWS_ROLEARN
CLUSTER_NAME=${CLUSTER_NAME:-primary}
AWS_REGION=${AWS_REGION:-${TEMP_REGION}}
AWS_ROLEARN=${AWS_ROLEARN:-${TEMP_ROLEARN}}
AWS_ROLENAME=`echo $AWS_ROLEARN|awk -F/ '{print $2}'`

# Set region
echo Setting region to $AWS_REGION
aws configure set region $AWS_REGION

echo  Altering the role associated with the Cloud9 EC2 instance.  Have it match the role that created the cluster.
aws ec2 associate-iam-instance-profile --instance-id $INSTANCE_ID --iam-instance-profile Name=$AWS_ROLENAME
 
echo  Disable Cloud9s Managed Credentials.  They are incompatible with identies known to the EKS Cluster
aws cloud9 update-environment --environment-id $C9_PID --managed-credentials-action DISABLE

# Kubectl
if ! command -v kubectl &> /dev/null
then
    echo Installing Kubectl
    # curl --silent -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.23.13/2022-10-31/bin/linux/amd64/kubectl 
    # curl --silent -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.27.4/2023-08-16/bin/linux/amd64/kubectl
    curl --silent -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.28.3/2023-11-14/bin/linux/amd64/kubectl

    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin
else
    echo Looks like kubectl is already installed.
fi
kubectl version --client

# Configure kubeconfig
echo Configuring kubeconfig file for cluster $CLUSTER_NAME
# Should use the credentials of the instance to avoid IAM Role self-assume
aws eks update-kubeconfig --name $CLUSTER_NAME --alias admin --region $AWS_REGION
#aws eks update-kubeconfig --name $CLUSTER_NAME --role-arn $AWS_ROLEARN --alias admin --region $AWS_REGION
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
