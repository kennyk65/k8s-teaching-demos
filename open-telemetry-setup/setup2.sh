# Setup AWS Distro for OpenTelemetry (ADOT).  
# Based on https://catalog.workshops.aws/eks-immersionday/en-US/monitoring

TEMP_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`
read -p 'Enter region ['${TEMP_REGION}']: ' AWS_REGION
read -p 'Enter cluster name [primary]: ' CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-primary}
AWS_REGION=${AWS_REGION:-${TEMP_REGION}}

echo Creat the Amazon Managed Prometheus workspace
WORKSPACE_ID=$(aws amp create-workspace --alias adot-eks --tags env=workshop --query workspaceId --output text)
sleep 8 # Wait up to 10 seconds for the workspace to become active

echo Setup the OIDC provider on EKS as an identity provider on IAM:
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve     

echo Establish a service account matched to IAM Role for pods in the prometheus namespace.  May not be required if already done.
eksctl create iamserviceaccount --name amp-irsa-role --namespace prometheus --cluster $CLUSTER_NAME --attach-policy-arn arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess --approve --override-existing-serviceaccounts

echo Install cert-manager as its a pre requisite before installing ADOT -
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml 
kubectl get pods -n cert-manager

echo Install the AWS Distrobution for Open Telemetry addon in the EKS cluster.  First permissions, then the addon itself:
kubectl apply -f https://amazon-eks.s3.amazonaws.com/docs/addons-otel-permissions.yaml 
aws eks create-addon --addon-name adot --addon-version v0.74.0-eksbuild.1 --cluster-name $CLUSTER_NAME
sleep 5 # Wait for addon to activate:
aws eks describe-addon --addon-name adot --cluster-name $CLUSTER_NAME --output text --query "addon.status"
sleep 5 # previous status should be "ACTIVE"

echo Acquire the Endpoint URL for the Prometheus workspace
AMP_ENDPOINT_URL=$(aws amp describe-workspace --workspace-id $WORKSPACE_ID --output text --query 'workspace.prometheusEndpoint')
AMP_REMOTE_WRITE_URL=${AMP_ENDPOINT_URL}api/v1/remote_write
echo Endpoint for the Prometheus workspace is $AMP_REMOTE_WRITE_URL

echo Install the Open Telemetry Collector Custom Resource.  Customize the region and URL for our cluster and Prometheus workspace
curl -O https://raw.githubusercontent.com/aws-containers/eks-app-mesh-polyglot-demo/master/workshop/otel-collector-config.yaml  
sed -i -e s/AWS_REGION/$AWS_REGION/g otel-collector-config.yaml
sed -i -e s^AMP_WORKSPACE_URL^$AMP_REMOTE_WRITE_URL^g otel-collector-config.yaml
kubectl apply -f ./otel-collector-config.yaml
sleep 4
kubectl get all -n prometheus
echo We should see the observability-collector service, deployment, and pod running

echo Test using awscurl, which needs to be installed, which requires an update to Python:
curl -O https://bootstrap.pypa.io/pip/3.6/get-pip.py    # Get the OLD 3.6 version of get-pip, required by Cloud9
sudo python3 get-pip.py                             # Install pip for Python 3.6.  This destroys the pre-installed pip
/usr/local/bin/pip install awscurl              # Install awscurl
rm get-pip.py                                # Delete the install script.

echo Verify the AMP metrics using awscurl:
awscurl --service="aps" --region=$AWS_REGION  "${AMP_ENDPOINT_URL}api/v1/query?query=scrape_samples_scraped"