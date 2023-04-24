#!/bin/bash
set -e

# Function to download Prometheus binary depending on the OS
download_prometheus() {
	local os=$1
	local arch=$2
	local prom_version="2.33.0"

	case $os in
	"linux" | "darwin" | "windows")
		echo "Downloading Prometheus for $os-$arch..."
		curl -LO "https://github.com/prometheus/prometheus/releases/download/v$prom_version/prometheus-$prom_version.$os-$arch.tar.gz"
		;;
	*)
		echo "Unsupported OS: $os"
		exit 1
		;;
	esac
}

# Function to extract tar.gz files
extract_tar_gz() {
	local tar_file=$1
	echo "Extracting $tar_file..."
	tar -xzvf "$tar_file"
}

# Function to download a tar.gz file from an S3 bucket
download_from_s3() {
	local s3_bucket=$1
	local s3_key=$2
	local dest_file=$3

	echo "Downloading $s3_key from $s3_bucket..."
	aws s3 cp "s3://$s3_bucket/$s3_key" "$dest_file"
}

# Main script
os=$(uname | tr '[:upper:]' '[:lower:]')
arch="amd64"

download_prometheus "$os" "$arch"
extract_tar_gz "prometheus-*.$os-$arch.tar.gz"

s3_key = "prometheus-metrics/prometheus-metrics-2023-04-21-19-00-21.tar.gz"
s3_bucket = "piotrprovidersperftest"
s3_folder = "prometheus-metrics"
download_from_s3 "$s3_bucket" "$s3_key" "$archive_name"
extract_tar_gz "$archive_name"

prom_folder=$(find . -type d -iname 'prometheus-*' | head -n 1)
data_folder="$prom_folder/data"

echo "Moving content to the Prometheus data folder..."
mv data/* "$data_folder/"

echo "Finished! Prometheus is ready to use."
