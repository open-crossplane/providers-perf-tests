#!/usr/bin/env -S just --justfile
set export

set shell := ["bash", "-uc"]

# Direcotories variables
yaml                                := justfile_directory() + "/yaml"
uptest                              := justfile_directory() + "/perf-tool"
raw_data                            := justfile_directory() + "/raw-data"

# OS specific variables
copy                                := if os() == "linux" { "xsel -ib"} else { "pbcopy" }
browse                              := if os() == "linux" { "xdg-open "} else { "open" }

# Provider related variables
gcp_provider_version                := "v0.30.0-62a5320"
gcp_provider_image                  :=  "ulucinar/provider-gcp-amd64:"
gcp_project_id                      := "squad-platform-playground"
base64encoded_gcp_creds             := `base64 $GCP_PROVIDER_CREDS | tr -d "\n"` # Variable containing path to a file with credentials for GCP provider
providerconfig_gcp_name             := "default"
gke_node                            := "n1-standard-16"
gke_private_network                 := "small-provider-network"
gke_location                        := "europe-west2-a"

azure_provider_version              := "v0.30.0-faff84353" 
azure_provider_image                := "ulucinar/provider-azure-amd64:"
base64encoded_azure_creds           := `base64 $AZURE_PROVIDER_CREDS | tr -d "\n"` # Variable containing path to a file with credentials for AZURE provider
providerconfig_azure_name           := "default"
aks_node                            := "Standard_D8s_v3" 
aks_resource_group                  := "SmallProvidersTesting"
aks_location                        := "westeurope"

# TODO: figure out why this doesn't render correctly in the secret
base64encoded_aws_creds             := `printf "[default]\n    aws_access_key_id = %s\n    aws_secret_access_key = %s" "${AWS_KEY_ID}" "${AWS_SECRET}" | base64 | tr -d "\n"`
providerconfig_aws_name             := "default"
eks_node                            := "c5.4xlarge"
eks_region                          := "eu-central-1"

# Other variables
file_prefix                         := `echo test_$(date +%F)`
cluster_name                        := "small-providers-testing"
user_id                             := `aws sts get-caller-identity | grep -i userid | awk -F ':' '{print $3}' | cut -d '"' -f1`
random_suffix                       := `echo $RANDOM`

# this list of available targets
default:
  @just --list --unsorted

# BASE INFRA SETUP {{{
# * entry setup recepie, possible values: cluster: eks, aks, gke, uxprelease: stable, unstable. Creates a cluster with uxp and observability.
setup_base cloud='aws' uxp_release='stable': (_setup_cluster cloud) (create_uxp uxp_release) _deploy_monitoring 

# * install platform ref and setup ProviderConfig for a given cloud
create_platformref cloud='aws': (create_platform_ref "v0.1.0-rc.0" cloud) (create_small_provider_config cloud)

# helper recipe for translating between cloud names and clusters
_setup_cluster cloud='aws':
  just {{ if cloud == "azure" { "_setup_aks" } else if cloud == "gcp" { "_setup_gke" } else { "_setup_eks" } }}

# setup eks cluster
_setup_eks:
  @echo "Setting up EKS cluster"
  @envsubst < {{yaml}}/cluster.yaml | eksctl create cluster --write-kubeconfig=false --config-file -
  just _get_kubeconfig

# setup aks cluster
_setup_aks:
  #!/usr/bin/env bash
  set -euo pipefail

  echo "Placeholder to setup AKS cluster"

  echo "Login with service principal"
  az login --service-principal --username $AZURE_CLIENT_ID --password $AZURE_CLIENT_SECRET --tenant $AZURE_TENANT_ID || exit 1

  echo "Create resource group"
  az group create --name {{aks_resource_group}} --location {{aks_location}} || exit 1

  echo "Create AKS cluster"
  az aks create \
    --resource-group {{aks_resource_group}} \
    --name aks-{{cluster_name}} \
    --node-count 1 \
    --node-vm-size {{aks_node}} \
    --location {{aks_location}} \
    --generate-ssh-keys || exit 1
  
  echo "Set kubeconfig with the cluster credentials"
  az aks get-credentials --resource-group {{aks_resource_group}} --name aks-{{cluster_name}} || exit 1
  echo "Setting up ProviderConfig for Azure"

# setup gke cluster
_setup_gke:
  #!/usr/bin/env bash
  set -euo pipefail

  echo "Set the environment variable for the Google Cloud service account"
  export GOOGLE_APPLICATION_CREDENTIALS=$GCP_PROVIDER_CREDS || exit 1

  echo "Create dedicated network for the cluster"
  gcloud compute networks create {{gke_private_network}} --subnet-mode=auto

  echo "Creating GKE cluster"
  gcloud container clusters create gke-{{cluster_name}} \
    --project={{gcp_project_id}} \
    --zone={{gke_location}} \
    --num-nodes=1 \
    --machine-type={{gke_node}} \
    --network={{gke_private_network}} || exit 1
  gcloud container clusters get-credentials gke-{{cluster_name}} --zone={{gke_location}} --project={{gcp_project_id}} || exit 1

# }}}

# MANAGE PROVIDERS {{{
# deploy uxp
create_uxp version='stable' namespace='upbound-system':
  @echo "Creating namespace {{namespace}}"
  @kubectl create namespace {{namespace}} --dry-run=client -o yaml | kubectl apply -f -
  @echo "Installing UXP with version {{version}}"
  up {{ if version == "stable" { "uxp install -n upbound-system" } else { "uxp install v1.12.1-up.1.uprc.1 --unstable -n upbound-system" } }} 
  @kubectl wait --for condition=Available=True --timeout=300s deployment/crossplane --namespace upbound-system

# remove uxp
remove_uxp:
  @echo "Removing UXP"
  @up uxp uninstall 

# deploy platform-ref 
create_platform_ref version='v0.1.0' cloud='gcp':
  @echo "Deploying platform-ref {{cloud}} package"
  @up ctp configuration install xpkg.upbound.io/upbound-release-candidates/platform-ref-{{cloud}}:{{version}}
  @kubectl wait --for condition=Healthy=True --timeout=300s configuration/upbound-release-candidates-platform-ref-{{cloud}}

# deploy small provider config
create_small_provider_config cloud='gcp':
  @echo Deploying ProviderConfig for $cloud"
  @envsubst < {{yaml}}/{{cloud}}-provider-config.yaml | kubectl apply -f - 

# remove small provider config
remove_small_provider_config cloud='gcp':
  @echo Removing ProviderConfig for $cloud"
  @envsubst < {{yaml}}/{{cloud}}-provider-config.yaml | kubectl delete -f - 

# deploy GCP official provider
create_gcp_provider:
  @echo "Setting up GCP official provider"
  @envsubst < {{yaml}}/gcp-provider.yaml | kubectl apply -f - 
  @kubectl wait --for condition=healthy --timeout=300s provider/provider-gcp
  @envsubst < {{yaml}}/gcp-provider-config.yaml | kubectl apply -f - 

# remove GCP official provider
remove_gcp_provider:
  @echo "Remove GCP official provider"
  @envsubst < {{yaml}}/gcp-provider.yaml | kubectl delete -f - 
  @envsubst < {{yaml}}/gcp-provider-config.yaml | kubectl delete -f - 

# setup Azure official provider and make sure test resource group is created
create_azure_provider:
  @echo "Setting up Azure official provider"
  @envsubst < {{yaml}}/azure-provider.yaml | kubectl apply -f - 
  @kubectl wait --for condition=healthy --timeout=300s provider/provider-azure
  @envsubst < {{yaml}}/azure-provider-config.yaml | kubectl apply -f - 
  @just create_resource_group

# remove Azure official provider
remove_azure_provider:
  @echo "Setting up Azure official provider"
  @envsubst < {{yaml}}/azure-provider.yaml | kubectl delete -f - 
  @envsubst < {{yaml}}/azure-provider-config.yaml | kubectl delete -f - 

# deploy resource group
create_azure_resource_group: 
  @kubectl apply -f {{yaml}}/azure-rg.yaml

# remove resource group
remove_azure_resource_group: 
  @kubectl delete -f {{yaml}}/azure-rg.yaml

# deploy observability
_deploy_monitoring:
  @helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  just _update_helm
  @helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n prometheus \
   --set namespaceOverride=prometheus \
   --set grafana.namespaceOverride=prometheus \
   --set grafana.defaultDashboardsEnabled=true \
   --set kube-state-metrics.namespaceOverride=prometheus \
   --set prometheus-node-exporter.namespaceOverride=prometheus --create-namespace
  just _enable_prometheus_admin_api
# }}}

# HELPER RECEPIES {{{
# enable prometheus admin api
_enable_prometheus_admin_api:
  @kubectl -n prometheus patch prometheus kube-prometheus-stack-prometheus --type merge --patch '{"spec":{"enableAdminAPI":true}}'

# nuke upbound-system namespace
remove_upbound_system:
  @echo "Removing upbound-system namespace"
  @kubectl delete namespace upbound-system

# flexible watch
help_watch RESOURCE='crossplane':
  watch kubectl get {{RESOURCE}}

# port forward grafana, user: admin, pw: prom-operator
help_launch_grafana:
  nohup {{browse}} http://localhost:3000 >/dev/null 2>&1
  kubectl port-forward -n prometheus svc/kube-prometheus-stack-grafana 3000:80

# port forward prometheus
help_launch_prometheus:
  nohup {{browse}} http://localhost:9090 >/dev/null 2>&1
  kubectl port-forward -n prometheus svc/kube-prometheus-stack-prometheus 9090:9090

# get node ip
help_copy_node_ip:
  #!/usr/bin/env bash
  node_ip=$(kubectl get nodes -o wide | awk ' FNR == 2 {print $6}')
  echo "$node_ip" | {{copy}}

# get prometheus query for memory
help_copy_prometheus_memory_metric prov:
  #!/usr/bin/env bash
  pod=$(kubectl -n upbound-system get pod -l pkg.crossplane.io/provider=provider-{{prov}} -o name)
  pod="${pod##*/}"
  sum="sum(node_namespace_pod_container:container_memory_working_set_bytes{pod="\"$pod\"", namespace="\"upbound-system"\"})"
  echo -n "$sum" | {{copy}}

# get prometheus clusterIP for prometheus configuration
help_copy_prometheus_url:
  #!/usr/bin/env bash
  ip=$(kubectl get svc -n prometheus kube-prometheus-stack-prometheus -o jsonpath='{.spec.clusterIP}')
  echo http://"$ip":9090 | {{copy}}

# upload Prometheus metrics to S3
help_upload_prometheus_metrics:
  ./scripts/uploader.sh

# update helm repos
_update_helm:
  @helm repo update

# get cluster kubeconfig
_get_kubeconfig:
  @eksctl utils write-kubeconfig --cluster=eks-{{cluster_name}} --region=eu-central-1 --kubeconfig=./config --set-kubeconfig-context=true

# deploy a sample bucket to verify the setup
help_test_gcp_deployment:
  @echo "Test if cluster setup succesfull by depoloying a sample bucket"
  @envsubst < {{yaml}}/bucket.yaml | kubectl apply -f -

# delete GCP test bucket
remove_bucket:
  @echo "Delete sample bucket if present"
  @envsubst < {{yaml}}/bucket.yaml | kubectl delete --ignore-not-found -f - 
### }}}
  
# RUN TESTS {{{
# deploy platform-ref-gcp claim
create_platform_ref_claim cloud='gcp':
  @echo Deploying platform-ref-$cloud claim"
  @kubectl apply -f https://raw.githubusercontent.com/upbound/platform-ref-{{cloud}}/main/examples/cluster-claim.yaml

# remove platform-ref-gcp claim
remove_platform_ref_claim cloud='gcp':
  @echo Removing platform-ref-$cloud claim"
  @kubectl delete -f https://raw.githubusercontent.com/upbound/platform-ref-{{cloud}}/main/examples/cluster-claim.yaml

# run tests and collect metrics
# TODO: collect all pods into an array and pass to the tool
run_tests prov iter='1':
  #!/usr/bin/env bash
  # go run github.com/Piotr1215/perf-tool-uptest/cmd/perf@performance-tool2 \
  if ! curl -q localhost:9090 > /dev/null 2>&1; then
    echo "Launch prometheus metrics server port forwarding with just help_launch_prometheus"
    exit 1
  fi
           # --provider-pods "$pod" \

  pod="upbound-release-candidates-provider-azure-registry-541d9fadwz6g"
  # pod=$(kubectl -n upbound-system get pod -l pkg.crossplane.io/provider=provider-{{prov}} -o name)
  # pod="${pod##*/}"
  node_ip=$(kubectl get nodes -o wide | awk ' FNR == 2 {print $6}')
  active_provider_version=$(printenv | grep {{prov}}_provider_version | awk -F '=' '{print $2}')
  cd {{uptest}} && go run {{uptest}}/cmd/perf/main.go \
         --mrs {{yaml}}/test-resource-{{prov}}.yaml={{iter}} \
         --provider-pods "$pod" \
         --provider-namespace upbound-system \
         --node "$node_ip":9100 \
         --step-duration 1s |& tee {{raw_data}}/{{file_prefix}}_{{prov}}_"$active_provider_version"_{{iter}}.txt

# run all tests for provider GCP
run_tests_gcp:
  @just run_tests gcp 1 
  @just run_tests gcp 10
  @just run_tests gcp 50
  @just run_tests gcp 100

# run all tests for provider Azure
run_tests_azure:
  @just run_tests azure 1 
  @just run_tests azure 10
  @just run_tests azure 50
  @just run_tests azure 100
# }}}

# TEARDOWN {{{
# remove eks cluster
remove_eks:
  @eksctl delete cluster --region={{eks_region}} --name=eks-{{cluster_name}}

# remove aks cluster
remove_aks:
  @az aks delete --name aks-{{cluster_name}} --resource-group {{aks_resource_group}} --yes
  @az group delete --name {{aks_resource_group}} --yes --no-wait

# remove gke cluster
remove_gke:
  #!/usr/bin/env bash
  set -euo pipefail
  echo "Set the environment variable for the Google Cloud service account"
  export GOOGLE_APPLICATION_CREDENTIALS=$GCP_PROVIDER_CREDS || exit 1
  echo "Deleting GKE cluster"
  gcloud container clusters delete gke-{{cluster_name}} \
    --project={{gcp_project_id}} \
    --zone={{gke_location}} \
    --quiet || exit 1
  echo "Delete dedicated network"
  gcloud compute networks delete {{gke_private_network}} --quiet
# }}}

