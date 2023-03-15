#!/usr/bin/env -S just --justfile
set export

set shell := ["bash", "-uc"]

yaml                                := justfile_directory() + "/yaml"
uptest                              := justfile_directory() + "/uptest"
file_prefix                         := justfile_directory() + "/test"
cluster                             := "piotr-azure-perf-test"
context                             := "piotr@upbound.io@piotr-azure-perf-test.eu-central-1.eksctl.io"
copy                                := if os() == "linux" { "xsel -ib"} else { "pbcopy" }
browse                              := if os() == "linux" { "xdg-open "} else { "open" }
# azure_provider_pod                  := `kubectl -n upbound-system get pod -l pkg.crossplane.io/provider=provider-azure -o name`

export node                         := "m5.2xlarge"
export azure_provider_version       := env_var_or_default('AZURE_PROVIDER', "v0.28.0")
export random_suffix                := `echo $RANDOM`
export base64encoded_azure_creds    := `base64 ~/crossplane-azure-provider-key.json | tr -d "\n"`

# this list of available targets
default:
  @just --list --unsorted

# * setup all
setup_all: setup_eks get_kubeconfig setup_uxp install_monitoring setup_azure deploy_resource_group

# delete eks cluster
delete_eks:
  @eksctl delete cluster --region=eu-central-1 --name={{cluster}}

# setup eks cluster
setup_eks: 
  @envsubst < {{yaml}}/cluster.yaml | eksctl create cluster --write-kubeconfig=false --config-file -

# get cluster kubeconfig
get_kubeconfig:
  @eksctl utils write-kubeconfig --cluster={{cluster}} --region=eu-central-1 --kubeconfig=./config --set-kubeconfig-context=true

# setup uxp
setup_uxp:
  @echo "Installing UXP"
  @kubectl create namespace upbound-system
  @up uxp install
  @kubectl wait --for condition=Available=True --timeout=300s deployment/crossplane --namespace upbound-system

# setup Azure official provider
setup_azure:
  @echo "Setting up Azure official provider"
  @envsubst < {{yaml}}/azure-provider.yaml | kubectl apply -f - 
  @kubectl wait --for condition=healthy --timeout=300s provider/provider-azure
  @envsubst < {{yaml}}/azure-provider-config.yaml | kubectl apply -f - 

# deploy resource group
deploy_resource_group op='apply':
  @kubectl {{op}} -f {{yaml}}/azure-rg.yaml

# run tests and collect metrics
run_tests iter='1':
  #!/usr/bin/env bash
  pod=$(kubectl -n upbound-system get pod -l pkg.crossplane.io/provider=provider-azure -o name)
  pod="${pod##*/}"
  node_ip=$(kubectl get nodes -o wide | awk ' FNR == 2 {print $6}')
  go run http://github.com/upbound/uptest/cmd/perf@performance-tool2 \
         --mrs {{yaml}}/test-resource.yaml={{iter}} \
         --provider-pod "$pod" \
         --provider-namespace upbound-system \
         --node "$node_ip":9100 \
         --step-duration 1s |& tee {{file_prefix}}-{{iter}}.txt

  echo "Getting managed resources state"
  kubectl get managed -oyaml > {{file_prefix}}-{{iter}}-mrs.txt
  
  echo "Getting provider pod processes"
  kubectl -n upbound-system exec -i "$pod" -- ps -o pid,ppid,etime,comm,args > {{file_prefix}}-{{iter}}-ps.log

# create arbitrary number of test resource
create_test_resource iter='2':
  #!/usr/bin/env bash
  for ((i = 0; i < {{iter}}; i++)); do
    random_suffix=`echo $RANDOM`
    envsubst < {{yaml}}/test-resource.yaml | kubectl apply -f -
  done

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

# get prometheus clusterIP for prometheus configuration
copy_prometheus_url:
  #!/usr/bin/env bash
  ip=$(kubectl get svc -n prometheus kube-prometheus-stack-prometheus -o jsonpath='{.spec.clusterIP}')
  echo http://"$ip":9090 | {{copy}}

# update helm repos
update_helm:
  @helm repo update

# install observability
install_monitoring:
  @helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  just update_helm
  @helm install kube-prometheus-stack  prometheus-community/kube-prometheus-stack -n prometheus \
   --set namespaceOverride=prometheus \
   --set grafana.namespaceOverride=prometheus \
   --set grafana.defaultDashboardsEnabled=true \
   --set kube-state-metrics.namespaceOverride=prometheus \
   --set prometheus-node-exporter.namespaceOverride=prometheus --create-namespace

# flexible watch
watch RESOURCE='crossplane':
  watch kubectl get {{RESOURCE}}
