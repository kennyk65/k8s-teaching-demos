#!/bin/bash
# BASED ON:  https://karpenter.sh/docs/getting-started/
# Use this script with an EXISTING EKS cluster and install Karpenter
TEMP_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`
AWS_ACCOUNT_ID=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep accountId|awk -F\" '{print $4}'`
read -p 'Enter region ['${TEMP_REGION}']: ' AWS_REGION
read -p 'Enter cluster name [primary]: ' CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-primary}
read -p 'Enter nodegroup name ['${CLUSTER_NAME}'-NodeGroup]: ' NODE_GROUP_NAME
#read -p 'Enter a comma-separated list of subnet IDs: ' SUBNET_IDS
read -p 'Enter the name of the IAM role used by the cluster nodes ['${CLUSTER_NAME}'-EKSNodeRole]: ' NODE_ROLE
AWS_REGION=${AWS_REGION:-${TEMP_REGION}}
NODE_ROLE=${NODE_ROLE:-${CLUSTER_NAME}'-EKSNodeRole'}
NODE_GROUP_NAME=${NODE_GROUP_NAME:-${CLUSTER_NAME}'-NodeGroup'}

# Set region
aws configure set region $AWS_REGION

# Get subnets used by existing cluster:
SUBNET_IDS=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name  $NODE_GROUP_NAME --query 'nodegroup.subnets' --output text)
#echo Subnets from API call: $TEMP_SUBNETS

echo 
echo Using values:  
echo Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION, Cluster: $CLUSTER_NAME, NodeGroup: $NODE_GROUP_NAME
echo Subnets: $SUBNET_IDS
echo Node Role: $NODE_ROLE
echo 

# Install Kubectl, if needed.
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
aws eks update-kubeconfig --name $CLUSTER_NAME 

# Install eksctl, if needed.
if ! command -v eksctl &> /dev/null
then
    echo Installing eksctl
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
else
    echo Looks like eksctl is already installed.
fi
eksctl version

# Install Helm, if needed.
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


echo Tagging subnets to be used by karpenter: $SUBNET_IDS
aws ec2 create-tags --resources $SUBNET_IDS --tags Key="kubernetes.io/cluster/${CLUSTER_NAME}",Value=
#aws ec2 create-tags --resources subnet-e58222bc subnet-954347f3 --tags Key="test",Value=    

# Use CloudFormation to quickly create some extra resources:
# Create a managed policy to be used by Karpenter
# Create an instance profile to be used by Karpenter-provisioned EC2 instances:
cat <<EOF > extra-resources-template.yaml
AWSTemplateFormatVersion: 2010-09-09
Resources:
  KarpenterControllerPolicy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: ${CLUSTER_NAME}-KarpenterControllerPolicy
      PolicyDocument:
        Version: 2012-10-17
        Statement:
          - Effect: Allow
            Resource: "*"
            Action:
              # Write Operations
              - ec2:CreateLaunchTemplate
              - ec2:CreateFleet
              - ec2:RunInstances
              - ec2:CreateTags
              - iam:PassRole
              - ec2:TerminateInstances
              # Read Operations
              - ec2:DescribeLaunchTemplates
              - ec2:DescribeInstances
              - ec2:DescribeSecurityGroups
              - ec2:DescribeSubnets
              - ec2:DescribeInstanceTypes
              - ec2:DescribeInstanceTypeOfferings
              - ec2:DescribeAvailabilityZones
              - ssm:GetParameter
  KarpenterInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      InstanceProfileName: ${CLUSTER_NAME}-KarpenterInstanceProfile
      Path: /
      Roles: [ ${NODE_ROLE} ]
EOF
aws cloudformation deploy --stack-name karpenter-${CLUSTER_NAME} --template-file extra-resources-template.yaml   --capabilities CAPABILITY_NAMED_IAM 


echo Enable OpenID Connect on the cluster
eksctl utils associate-iam-oidc-provider --cluster=${CLUSTER_NAME} --approve

echo Create an RBAC service account associated with IAM Role.  It will be used by code in the provisioner to make AWS API calls to facilitate scaling.
eksctl create iamserviceaccount --cluster $CLUSTER_NAME --namespace karpenter --name karpenter  \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/${CLUSTER_NAME}-KarpenterControllerPolicy \
  --approve

echo Install Karpenter itself using Helm:
helm repo add karpenter https://charts.karpenter.sh
helm repo update
helm upgrade --install karpenter karpenter/karpenter --create-namespace --namespace karpenter \
  --set serviceAccount.create=false --version 0.5.0 \
  --set controller.clusterName=${CLUSTER_NAME} \
  --set controller.clusterEndpoint=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.endpoint" --output json) \
  --wait # for the defaulting webhook to install before creating a Provisioner

echo Create a karpenter provisioner.  Note this one is using spot instances:
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot"]
  limits:
    resources:
      cpu: 1000
  provider:
    instanceProfile: ${CLUSTER_NAME}-KarpenterInstanceProfile
  ttlSecondsAfterEmpty: 30
EOF

echo try running the demo-scale-out.sh and demo-scale-in.sh scripts while watching the number of nodes.
sleep 5


