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
gcp_provider_version                := "v0.29.0-e45875a" # env_var_or_default('GCP_PROVIDER', "v0.29.0")
gcp_provider_image                  := "ulucinar/provider-gcp-amd64:"
gcp_project_id                      := "squad-platform-playground"
base64encoded_gcp_creds             := `base64 ~/gcp-creds-platform.json | tr -d "\n"`

azure_provider_version              := "d0932e28" # env_var_or_default('AZURE_PROVIDER', "v0.28.0")
azure_provider_image                := "ulucinar/provider-azure-amd64:" # "xpkg.upbound.io/upbound/provider-azure:"
base64encoded_azure_creds           := `base64 ~/crossplane-azure-provider-key.json | tr -d "\n"`

# Other variables
file_prefix                         := `echo test-$(date +%F)`
cluster_name                        := "piotr-perf-test"
eks_region                          := "eu-central-1"
user_id                             := `aws sts get-caller-identity | grep -i userid | awk -F ':' '{print $3}' | cut -d '"' -f1`
random_suffix                       := `echo $RANDOM`
context                             := user_id+"@"+cluster_name+"."+eks_region+".eksctl.io"
node                                := "m5.2xlarge"

# this list of available targets
default:
  @just --list --unsorted

testme:
  echo {{context}}
  echo {{user_id}}

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
deploy_uxp:
  @echo "Installing UXP"
  @kubectl create namespace upbound-system
  @up uxp install
  @kubectl wait --for condition=Available=True --timeout=300s deployment/crossplane --namespace upbound-system

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

# setup Azure official provider
deploy_azure_provider:
  @echo "Setting up Azure official provider"
  @envsubst < {{yaml}}/azure-provider.yaml | kubectl apply -f - 
  @kubectl wait --for condition=healthy --timeout=300s provider/provider-azure
  @envsubst < {{yaml}}/azure-provider-config.yaml | kubectl apply -f - 

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
  @helm install kube-prometheus-stack  prometheus-community/kube-prometheus-stack -n prometheus \
   --set namespaceOverride=prometheus \
   --set grafana.namespaceOverride=prometheus \
   --set grafana.defaultDashboardsEnabled=true \
   --set kube-state-metrics.namespaceOverride=prometheus \
   --set prometheus-node-exporter.namespaceOverride=prometheus --create-namespace

# create thanos objstore secret
create_thanos_objstore_secret:
  @kubectl create namespace prometheus --dry-run=client -o yaml | kubectl apply -f -
  @kubectl create secret generic thanos-objstore-config --namespace=prometheus \
    --from-file=objstore.yaml=<path_to_objstore_yaml> --dry-run=client -o yaml | kubectl apply -f -

# deploy thanos
deploy_thanos:
  @helm repo add thanos https://thanos-io.github.io/thanos-chart
  just update_helm
  @helm install thanos thanos/thanos \
   --create-namespace \
   --namespace prometheus \
   --set objstoreConfig.secretName=thanos-objstore-config \
   --set objstoreConfig.secretKey=objstore.yaml

# Export Thanos metrics
export_metrics:
  @echo "Ensure you have kubectl port-forward running for Thanos Query and Thanos Store Gateway"
  # Get the current date, provider name, and version
  current_date = `date +%F`
  active_provider_version = `echo $ACTIVE_PROVIDER_VERSION`
  provider_name = `echo $PROVIDER_NAME`

  # Create the S3 folder path
  s3_folder = "s3://your-s3-bucket/metrics/${current_date}/${provider_name}/${active_provider_version}"

  # Run the thanos tools bucket web command
  @docker run -it --rm \
    -v $PWD/objstore.yaml:/etc/thanos/objstore.yaml:ro \
    quay.io/thanos/thanos:v0.23.1 \
    tools bucket web \
    --listen ":8080" \
    --objstore.config-file "/etc/thanos/objstore.yaml" \
    --web.external-prefix="${s3_folder}"

  # Forward port 8080 to access Thanos tools bucket web UI
  @echo "You can now access Thanos tools bucket web UI at http://localhost:8080"
  @kubectl port-forward svc/thanos-query -n prometheus 8080:8080
# }}}

# HELPER RECEPIES {{{
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

# update helm repos
update_helm:
  @helm repo update

# get cluster kubeconfig
get_kubeconfig:
  @eksctl utils write-kubeconfig --cluster={{cluster}} --region=eu-central-1 --kubeconfig=./config --set-kubeconfig-context=true

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
         --step-duration 1s |& tee {{raw_data}}/{{file_prefix}}-{{prov}}-$active_provider_version-{{iter}}.txt
  echo "Getting provider pod processes"
  kubectl -n upbound-system exec -i "$pod" -- ps -o pid,ppid,etime,comm,args > {{raw_data}}/{{file_prefix}}-{{prov}}-{{iter}}-ps.log

# create arbitra# Run tests and export metrics
run_tests_and_export_metrics prov iter='1':
  @just run_tests {{prov}} {{iter}}
  @just export_metricsry number of test resource

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

