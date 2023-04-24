#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Set variables
NAMESPACE="prometheus"
S3_BUCKET="piotrprovidersperftest"
S3_FOLDER="prometheus-metrics"
TIMESTAMP=$(date +"%Y-%m-%d-%H-%M-%S")
OUTPUT_FILE="prometheus-metrics-${TIMESTAMP}.tar.gz"

# Get the Prometheus pod name
PROMETHEUS_POD=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')

# Set up port-forwarding
kubectl port-forward -n "${NAMESPACE}" "${PROMETHEUS_POD}" 9090:9090 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!
echo "Port forwarding started with PID: ${PORT_FORWARD_PID}"
sleep 5

# Create a snapshot
SNAPSHOT=$(curl -XPOST "http://localhost:9090/api/v1/admin/tsdb/snapshot" | jq -r '.data.name')
echo "Snapshot created: ${SNAPSHOT}"

# Copy the snapshot to the current directory
echo "Copying snapshot to the current directory..."
kubectl cp -n "${NAMESPACE}" "${PROMETHEUS_POD}:/prometheus/snapshots/${SNAPSHOT}" -c prometheus "./${SNAPSHOT}"

# Compress the snapshot folder
echo "Compressing the snapshot folder..."
tar czf "${OUTPUT_FILE}" "${SNAPSHOT}"

# Upload the compressed snapshot to the S3 bucket
echo "Uploading the compressed snapshot to the S3 bucket..."
aws s3 cp "${OUTPUT_FILE}" "s3://${S3_BUCKET}/${S3_FOLDER}/${OUTPUT_FILE}"

# Clean up
kill "${PORT_FORWARD_PID}" # Stop the port-forward process
rm -rf "${SNAPSHOT}" "${OUTPUT_FILE}"

echo "Prometheus snapshot uploaded to s3://${S3_BUCKET}/${S3_FOLDER}/${OUTPUT_FILE}"
echo "https://s3.console.aws.amazon.com/s3/object/${S3_BUCKET}/${S3_FOLDER}/${OUTPUT_FILE}"
