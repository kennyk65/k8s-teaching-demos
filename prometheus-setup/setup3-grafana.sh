helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install grafana grafana/grafana --namespace grafana --create-namespace \
  --set service.type=LoadBalancer \
  --set dashboardsProvider.enabled=true \
  --set dashboards.default.all-pods-per-namespace.gnetId=15336 \
  --set dashboards.default.all-pods-per-namespace.revision=1 \
  --set dashboards.default.all-pods-per-namespace.datasource="Prometheus" \  
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
  --set datasources."datasources\.yaml".datasources[0].type=prometheus \
  --set datasources."datasources\.yaml".datasources[0].url=http://prometheus-server.prometheus.svc.cluster.local \
  --set datasources."datasources\.yaml".datasources[0].access=proxy \
  --set datasources."datasources\.yaml".datasources[0].isDefault=true

sleep 4 # waiting a moment for the password to be established...
#kubectl port-forward svc/grafana 3000:80 -n grafana
GRAFANA_PWD=$(kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 -d)
GRAFANA_HOST=$(kubectl get svc -n grafana grafana -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null)
  

echo "Grafana is available at: http://${GRAFANA_HOST}"
echo "Username: admin"
echo "Password: $GRAFANA_PWD"
echo " "
echo "Once logged in, add prometheus as a datasource."
echo "  URL: http://prometheus-server.prometheus.svc.cluster.local"
echo "  Name: Prometheus"

