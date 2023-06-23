
# NOTE: This Grafana setup will only work if you are using Identity Center for SSO to AWS accounts

AWS_REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region -s)
ACCOUNT_ID=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep accountId|awk -F\" '{print $4}'`
CLUSTER_NAME=primary
IDENTITY_STORE_ID=$(aws sso-admin list-instances --output text --query Instances[0].IdentityStoreId)
read -p 'Enter Identity Store ID ['${IDENTITY_STORE_ID}']: ' IDENTITY_STORE_ID
echo $IDENTITY_STORE_ID


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
echo Setup Grafana.  Create Workspace, this may take a few minutes...
AMG_WORKSPACE_ID=$(aws grafana create-workspace --account-access-type="CURRENT_ACCOUNT" --authentication-providers "AWS_SSO" --permission-type "CUSTOMER_MANAGED" --workspace-name "${CLUSTER_NAME}-amg" --workspace-role-arn "adot-grafana-role" --output text --query "workspace.id")
echo -n 'Grafana workspace ID is $AMG_WORKSPACE_ID.  Waiting for workspace to become active ... '
while true; do
    STATUS=$(aws grafana describe-workspace --workspace-id $AMG_WORKSPACE_ID --output text --query "workspace.status")
    if [[ "${STATUS}" == "ACTIVE" ]]; then break; fi
    sleep 1
    echo -n '.'
done

export AMG_WORKSPACE_ENDPOINT=$(aws grafana describe-workspace --workspace-id $AMG_WORKSPACE_ID --output text --query "workspace.endpoint" )
echo Grafana Workspace Endpoint is $AMG_WORKSPACE_ENDPOINT

# TODO:  DETERMINE HOW TO ASSOCIATE GRAFANA WITH IDENTITY CENTER USER OR GROUP.  opened support ticket
# TODO:  DETERMINE HOW TO GET GRAFANA PLUGGED INTO PROMETHEUS SERVER.  opened support ticket
# TODO:  TEST THIS
IDENTITY_CENTER_GROUP=$(aws identitystore list-groups --identity-store-id $IDENTITY_STORE_ID --output text --query "Groups[?contains(DisplayName,'main')].GroupId")
aws grafana update-permissions --workspace-id $AMG_WORKSPACE_ID --update-instruction-batch action=ADD,role=ADMIN,users=[{id=$IDENTITY_CENTER_GROUP,type=SSO_GROUP}]
aws grafana update-permissions --workspace-id $AMG_WORKSPACE_ID --update-instruction-batch "[{\"action\":\"ADD\",\"role\":\"ADMIN\",\"users\":[{\"id\":\"$IDENTITY_CENTER_GROUP\",\"type\":\"SSO_GROUP\"}]}]"
