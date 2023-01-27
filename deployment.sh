#!/usr/bin/env bash

################################################################################
### Script deploying the Observ-K8s environment
### Parameters:
### Clustern name: name of your k8s cluster
### dttoken: Dynatrace api token with ingest metrics and otlp ingest scope
### dturl : url of your DT tenant wihtout any / at the end for example: https://dedede.live.dynatrace.com
################################################################################


### Pre-flight checks for dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "Please install jq before continuing"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Please install git before continuing"
    exit 1
fi


if ! command -v helm >/dev/null 2>&1; then
    echo "Please install helm before continuing"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "Please install kubectl before continuing"
    exit 1
fi
echo "parsing arguments"
while [ $# -gt 0 ]; do
  case "$1" in
  --dttoken)
    DTTOKEN="$2"
   shift 2
    ;;
  --dturl)
    DTURL="$2"
   shift 2
    ;;
  --clustername)
    CLUSTERNAME="$2"
   shift 2
    ;;
  *)
    echo "Warning: skipping unsupported option: $1"
    shift
    ;;
  esac
done
echo "Checking arguments"
if [ -z "$CLUSTERNAME" ]; then
  echo "Error: clustername not set!"
  exit 1
fi
if [ -z "$DTURL" ]; then
  echo "Error: environment-url not set!"
  exit 1
fi

if [ -z "$DTTOKEN" ]; then
  echo "Error: api-token not set!"
  exit 1
fi



helm upgrade --install ingress-nginx ingress-nginx  --repo https://kubernetes.github.io/ingress-nginx  --namespace ingress-nginx --create-namespace

### get the ip adress of ingress ####
IP=""
while [ -z $IP ]; do
  echo "Waiting for external IP"
  IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -ojson | jq -j '.status.loadBalancer.ingress[].ip')
  [ -z "$IP" ] && sleep 10
done
echo 'Found external IP: '$IP

### Update the ip of the ip adress for the ingres
#TODO to update this part to use the dns entry /ELB/ALB
sed -i "s,IP_TO_REPLACE,$IP," kubernetes-manifests/K8sdemo.yaml
sed -i "s,IP_TO_REPLACE,$IP,"  deployments/ingress.yaml
### Depploy Prometheus

#### Deploy the cert-manager
echo "Deploying Cert Manager ( for OpenTelemetry Operator)"
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.6.1/cert-manager.yaml
# Wait for pod webhook started
kubectl wait pod -l app.kubernetes.io/component=webhook -n cert-manager --for=condition=Ready --timeout=2m
# Deploy the opentelemetry operator
sleep 10
echo "Deploying the OpenTelemetry Operator"
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml


CLUSTERID=$(kubectl get namespace kube-system -o jsonpath='{.metadata.uid}')
sed -i "s,CLUSTER_ID_TOREPLACE,$CLUSTERID," kubernetes-manifests/openTelemetry-sidecar.yaml
sed -i "s,CLUSTER_NAME_TO_REPLACE,$CLUSTERNAME," kubernetes-manifests/openTelemetry-sidecar.yaml



#Deploy the OpenTelemetry Collector
echo "Deploying Otel Collector"
kubectl apply -f kubernetes-manifests/rbac.yaml
##update the collector pipeline
sed -i "s,DT_TOKEN_TO_REPLACE,$DTTOKEN," kubernetes-manifests/openTelemetry-manifest.yaml
sed -i "s,DT_URL_TO_REPLACE,$DTURL," kubernetes-manifests/openTelemetry-manifest.yaml
##Deploy the Collector DaemonSet
kubectl apply -f kubernetes-manifests/openTelemetry-manifest.yaml

#install prometheus operator
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack

#DEploying otel demo application
kubectl create ns otel-demo
kubectl apply -f kubernetes-manifests/openTelemetry-sidecar.yaml -n otel-demo
kubectl apply -f kubernetes-manifests/openTelemetry-manifest.yaml -n otel-demo


#Deploy qlkube
kubectl create ns qlkube
kubectl apply -f kubernetes-manifests/openTelemetry-sidecar.yaml -n qlkube
kubectl apply -f deployments/deployment.yaml -n qlkube
kubectl apply -f  deployments/ingress.yaml -n qlkube
# Echo environ*
echo "--------------Demo--------------------"
echo "url of the demo: "
echo "Otel demo url: http://otel-demo.$IP.nip.io"
echo "Otel demo url: http://qlkube.$IP.nip.io"
echo "========================================================"


