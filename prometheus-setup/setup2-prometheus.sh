# This sets up an in-cluster Prometheus server that you can use for a quick demo
# Based on:  https://docs.aws.amazon.com/eks/latest/userguide/prometheus.html
# Requires a running cluster, kubectl already setup to connect to it, helm, and the CSI EBS driver installed.

# if ! kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver | grep -q ebs-csi; then
#   echo "❌ AWS EBS CSI Driver is not installed. Aborting script."
#   exit 1
# else
#   echo "✅ AWS EBS CSI Driver is installed."
# fi


# kubectl create namespace prometheus
# helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# helm upgrade -i prometheus prometheus-community/prometheus --namespace prometheus --set alertmanager.persistentVolume.storageClass="gp2",server.persistentVolume.storageClass="gp2"

# sleep 8 # wait a bit for these pods to start
# kubectl get pods -n prometheus

# # WARNING: THIS IS EXPOSING THE PROMETHEUS SERVER ON THE PUBLIC INTERNET WITH NO AUTHENTICATION
# kubectl expose deployment prometheus-server --port=80 --target-port=9090 --name external --type LoadBalancer -n prometheus
# kubectl get svc -n prometheus 



helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install with persistence disabled; not recommended in production
helm install prometheus prometheus-community/prometheus \
  --namespace prometheus --create-namespace \
  --set server.persistentVolume.enabled=false \
  --set alertmanager.persistentVolume.enabled=false \
  -f prometheus-values.yaml
