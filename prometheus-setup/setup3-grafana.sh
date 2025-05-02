helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install grafana grafana/grafana --namespace grafana

kubectl port-forward svc/grafana 3000:80 -n grafana
GRAFANA_PWD=$(kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 -d)

echo "Grafana is available at: http://localhost:3000"
echo "Username: admin"
echo "Password: $GRAFANA_PWD"
