# Prometheus, Grafana, ADOT setup for EKS

The scripts here provide a fast, easy way to get a basic setup for AWS Distribution for Open Telemetry, Prometheus, and Grafana on an EKS Cluster.  Once script to set it up, one script to tear it down.

## Prerequisites
These scripts assume:
* A running cluster
* A CLI environment with kubectl connected to it.
* Helm installed.

## Setup
Run

```
chmod +x setup.sh
./setup.sh
```
...to setup everything.  It will:
* Establish a new namespace called *monitoring*
* Install the ADOT components as a daemonset in this namespace.
* Use Helm to install Prometheus in this namespace to accept these metrics
* Use Helm to install Grafana in this namespace to display
* Print out the URL, username, and password needed to open Grafana in a browser.
* Provide some ideas for Grafana dashboards you can import.

## Caveats
Prometheus and Grafana really should be run with the EBS-CSI plugin established to allow them to persist data.  However to keep things just a bit simpler I've left that out (for now).

## Sample Application
You'll need to run a workload to generate some nice beefy metrics to look at.  If you don't have one try:

```
kubectl apply -f  https://raw.githubusercontent.com/brentley/ecsdemo-frontend/master/kubernetes/deployment.yaml
kubectl apply -f  https://raw.githubusercontent.com/brentley/ecsdemo-frontend/master/kubernetes/service.yaml
kubectl apply -f  https://raw.githubusercontent.com/brentley/ecsdemo-nodejs/master/kubernetes/deployment.yaml
kubectl apply -f  https://raw.githubusercontent.com/brentley/ecsdemo-nodejs/master/kubernetes/service.yaml
kubectl apply -f  https://raw.githubusercontent.com/brentley/ecsdemo-crystal/master/kubernetes/deployment.yaml
kubectl apply -f  https://raw.githubusercontent.com/brentley/ecsdemo-crystal/master/kubernetes/service.yaml
kubectl scale deployment ecsdemo-nodejs --replicas=3
kubectl scale deployment ecsdemo-crystal --replicas=3
kubectl scale deployment ecsdemo-frontend --replicas=3

```

run the following command to get the URL of the frontend app; may take a moment or two for DNS to piece things together:

```
kubectl get svc
```

Warning: this application uses an elastic load balancer, so make sure you delete the service when finished:

```
kubectl delete svc ecsdemo-frontend
```

## Cleanup
Run the cleanup script to delete everything, especially the Grafana server which uses an (expensive) elastic load balancer:

```
chmod +x cleanup.sh
./cleanup.sh
```


