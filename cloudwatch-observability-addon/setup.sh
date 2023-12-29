#
#  This script installs the Amazon CloudWatch Observability Add-On for EKS.
#

ACCOUNT=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep accountId|awk -F\" '{print $4}'`
TEMP_ROLE=primary-EKSNodeRole

read -p 'Enter cluster name [primary]: ' CLUSTER_NAME
read -p 'Enter worker node role name ['${TEMP_ROLE}']: ' AWS_ROLE
CLUSTER_NAME=${CLUSTER_NAME:-primary}
AWS_ROLE=${AWS_ROLE:-${TEMP_ROLE}}

# Be sure the node's role has adequate permissions to run the addon:
aws iam attach-role-policy --role-name $AWS_ROLE --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
aws iam attach-role-policy --role-name $AWS_ROLE --policy-arn arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess

# Install the addon:
# TODO: UNTESTED CODE.  SEE SUPPORT ISSUE 170377686801544
CLUSTER_VERSION=${aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.version' --ouput text}
ADD_ON_VERSION=${aws eks describe-addon-versions --kubernetes-version $CLUSTER_VERSION --addon-name amazon-cloudwatch-observability --query 'addons[].addonVersions[0].addonVersion' --output text}
aws eks create-addon --addon-name amazon-cloudwatch-observability --addon-version $ADD_ON_VERSION --cluster-name $CLUSTER_NAME 
