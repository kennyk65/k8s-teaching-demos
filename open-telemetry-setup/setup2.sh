# Setup AWS Distro for OpenTelemetry (ADOT).  
# Based on https://catalog.workshops.aws/eks-immersionday/en-US/monitoring

TEMP_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`
read -p 'Enter region ['${TEMP_REGION}']: ' AWS_REGION
read -p 'Enter cluster name [primary]: ' CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-primary}
AWS_REGION=${AWS_REGION:-${TEMP_REGION}}

# Created AMP workspace
WORKSPACE_ID=$(aws amp create-workspace --alias adot-eks --tags env=workshop --query workspaceId --output text)

sleep 8 # Wait up to 10 seconds for the workspace to become active

#  Setup the OIDC provider on EKS as an identity provider on IAM:
eksctl utils associate-iam-oidc-provider --cluster $EKS_CLUSTER_NAME --approve     

#  Establish a service account matched to IAM Role for pods in the prometheus namespace.
eksctl create iamserviceaccount --name amp-irsa-role --namespace prometheus --cluster $EKS_CLUSTER_NAME --attach-policy-arn arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess --approve --override-existing-serviceaccounts

# install cert-manager as its a pre requisite before installing ADOT -
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml 
kubectl get pods -n cert-manager

# Then I install the ADOT addon in my eks cluster.  First permissions then the addon itself:
kubectl apply -f https://amazon-eks.s3.amazonaws.com/docs/addons-otel-permissions.yaml 
aws eks create-addon --addon-name adot --addon-version v0.74.0-eksbuild.1 --cluster-name $EKS_CLUSTER_NAME
sleep 5 # Wait for addon to activate:
aws eks describe-addon --addon-name adot --cluster-name $EKS_CLUSTER_NAME | jq .addon.status
sleep 5 # previous status should be "ACTIVE"

# Acquire the Endpoint URL for the Prometheus workspace
AMP_ENDPOINT_URL=$(aws amp describe-workspace --workspace-id $WORKSPACE_ID | jq '.workspace.prometheusEndpoint' -r)
AMP_REMOTE_WRITE_URL=${AMP_ENDPOINT_URL}api/v1/remote_write

#  Install the Open Telemetry Collector Custom Resource (CR)
curl -O https://raw.githubusercontent.com/aws-containers/eks-app-mesh-polyglot-demo/master/workshop/otel-collector-config.yaml  

# set region code in the yaml file that is downloaded above -
sed -i -e s/AWS_REGION/$AWS_REGION/g otel-collector-config.yaml

# set AMP remote write URL in the config ymal downloaded above - 
sed -i -e s^AMP_WORKSPACE_URL^$AMP_REMOTE_WRITE_URL^g otel-collector-config.yaml

# Apply, verify:
kubectl apply -f ./otel-collector-config.yaml
kubectl get all -n prometheus
sleep 8 # You should see the observability-collector service, deployment, and pod running

# Verified the AMP metrics using awscurl:
awscurl --service="aps" --region=$AWS_REGION  "${AMP_ENDPOINT_URL}api/v1/query?query=scrape_samples_scraped"