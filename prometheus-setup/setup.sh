# This script installs the ADOT components in a cluster, 
# prometheus to collect them, and grafana to display them.
# Prerequisites:  a running cluster, kubectl already setup to connect to it, and helm.

# Everything will be installed in the new "monitoring" namespace
kubectl create namespace monitoring

# ADOT:
# Install the ADOT components
kubectl apply -f adot-collector.yaml -n monitoring
sleep 4 # ADOT components have been installed.  Now installing Prometheus...

# PROMETHEUS:
# This sets up an in-cluster Prometheus server that you can use for a quick demo
# Based on:  https://docs.aws.amazon.com/eks/latest/userguide/prometheus.html

# TODO: SWITCH DEMO TO USE EBS FOR PERSISTENCE, THEN YOU CAN ADD THIS SAFETY CHECK:
# if ! kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver | grep -q ebs-csi; then
#   echo "❌ AWS EBS CSI Driver is not installed. Aborting script."
#   exit 1
# else
#   echo "✅ AWS EBS CSI Driver is installed."
# fi

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install with persistence disabled; not recommended in production
# TODO: SWITCH OVER TO PERSISTENCE ENABLED AT SOME POINT.
helm install prometheus prometheus-community/prometheus \
  --namespace monitoring --create-namespace \
  --set server.persistentVolume.enabled=false \
  --set alertmanager.persistentVolume.enabled=false \
  -f prometheus-values.yaml

sleep 4 # Prometheus components have been installed.  Now installing Grafana...


# GRAFANA:
# Installing Grafana via helm chart.  Automatically establish prometheus datasource.
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install grafana grafana/grafana --namespace monitoring --create-namespace \
  --set service.type=LoadBalancer \
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
  --set datasources."datasources\.yaml".datasources[0].type=prometheus \
  --set datasources."datasources\.yaml".datasources[0].url=http://prometheus-server.monitoring.svc.cluster.local \
  --set datasources."datasources\.yaml".datasources[0].access=proxy \
  --set datasources."datasources\.yaml".datasources[0].isDefault=true

sleep 4 # waiting a moment for the password to be established...
#kubectl port-forward svc/grafana 3000:80 -n grafana
GRAFANA_PWD=$(kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 -d)
GRAFANA_HOST=$(kubectl get svc -n monitoring grafana -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null)
  

echo "Grafana is available at: http://${GRAFANA_HOST}"
echo "Username: admin"
echo "Password: $GRAFANA_PWD"
echo " "
echo "Once logged in, the prometheus datasource should already be present at: "
echo "  URL: http://prometheus-server.monitoring.svc.cluster.local"
echo "  Name: Prometheus"
echo " "
echo "A good dashboard to start with is: 15336"