# This script will setup the CSI EBS storage driver on the cluster of your choice.
# First it must setup an OIDC provider in IAM for the cluster, if one is not already there
# Prerequisites:  eksctl
# Based on this document:  https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html
# and this:  https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html

ACCOUNT=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep accountId|awk -F\" '{print $4}'`
read -p 'Enter cluster name [primary]: ' CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-primary}


#  See if we already have an OIDC provider setup with IAM for our cluster.
#  Retrieve your cluster's OIDC provider ID and store it in a variable.  Then see if is in the list of IAM OIDC providers already: 
OIDC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
OIDC_PRESENT=$(aws iam list-open-id-connect-providers | grep $OIDC_ID | cut -d "/" -f4)

# TODO - ADD SOME CONDITIONAL LOGIC SO THAT WE DON'T ADD THE OPEN ID CONNECT PROVIDER IF ONE IS ALREADY AVAILABLE, i.e if OIDC_PRESENT IS NOT BLANK.
# Create an OIDC provider for our cluster.
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve

eksctl create iamserviceaccount --name ebs-csi-controller-sa --namespace kube-system --cluster $CLUSTER_NAME --role-name AmazonEKS_EBS_CSI_DriverRole --role-only --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy --approve

eksctl create addon --name aws-ebs-csi-driver --cluster $CLUSTER_NAME --service-account-role-arn arn:aws:iam::$ACCOUNT:role/AmazonEKS_EBS_CSI_DriverRole --force


