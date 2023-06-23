# Setup AWS Distro for OpenTelemetry (ADOT).  
# Based on https://docs.aws.amazon.com/eks/latest/userguide/opentelemetry.html
# TODO:  The Prometheus open telemetry collector install fails with: "error: unable to recognize "collector-config-amp.yaml": no matches for kind "OpenTelemetryCollector" in version "opentelemetry.io/v1alpha1"".  ticket opened.
# TODO:  The CloudWatch collector doesn't produce any metric results, although there are some logs.

TEMP_REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region -s)
read -p 'Enter region ['${TEMP_REGION}']: ' AWS_REGION
read -p 'Enter cluster name [primary]: ' CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-primary}
AWS_REGION=${AWS_REGION:-${TEMP_REGION}}

echo Replacing AWS CLI v1 with v2
pip uninstall awscli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

echo Create Prometheus workspace and get the URL.
WORKSPACE_ID=$(aws amp create-workspace --alias prometheus-workspace --query workspaceId --output text)
WORKSPACE_URL=$(aws amp describe-workspace --workspace-id $WORKSPACE_ID --query workspace.prometheusEndpoint --output text)
WORKSPACE_URL=${WORKSPACE_URL}v1/remote_write
echo The Prometheus workspace URL is $WORKSPACE_URL

echo Prerequisite - Grant permissions to Amazon EKS add-ons to install AWS Distro for OpenTelemetry ADOT:
kubectl apply -f https://amazon-eks.s3.amazonaws.com/docs/addons-otel-permissions.yaml

echo Install Cert Manager:
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml

echo Verify that the Cert manager is ready.  Should see pods running:
kubectl get pod  -n cert-manager

echo Create an IAM OIDC identity provider for your cluster with eksctl
# See https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html
oidc_id=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)

# Determine whether an IAM OIDC provider with your cluster's ID is already in your account.
aws iam list-open-id-connect-providers | grep $oidc_id

echo Create an IAM OIDC identity provider for your cluster 
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve

echo Create IAM Role to support the AWS Distro for OpenTelemetry ADOT
# see https://docs.aws.amazon.com/eks/latest/userguide/adot-iam.html
eksctl create iamserviceaccount --name adot-collector --namespace default --cluster $CLUSTER_NAME \
    --attach-policy-arn arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess \
    --attach-policy-arn arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess \
    --attach-policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
    --approve --override-existing-serviceaccounts

echo Create the AWS Distro for OpenTelemetry ADOT operator
# See https://docs.aws.amazon.com/eks/latest/userguide/adot-manage.html
aws eks create-addon --addon-name adot --cluster-name $CLUSTER_NAME
aws eks describe-addon --addon-name adot --cluster-name $CLUSTER_NAME

echo Deploy Open Telemetry Collector from prometheus.  
# See https://docs.aws.amazon.com/eks/latest/userguide/deploy-deployment.html
cat <<EOF > collector-config-amp.yaml
# OpenTelemetry Collector configuration
# Metrics pipeline with Prometheus Receiver and Prometheus Remote Write Exporter sending metrics to Amazon Managed Prometheus
---
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: my-collector-amp
spec:
  mode: deployment
  serviceAccount: adot-collector
  podAnnotations:
    prometheus.io/scrape: 'true'
    prometheus.io/port: '8888'
  config: |
    extensions:
      sigv4auth:
        region: "$AWS_REGION"
        service: "aps"

    receivers:
      # Scrape configuration for the Prometheus Receiver
      # This is the same configuration used when Prometheus is installed using the community Helm chart
      prometheus:
        config:
          global:
            scrape_interval: 15s
            scrape_timeout: 10s

          scrape_configs:
          - job_name: kubernetes-apiservers
            bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            kubernetes_sd_configs:
            - role: endpoints
            relabel_configs:
            - action: keep
              regex: default;kubernetes;https
              source_labels:
              - __meta_kubernetes_namespace
              - __meta_kubernetes_service_name
              - __meta_kubernetes_endpoint_port_name
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              insecure_skip_verify: true

          - job_name: kubernetes-nodes
            bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            kubernetes_sd_configs:
            - role: node
            relabel_configs:
            - action: labelmap
              regex: __meta_kubernetes_node_label_(.+)
            - replacement: kubernetes.default.svc:443
              target_label: __address__
            - regex: (.+)
              replacement: /api/v1/nodes/$$1/proxy/metrics
              source_labels:
              - __meta_kubernetes_node_name
              target_label: __metrics_path__
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              insecure_skip_verify: true

          - job_name: kubernetes-nodes-cadvisor
            bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            kubernetes_sd_configs:
            - role: node
            relabel_configs:
            - action: labelmap
              regex: __meta_kubernetes_node_label_(.+)
            - replacement: kubernetes.default.svc:443
              target_label: __address__
            - regex: (.+)
              replacement: /api/v1/nodes/$$1/proxy/metrics/cadvisor
              source_labels:
              - __meta_kubernetes_node_name
              target_label: __metrics_path__
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              insecure_skip_verify: true

          - job_name: kubernetes-service-endpoints
            kubernetes_sd_configs:
            - role: endpoints
            relabel_configs:
            - action: keep
              regex: true
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_scrape
            - action: replace
              regex: (https?)
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_scheme
              target_label: __scheme__
            - action: replace
              regex: (.+)
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_path
              target_label: __metrics_path__
            - action: replace
              regex: ([^:]+)(?::\d+)?;(\d+)
              replacement: $$1:$$2
              source_labels:
              - __address__
              - __meta_kubernetes_service_annotation_prometheus_io_port
              target_label: __address__
            - action: labelmap
              regex: __meta_kubernetes_service_annotation_prometheus_io_param_(.+)
              replacement: __param_$$1
            - action: labelmap
              regex: __meta_kubernetes_service_label_(.+)
            - action: replace
              source_labels:
              - __meta_kubernetes_namespace
              target_label: kubernetes_namespace
            - action: replace
              source_labels:
              - __meta_kubernetes_service_name
              target_label: kubernetes_name
            - action: replace
              source_labels:
              - __meta_kubernetes_pod_node_name
              target_label: kubernetes_node

          - job_name: kubernetes-service-endpoints-slow
            kubernetes_sd_configs:
            - role: endpoints
            relabel_configs:
            - action: keep
              regex: true
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_scrape_slow
            - action: replace
              regex: (https?)
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_scheme
              target_label: __scheme__
            - action: replace
              regex: (.+)
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_path
              target_label: __metrics_path__
            - action: replace
              regex: ([^:]+)(?::\d+)?;(\d+)
              replacement: $$1:$$2
              source_labels:
              - __address__
              - __meta_kubernetes_service_annotation_prometheus_io_port
              target_label: __address__
            - action: labelmap
              regex: __meta_kubernetes_service_annotation_prometheus_io_param_(.+)
              replacement: __param_$$1
            - action: labelmap
              regex: __meta_kubernetes_service_label_(.+)
            - action: replace
              source_labels:
              - __meta_kubernetes_namespace
              target_label: kubernetes_namespace
            - action: replace
              source_labels:
              - __meta_kubernetes_service_name
              target_label: kubernetes_name
            - action: replace
              source_labels:
              - __meta_kubernetes_pod_node_name
              target_label: kubernetes_node
            scrape_interval: 5m
            scrape_timeout: 30s
            
          - job_name: prometheus-pushgateway
            kubernetes_sd_configs:
            - role: service
            relabel_configs:
            - action: keep
              regex: pushgateway
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_probe

          - job_name: kubernetes-services
            kubernetes_sd_configs:
            - role: service
            metrics_path: /probe
            params:
              module:
              - http_2xx
            relabel_configs:
            - action: keep
              regex: true
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_probe
            - source_labels:
              - __address__
              target_label: __param_target
            - replacement: blackbox
              target_label: __address__
            - source_labels:
              - __param_target
              target_label: instance
            - action: labelmap
              regex: __meta_kubernetes_service_label_(.+)
            - source_labels:
              - __meta_kubernetes_namespace
              target_label: kubernetes_namespace
            - source_labels:
              - __meta_kubernetes_service_name
              target_label: kubernetes_name

          - job_name: kubernetes-pods
            kubernetes_sd_configs:
            - role: pod
            relabel_configs:
            - action: keep
              regex: true
              source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_scrape
            - action: replace
              regex: (https?)
              source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_scheme
              target_label: __scheme__
            - action: replace
              regex: (.+)
              source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_path
              target_label: __metrics_path__
            - action: replace
              regex: ([^:]+)(?::\d+)?;(\d+)
              replacement: $$1:$$2
              source_labels:
              - __address__
              - __meta_kubernetes_pod_annotation_prometheus_io_port
              target_label: __address__
            - action: labelmap
              regex: __meta_kubernetes_pod_annotation_prometheus_io_param_(.+)
              replacement: __param_$$1
            - action: labelmap
              regex: __meta_kubernetes_pod_label_(.+)
            - action: replace
              source_labels:
              - __meta_kubernetes_namespace
              target_label: kubernetes_namespace
            - action: replace
              source_labels:
              - __meta_kubernetes_pod_name
              target_label: kubernetes_pod_name
            - action: drop
              regex: Pending|Succeeded|Failed|Completed
              source_labels:
              - __meta_kubernetes_pod_phase

          - job_name: kubernetes-pods-slow
            scrape_interval: 5m
            scrape_timeout: 30s          
            kubernetes_sd_configs:
            - role: pod
            relabel_configs:
            - action: keep
              regex: true
              source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_scrape_slow
            - action: replace
              regex: (https?)
              source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_scheme
              target_label: __scheme__
            - action: replace
              regex: (.+)
              source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_path
              target_label: __metrics_path__
            - action: replace
              regex: ([^:]+)(?::\d+)?;(\d+)
              replacement: $$1:$$2
              source_labels:
              - __address__
              - __meta_kubernetes_pod_annotation_prometheus_io_port
              target_label: __address__
            - action: labelmap
              regex: __meta_kubernetes_pod_annotation_prometheus_io_param_(.+)
              replacement: __param_$1
            - action: labelmap
              regex: __meta_kubernetes_pod_label_(.+)
            - action: replace
              source_labels:
              - __meta_kubernetes_namespace
              target_label: namespace
            - action: replace
              source_labels:
              - __meta_kubernetes_pod_name
              target_label: pod
            - action: drop
              regex: Pending|Succeeded|Failed|Completed
              source_labels:
              - __meta_kubernetes_pod_phase
                                
    processors:
      batch/metrics:
        timeout: 60s         

    exporters:
      prometheusremotewrite:
        endpoint: $WORKSPACE_URL
        auth:
          authenticator: sigv4auth

    service:
      extensions: [sigv4auth]
      pipelines:   
        metrics:
          receivers: [prometheus]
          processors: [batch/metrics]
          exporters: [prometheusremotewrite]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: otel-prometheus-role
rules:
  - apiGroups:
      - ""
    resources:
      - nodes
      - nodes/proxy
      - services
      - endpoints
      - pods
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - extensions
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
  - nonResourceURLs:
      - /metrics
    verbs:
      - get

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: otel-prometheus-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: otel-prometheus-role
subjects:
  - kind: ServiceAccount
    name: adot-collector
    namespace: default
EOF
kubectl apply -f collector-config-amp.yaml 


echo Deploy the AWS Distro for OpenTelemetry Collector for CloudWatch
# See https://docs.aws.amazon.com/eks/latest/userguide/configure-cw.html
cat <<EOF > collector-config-cw.yaml
# OpenTelemetry Collector configuration
# Metrics pipeline with Prometheus Receiver and Amazon CloudWatch EMF Exporter sending metrics to Amazon CloudWatch
---
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: my-collector-cloudwatch
spec:
  mode: deployment
  serviceAccount: adot-collector
  podAnnotations:
    prometheus.io/scrape: 'true'
    prometheus.io/port: '8888'
  env:
    - name: CLUSTER_NAME
      value: $CLUSTER_NAME
  config: |
    receivers:
      # Scrape configuration for the Prometheus Receiver
      # This is the same configuration used when Prometheus is installed using the community Helm chart
      prometheus:
        config:
          global:
            scrape_interval: 15s
            scrape_timeout: 10s

          scrape_configs:
          - job_name: kubernetes-apiservers
            bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            kubernetes_sd_configs:
            - role: endpoints
            relabel_configs:
            - action: keep
              regex: default;kubernetes;https
              source_labels:
              - __meta_kubernetes_namespace
              - __meta_kubernetes_service_name
              - __meta_kubernetes_endpoint_port_name
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              insecure_skip_verify: true

          - job_name: kubernetes-nodes
            bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            kubernetes_sd_configs:
            - role: node
            relabel_configs:
            - action: labelmap
              regex: __meta_kubernetes_node_label_(.+)
            - replacement: kubernetes.default.svc:443
              target_label: __address__
            - regex: (.+)
              replacement: /api/v1/nodes/$$1/proxy/metrics
              source_labels:
              - __meta_kubernetes_node_name
              target_label: __metrics_path__
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              insecure_skip_verify: true

          - job_name: kubernetes-nodes-cadvisor
            bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            kubernetes_sd_configs:
            - role: node
            relabel_configs:
            - action: labelmap
              regex: __meta_kubernetes_node_label_(.+)
            - replacement: kubernetes.default.svc:443
              target_label: __address__
            - regex: (.+)
              replacement: /api/v1/nodes/$$1/proxy/metrics/cadvisor
              source_labels:
              - __meta_kubernetes_node_name
              target_label: __metrics_path__
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              insecure_skip_verify: true

          - job_name: kubernetes-service-endpoints
            kubernetes_sd_configs:
            - role: endpoints
            relabel_configs:
            - action: keep
              regex: true
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_scrape
            - action: replace
              regex: (https?)
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_scheme
              target_label: __scheme__
            - action: replace
              regex: (.+)
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_path
              target_label: __metrics_path__
            - action: replace
              regex: ([^:]+)(?::\d+)?;(\d+)
              replacement: $$1:$$2
              source_labels:
              - __address__
              - __meta_kubernetes_service_annotation_prometheus_io_port
              target_label: __address__
            - action: labelmap
              regex: __meta_kubernetes_service_annotation_prometheus_io_param_(.+)
              replacement: __param_$$1
            - action: labelmap
              regex: __meta_kubernetes_service_label_(.+)
            - action: replace
              source_labels:
              - __meta_kubernetes_namespace
              target_label: kubernetes_namespace
            - action: replace
              source_labels:
              - __meta_kubernetes_service_name
              target_label: kubernetes_name
            - action: replace
              source_labels:
              - __meta_kubernetes_pod_node_name
              target_label: kubernetes_node

          - job_name: kubernetes-service-endpoints-slow
            kubernetes_sd_configs:
            - role: endpoints
            relabel_configs:
            - action: keep
              regex: true
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_scrape_slow
            - action: replace
              regex: (https?)
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_scheme
              target_label: __scheme__
            - action: replace
              regex: (.+)
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_path
              target_label: __metrics_path__
            - action: replace
              regex: ([^:]+)(?::\d+)?;(\d+)
              replacement: $$1:$$2
              source_labels:
              - __address__
              - __meta_kubernetes_service_annotation_prometheus_io_port
              target_label: __address__
            - action: labelmap
              regex: __meta_kubernetes_service_annotation_prometheus_io_param_(.+)
              replacement: __param_$$1
            - action: labelmap
              regex: __meta_kubernetes_service_label_(.+)
            - action: replace
              source_labels:
              - __meta_kubernetes_namespace
              target_label: kubernetes_namespace
            - action: replace
              source_labels:
              - __meta_kubernetes_service_name
              target_label: kubernetes_name
            - action: replace
              source_labels:
              - __meta_kubernetes_pod_node_name
              target_label: kubernetes_node
            scrape_interval: 5m
            scrape_timeout: 30s
            
          - job_name: prometheus-pushgateway
            kubernetes_sd_configs:
            - role: service
            relabel_configs:
            - action: keep
              regex: pushgateway
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_probe

          - job_name: kubernetes-services
            kubernetes_sd_configs:
            - role: service
            metrics_path: /probe
            params:
              module:
              - http_2xx
            relabel_configs:
            - action: keep
              regex: true
              source_labels:
              - __meta_kubernetes_service_annotation_prometheus_io_probe
            - source_labels:
              - __address__
              target_label: __param_target
            - replacement: blackbox
              target_label: __address__
            - source_labels:
              - __param_target
              target_label: instance
            - action: labelmap
              regex: __meta_kubernetes_service_label_(.+)
            - source_labels:
              - __meta_kubernetes_namespace
              target_label: kubernetes_namespace
            - source_labels:
              - __meta_kubernetes_service_name
              target_label: kubernetes_name

          - job_name: kubernetes-pods
            kubernetes_sd_configs:
            - role: pod
            relabel_configs:
            - action: keep
              regex: true
              source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_scrape
            - action: replace
              regex: (https?)
              source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_scheme
              target_label: __scheme__
            - action: replace
              regex: (.+)
              source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_path
              target_label: __metrics_path__
            - action: replace
              regex: ([^:]+)(?::\d+)?;(\d+)
              replacement: $$1:$$2
              source_labels:
              - __address__
              - __meta_kubernetes_pod_annotation_prometheus_io_port
              target_label: __address__
            - action: labelmap
              regex: __meta_kubernetes_pod_annotation_prometheus_io_param_(.+)
              replacement: __param_$$1
            - action: labelmap
              regex: __meta_kubernetes_pod_label_(.+)
            - action: replace
              source_labels:
              - __meta_kubernetes_namespace
              target_label: kubernetes_namespace
            - action: replace
              source_labels:
              - __meta_kubernetes_pod_name
              target_label: kubernetes_pod_name
            - action: drop
              regex: Pending|Succeeded|Failed|Completed
              source_labels:
              - __meta_kubernetes_pod_phase
              
          - job_name: kubernetes-pods-slow
            scrape_interval: 5m
            scrape_timeout: 30s          
            kubernetes_sd_configs:
            - role: pod
            relabel_configs:
            - action: keep
              regex: true
              source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_scrape_slow
            - action: replace
              regex: (https?)
              source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_scheme
              target_label: __scheme__
            - action: replace
              regex: (.+)
              source_labels:
              - __meta_kubernetes_pod_annotation_prometheus_io_path
              target_label: __metrics_path__
            - action: replace
              regex: ([^:]+)(?::\d+)?;(\d+)
              replacement: $$1:$$2
              source_labels:
              - __address__
              - __meta_kubernetes_pod_annotation_prometheus_io_port
              target_label: __address__
            - action: labelmap
              regex: __meta_kubernetes_pod_annotation_prometheus_io_param_(.+)
              replacement: __param_$1
            - action: labelmap
              regex: __meta_kubernetes_pod_label_(.+)
            - action: replace
              source_labels:
              - __meta_kubernetes_namespace
              target_label: namespace
            - action: replace
              source_labels:
              - __meta_kubernetes_pod_name
              target_label: pod
            - action: drop
              regex: Pending|Succeeded|Failed|Completed
              source_labels:
              - __meta_kubernetes_pod_phase              
                                                            
    processors:
      batch/metrics:
        timeout: 60s
      # Processor to transform the names of existing labels and/or add new labels to the metrics identified
      metricstransform/labelling:
        transforms:
          - include: .*
            match_type: regexp
            action: update
            operations:
              - action: add_label
                new_label: EKS_Cluster
                new_value: ${CLUSTER_NAME}
              - action: update_label
                label: kubernetes_pod_name
                new_label: EKS_PodName
              - action: update_label
                label: kubernetes_namespace
                new_label: EKS_Namespace               

    exporters:
      # AWS EMF exporter that sends metrics data as performance log events to Amazon CloudWatch
      # Only the metrics that were filtered out by the processors get to this stage of the pipeline
      # Under the metric_declarations field, add one or more sets of Amazon CloudWatch dimensions
      # Each dimension must alredy exist as a label on the Prometheus metric
      # For each set of dimensions, add a list of metrics under the metric_name_selectors field
      # Metrics names may be listed explicitly or using regular expressions
      # A default list of metrics has been provided
      # Data from performance log events will be aggregated by Amazon CloudWatch using these dimensions to create an Amazon CloudWatch custom metric
      awsemf:
        region: "$AWS_REGION"
        namespace: ContainerInsights/Prometheus
        log_group_name: '/aws/containerinsights/${CLUSTER_NAME}/prometheus'
        resource_to_telemetry_conversion:
          enabled: true
        dimension_rollup_option: NoDimensionRollup
        parse_json_encoded_attr_values: [Sources, kubernetes]
        metric_declarations:
          - dimensions: [[EKS_Cluster, EKS_Namespace, EKS_PodName]]
            metric_name_selectors:
              - apiserver_request_.*
              - container_memory_.*
              - container_threads
              - otelcol_process_.*
    service:
      pipelines:
        metrics:
          receivers: [prometheus]
          processors: [batch/metrics,metricstransform/labelling]
          exporters: [awsemf]         
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: otel-prometheus-role
rules:
  - apiGroups:
      - ""
    resources:
      - nodes
      - nodes/proxy
      - services
      - endpoints
      - pods
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - extensions
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
  - nonResourceURLs:
      - /metrics
    verbs:
      - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: otel-prometheus-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: otel-prometheus-role
subjects:
  - kind: ServiceAccount
    name: adot-collector
    namespace: default
EOF
kubectl apply -f collector-config-cw.yaml 

echo Install a Sample App to generate traffic.  
# See https://docs.aws.amazon.com/eks/latest/userguide/sample-app.html
curl -o traffic-generator.yaml https://raw.githubusercontent.com/aws-observability/aws-otel-community/master/sample-configs/traffic-generator.yaml
kubectl apply -f traffic-generator.yaml
curl -o sample-app.yaml https://raw.githubusercontent.com/aws-observability/aws-otel-community/master/sample-configs/sample-app.yaml
sed -i "s~<YOUR_AWS_REGION>~$AWS_REGION~g" sample-app.yaml
kubectl apply -f sample-app.yaml


echo Verify that any of this is working
pip3 install awscurl 
awscurl --service="aps" --region="$AWS_REGION" "https://aps-workspaces.$AWS_REGION.amazonaws.com/workspaces/$WORKSPACE_ID/api/v1/query?query=20 "

awscurl -X POST --region $AWS_REGION --service aps "https://aps-workspaces.$AWS_REGION.amazonaws.com/workspaces/$WORKSPACE_ID/api/v1/query?query=20"
                                                    https://aps-workspaces.us-west-2.amazonaws.com/workspaces/ws-85d2551d-ec3a-44ab-8870-7ae9d05a3372/api/v1/query