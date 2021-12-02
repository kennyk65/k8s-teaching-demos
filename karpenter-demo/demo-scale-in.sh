#!/bin/bash
# Demonstrate scaling in:
kubectl delete deployment inflate
kubectl logs -f -n karpenter $(kubectl get pods -n karpenter -l karpenter=controller -o name)




