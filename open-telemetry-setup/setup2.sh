# Setup AWS Distro for OpenTelemetry (ADOT).  
# Based on https://catalog.workshops.aws/eks-immersionday/en-US/monitoring

TEMP_REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region -s)
read -p 'Enter region ['${TEMP_REGION}']: ' AWS_REGION
read -p 'Enter cluster name [primary]: ' CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-primary}
AWS_REGION=${AWS_REGION:-${TEMP_REGION}}
ACCOUNT_ID=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep accountId|awk -F\" '{print $4}'`

echo
echo Create the Amazon Managed Prometheus workspace
WORKSPACE_ID=$(aws amp create-workspace --alias adot-eks --tags env=workshop --query workspaceId --output text)
sleep 8 # Wait up to 10 seconds for the workspace to become active

echo
echo Setup the OIDC provider on EKS as an identity provider on IAM.  May not be required if already done:
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve     

echo
echo Establish a service account matched to IAM Role for pods in the prometheus namespace.  
eksctl create iamserviceaccount --name amp-irsa-role --namespace prometheus --cluster $CLUSTER_NAME --attach-policy-arn arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess --approve --override-existing-serviceaccounts

echo
echo Install cert-manager as its a pre requisite before installing ADOT.  Allow it a few seconds to start up...
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml 
sleep 8 # May take a moment to start
kubectl get pods -n cert-manager

echo
echo Install the AWS Distribution for Open Telemetry addon in the EKS cluster.  First permissions, then the addon itself.  Ignore errors if this is already added:
kubectl apply -f https://amazon-eks.s3.amazonaws.com/docs/addons-otel-permissions.yaml 
aws eks create-addon --addon-name adot --addon-version v0.74.0-eksbuild.1 --cluster-name $CLUSTER_NAME
echo Allow the addon a few seconds to start.  Ignore any errors about already being installed...
while true; do
    STATUS=$(aws eks describe-addon --addon-name adot --cluster-name $CLUSTER_NAME --output text --query "addon.status")
    echo Status of Open Telemetry AddOn is $STATUS
    if [[ "${STATUS}" == "ACTIVE" ]]; then break; fi
    sleep 1
done

echo
echo Acquire the Endpoint URL for the Prometheus workspace
AMP_ENDPOINT_URL=$(aws amp describe-workspace --workspace-id $WORKSPACE_ID --output text --query 'workspace.prometheusEndpoint')
AMP_ENDPOINT_WRITE_URL=${AMP_ENDPOINT_URL}api/v1/remote_write
AMP_ENDPOINT_QUERY_URL=${AMP_ENDPOINT_URL}api/v1/query
echo Write endpoint for the Prometheus workspace is $AMP_ENDPOINT_WRITE_URL
echo Query endpoint for the Prometheus workspace is $AMP_ENDPOINT_QUERY_URL

echo
echo Install the Open Telemetry Collector Custom Resource.  Customize the region and URL for our cluster and Prometheus workspace
curl -O https://raw.githubusercontent.com/aws-containers/eks-app-mesh-polyglot-demo/master/workshop/otel-collector-config.yaml  
sed -i -e s/AWS_REGION/$AWS_REGION/g otel-collector-config.yaml
sed -i -e s^AMP_WORKSPACE_URL^$AMP_ENDPOINT_WRITE_URL^g otel-collector-config.yaml
kubectl apply -f ./otel-collector-config.yaml
rm ./otel-collector-config.yaml
sleep 4
kubectl get all -n prometheus
echo We should see the observability-collector service, deployment, and pod running

echo
echo Install a Sample App to generate traffic.  
# See https://docs.aws.amazon.com/eks/latest/userguide/sample-app.html
curl -o traffic-generator.yaml https://raw.githubusercontent.com/aws-observability/aws-otel-community/master/sample-configs/traffic-generator.yaml
kubectl apply -f traffic-generator.yaml
rm traffic-generator.yaml
curl -o sample-app.yaml https://raw.githubusercontent.com/aws-observability/aws-otel-community/master/sample-configs/sample-app.yaml
sed -i "s~<YOUR_AWS_REGION>~$AWS_REGION~g" sample-app.yaml
kubectl apply -f sample-app.yaml
rm sample-app.yaml

echo
echo Test using awscurl, which needs to be installed, which requires an update to Python:
curl -O https://bootstrap.pypa.io/pip/3.6/get-pip.py    # Get the OLD 3.6 version of get-pip, required by Cloud9
sudo python3 get-pip.py                             # Install pip for Python 3.6.  This destroys the pre-installed pip
/usr/local/bin/pip install awscurl              # Install awscurl.  pip is no longer available on the path after installation
rm get-pip.py                                # Delete the install script.

echo
echo Verify the AMP metrics using awscurl using  $AMP_ENDPOINT_QUERY_URL?query=scrape_samples_scraped :
awscurl --service=aps --region=$AWS_REGION  $AMP_ENDPOINT_QUERY_URL?query=scrape_samples_scraped


echo 
echo Setup Grafana.  Prepare IAM Role...
cat << EOF > grafana_trust_policy.json
{   "Version": "2012-10-17",
    "Statement": [
        {   "Effect": "Allow",
            "Principal": { "Service": "grafana.amazonaws.com" },
            "Action": "sts:AssumeRole",
            "Condition": { 
                "StringEquals": { "aws:SourceAccount": "${ACCOUNT_ID}" },
                "StringLike": { "aws:SourceArn": "arn:aws:grafana:${AWS_REGION}:${ACCOUNT_ID}:/workspaces/*" }
            }
        }
    ]
}
EOF
cat << EOF > policy.json
{   "Version": "2012-10-17",
    "Statement": [
        {   "Effect": "Allow",
            "Action": [
                "aps:List*",
                "aps:Describe*",
                "aps:Query*",
                "aps:Get*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
aws iam create-role --role-name adot-grafana-role --assume-role-policy-document file://grafana_trust_policy.json
aws iam put-role-policy --role-name adot-grafana-role --policy-name amg-amp-policy --policy-document file://policy.json
echo Setup Grafana.  Create Workspace...
AMG_WORKSPACE_ID=$(aws grafana create-workspace --account-access-type="CURRENT_ACCOUNT" --authentication-providers "AWS_SSO" --permission-type "CUSTOMER_MANAGED" --workspace-name "${CLUSTER_NAME}-amg" --workspace-role-arn "adot-grafana-role" --output text --query "workspace.id")
while true; do
    STATUS=$(aws grafana describe-workspace --workspace-id $AMG_WORKSPACE_ID --output text --query "workspace.status")
    if [[ "${STATUS}" == "ACTIVE" ]]; then break; fi
    sleep 1
    echo -n '.'
done
export AMG_WORKSPACE_ENDPOINT=$(aws grafana describe-workspace --workspace-id $AMG_WORKSPACE_ID --output text --query "workspace.endpoint" )
echo Grafana Workspace Endpoint is $AMG_WORKSPACE_ENDPOINT


