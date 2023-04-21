#!/usr/bin/env python3
import os
import time
import json
from datetime import datetime
import boto3
import requests
from kubernetes import config, client

# Set variables
NAMESPACE = "prometheus"
PROMETHEUS_POD_LABEL = "app.kubernetes.io/name=prometheus"
S3_BUCKET = "piotrprovidersperftest"
S3_FOLDER = "prometheus-metrics"
TIMESTAMP = datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
OUTPUT_FILE = f"prometheus-metrics-{TIMESTAMP}.json"

# Load kubeconfig and get the Prometheus pod name
config.load_kube_config()
v1 = client.CoreV1Api()
pods = v1.list_namespaced_pod(NAMESPACE, label_selector=PROMETHEUS_POD_LABEL).items
prometheus_pod = pods[0].metadata.name if pods else None

if not prometheus_pod:
    print(f"No pod found with label {PROMETHEUS_POD_LABEL} in namespace {NAMESPACE}")
    exit(1)

# Port-forward Prometheus pod to access its API
port_forward_command = f"kubectl port-forward -n {NAMESPACE} {prometheus_pod} 9090:9090 > /dev/null 2>&1 &"
os.system(port_forward_command)

# Wait for port-forwarding to establish
time.sleep(5)

# Get the list of all metric names
response = requests.get("http://localhost:9090/api/v1/query", params={"query": 'count({__name__=~".+"}) by (__name__)'})
metric_names = [result["metric"]["__name__"] for result in response.json()["data"]["result"]]

# Download all metrics with their labels
all_metrics = []
for metric_name in metric_names:
    response = requests.get("http://localhost:9090/api/v1/query", params={"query": metric_name})
    all_metrics.extend(response.json()["data"]["result"])

# Save metrics to a file
with open(OUTPUT_FILE, "w") as f:
    json.dump(all_metrics, f)

# Upload the metrics to the S3 bucket
s3 = boto3.client("s3")
s3.upload_file(OUTPUT_FILE, S3_BUCKET, f"{S3_FOLDER}/{OUTPUT_FILE}")

# Clean up
os.system("pkill -f 'kubectl port-forward'")  # Stop the port-forward process
os.remove(OUTPUT_FILE)

print(f"Prometheus metrics downloaded and uploaded to s3://{S3_BUCKET}/{S3_FOLDER}/{OUTPUT_FILE}")
