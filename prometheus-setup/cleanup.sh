# Delete everything in the reverse order in which is was created.
helm delete grafana -n monitoring
helm delete prometheus -n monitoring
kubectl delete -f adot-collector.yaml -n monitoring
kubectl delete namespace monitoring