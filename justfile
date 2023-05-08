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
# gcp_provider_version                := "v0.29.0" 
gcp_provider_version                := "v0.30.0-62a5320"
# gcp_provider_image                  := "xpkg.upbound.io/upbound/provider-gcp:" 
gcp_provider_image                  :=  "ulucinar/provider-gcp-amd64:"
gcp_project_id                      := "squad-platform-playground"
base64encoded_gcp_creds             := `base64 $GCP_PROVIDER_CREDS | tr -d "\n"` # Variable containing path to a file with credentials for GCP provider

# azure_provider_version              := "v0.29.0"
# azure_provider_image                := "xpkg.upbound.io/upbound/provider-azure:" 
azure_provider_version              := "v0.30.0-faff84353" 
azure_provider_image                := "ulucinar/provider-azure-amd64:"
base64encoded_azure_creds           := `base64 $AZURE_PROVIDER_CREDS | tr -d "\n"` # Variable containing path to a file with credentials for AZURE provider

# Other variables
file_prefix                         := `echo test_$(date +%F)`
cluster_name                        := "piotr-perf-test"
eks_region                          := "eu-central-1"
user_id                             := `aws sts get-caller-identity | grep -i userid | awk -F ':' '{print $3}' | cut -d '"' -f1`
random_suffix                       := `echo $RANDOM`
context                             := user_id+"@"+cluster_name+"."+eks_region+".eksctl.io"
node                                := "c5.4xlarge"

# this list of available targets
default:
  @just --list --unsorted

# BASE INFRA SETUP {{{
# * entry setup recepie, possible values: base (defult), azure, aws, gcp, all
# - aws: eks, uxp, observability, aws provider
setup prov='base': 
  @just setup_{{prov}}

# * setup base infrastructure with cluster and observability
setup_base: setup_eks get_kubeconfig deploy_uxp deploy_monitoring 

# * setup azure
setup_azure: setup_base deploy_azure_provider deploy_resource_group

# * setup gcp
setup_gcp: setup_base deploy_gcp_provider

# * setup aws
setup_aws: setup_base

# setup eks cluster
setup_eks: 
  @envsubst < {{yaml}}/cluster.yaml | eksctl create cluster --write-kubeconfig=false --config-file -
# }}}

# MANAGE PROVIDERS {{{
# deploy uxp
deploy_uxp version='stable' namespace='upbound-system':
  @echo "Creating namespace {{namespace}}"
  @kubectl create namespace {{namespace}} --dry-run=client -o yaml | kubectl apply -f -
  @echo "Installing UXP with version {{version}}"
  up {{ if version == "stable" { "uxp install -n upbound-system" } else { "uxp install v1.12.1-up.1.uprc.1 --unstable -n upbound-system" } }} 
  @kubectl wait --for condition=Available=True --timeout=300s deployment/crossplane --namespace upbound-system

# remove uxp
remove_uxp:
  @echo "Removing UXP"
  @up uxp uninstall 

# deploy GCP official provider
deploy_gcp_provider:
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
deploy_azure_provider:
  @echo "Setting up Azure official provider"
  @envsubst < {{yaml}}/azure-provider.yaml | kubectl apply -f - 
  @kubectl wait --for condition=healthy --timeout=300s provider/provider-azure
  @envsubst < {{yaml}}/azure-provider-config.yaml | kubectl apply -f - 
  @just deploy_resource_group

# remove Azure official provider
remove_azure_provider:
  @echo "Setting up Azure official provider"
  @envsubst < {{yaml}}/azure-provider.yaml | kubectl delete -f - 
  @envsubst < {{yaml}}/azure-provider-config.yaml | kubectl delete -f - 

# deploy resource group
deploy_resource_group op='apply':
  @kubectl {{op}} -f {{yaml}}/azure-rg.yaml

# deploy observability
deploy_monitoring:
  @helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  just update_helm
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

# get caller identity for cluster name
get_aws_user_id:
  @aws sts get-caller-identity | grep -i userid | awk -F ':' '{print $3}' | cut -d '"' -f1

# flexible watch
watch RESOURCE='crossplane':
  watch kubectl get {{RESOURCE}}

# port forward grafana, user: admin, pw: prom-operator
launch_grafana:
  nohup {{browse}} http://localhost:3000 >/dev/null 2>&1
  kubectl port-forward -n prometheus svc/kube-prometheus-stack-grafana 3000:80

# port forward prometheus
launch_prometheus:
  nohup {{browse}} http://localhost:9090 >/dev/null 2>&1
  kubectl port-forward -n prometheus svc/kube-prometheus-stack-prometheus 9090:9090

# get node ip
copy_node_ip:
  #!/usr/bin/env bash
  node_ip=$(kubectl get nodes -o wide | awk ' FNR == 2 {print $6}')
  echo "$node_ip" | {{copy}}

# get prometheus query for memory
copy_prometheus_memory_metric prov:
  #!/usr/bin/env bash
  pod=$(kubectl -n upbound-system get pod -l pkg.crossplane.io/provider=provider-{{prov}} -o name)
  pod="${pod##*/}"
  sum="sum(node_namespace_pod_container:container_memory_working_set_bytes{pod="\"$pod\"", namespace="\"upbound-system"\"})"
  echo -n "$sum" | {{copy}}

# get prometheus clusterIP for prometheus configuration
copy_prometheus_url:
  #!/usr/bin/env bash
  ip=$(kubectl get svc -n prometheus kube-prometheus-stack-prometheus -o jsonpath='{.spec.clusterIP}')
  echo http://"$ip":9090 | {{copy}}

# upload Prometheus metrics to S3
upload_prometheus_metrics:
  ./scripts/uploader.sh

# update helm repos
update_helm:
  @helm repo update

# get cluster kubeconfig
get_kubeconfig:
  @eksctl utils write-kubeconfig --cluster={{cluster_name}} --region=eu-central-1 --kubeconfig=./config --set-kubeconfig-context=true

# deploy a sample bucket to verify the setup
test_gcp_deployment:
  @echo "Test if cluster setup succesfull by depoloying a sample bucket"
  @envsubst < {{yaml}}/bucket.yaml | kubectl apply -f -

# delete GCP test bucket
delete_bucket:
  @echo "Delete sample bucket if present"
  @envsubst < {{yaml}}/bucket.yaml | kubectl delete --ignore-not-found -f - 
### }}}
  
# RUN TESTS {{{
# run tests and collect metrics
run_tests prov iter='1':
  #!/usr/bin/env bash
  # go run github.com/Piotr1215/perf-tool-uptest/cmd/perf@performance-tool2 \
  if ! curl -q localhost:9090 > /dev/null 2>&1; then
    echo "Launch prometheus metrics server port forwarding with just launch_prometheus"
    exit 1
  fi
  pod=$(kubectl -n upbound-system get pod -l pkg.crossplane.io/provider=provider-{{prov}} -o name)
  pod="${pod##*/}"
  node_ip=$(kubectl get nodes -o wide | awk ' FNR == 2 {print $6}')
  active_provider_version=$(printenv | grep {{prov}}_provider_version | awk -F '=' '{print $2}')
  cd {{uptest}} && go run {{uptest}}/cmd/perf/main.go \
         --mrs {{yaml}}/test-resource-{{prov}}.yaml={{iter}} \
         --provider-pod "$pod" \
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

create_test_resource iter='2':
  #!/usr/bin/env bash
  for ((i = 0; i < {{iter}}; i++)); do
    random_suffix=`echo $RANDOM`
    envsubst < {{yaml}}/test-resource.yaml | kubectl apply -f -
  done
# }}}

# TEARDOWN {{{
# delete eks cluster
delete_eks:
  @eksctl delete cluster --region=eu-central-1 --name={{cluster_name}}
# }}}

