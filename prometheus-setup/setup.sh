# This sets up an in-cluster Prometheus server that you can use for a quick demo
# Based on:  https://docs.aws.amazon.com/eks/latest/userguide/prometheus.html
# Requires a running cluster, kubectl already setup to connect to it.

kubectl create namespace prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade -i prometheus prometheus-community/prometheus --namespace prometheus --set alertmanager.persistentVolume.storageClass="gp2",server.persistentVolume.storageClass="gp2"
kubectl get pods -n prometheus
kubectl --namespace=prometheus port-forward deploy/prometheus-server 9090

# point a web browser to http://localhost:9090