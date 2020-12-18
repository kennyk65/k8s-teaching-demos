# Cloud9 Setup
This script is for setting up an AWS Cloud9 environment to work with an EKS Cluster.  It assumes you have created an EKS cluster, and a Cloud9 environment, with a template like https://github.com/kennyk65/aws-teaching-demos/blob/master/cloud-formation-demos/my-eks-cluster-plus-bastion.template.yml


1.  You must MANUALLY turn off Cloud9 managed credentials.  Go to AWS Cloud9 —> Preferences (setting button present at the right hand top corner of the IDE) —> AWS Settings —> Credentials.  Turn these off.

2.  You must MANUALLY associate a role like EksClusterCreatorRole with Cloud9's backing EC2 instance.  The role should be whatever you created the cluster with.

3.  If not already done, clone this entire github repo into the cloud9 environment (the template above does this).  This will include the readme file you are reading now:

git clone https://github.com/kennyk65/k8s-teaching-demos

4.  Find the cloud9-setup.sh and give it execute permissions:

chmod +x cloud9-setup.sh

5.  Run this script.  It should setup eksctl, kubectl, and setup a connection profile for your cluster

./cloud9-setup.sh
