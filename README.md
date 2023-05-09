# Crossplane providers performance testing

* [Introduction](#introduction)
* [Prerequisites](#prerequisites)
* [It's like a Makefile _just_ better](#it's-like-a-makefile-_just_-better)
* [Envsubst](#envsubst)
* [Justfile overview](#justfile-overview)
  * [Variables propagation](#variables-propagation)
  * [Autoload variables](#autoload-variables)
* [Testing process](#testing-process)
* [Formatting output and interpreting tests results](#formatting-output-and-interpreting-tests-results)
* [Exporting prometheus metrics to S3 bucket](#exporting-prometheus-metrics-to-s3-bucket)
 
## Introduction

Crossplane Providers Performance Testing is an automation setup created to
assess the performance of Crossplane providers. This tool facilitates setting up
and configuring various testing scenarios, executing performance tests, and
analyzing the results to gain insights into the performance of different
Crossplane providers. 

The automation setup streamlines the testing process,
allowing for a better understanding and optimization of Crossplane
infrastructure by providing objective data on the efficiency of different
providers.

It is possible to test regular providers as well as the new _small_ providers.

## Prerequisites

Before getting started, ensure you have the following tools installed on your system:

1. Install the `just` command runner:

For macOS users, you can use Homebrew to install `just`:

```bash
brew install just
```

For Linux users, refer to the [just repository](https://github.com/casey/just#installation) for installation instructions.

1. Install `envsubst`:

On macOS, you can install `gettext` (which includes `envsubst`) using Homebrew:

    brew install gettext
    brew link --force gettext

On Linux, `envsubst` is usually included with the `gettext` package. Use your distribution's package manager to install it:

For Debian-based distributions (e.g., Ubuntu):

    sudo apt-get update
    sudo apt-get install gettext

For RHEL-based distributions (e.g., CentOS):

    sudo yum install gettext

1. Install `kubectl`:

Follow the [official Kubernetes documentation](https://kubernetes.io/docs/tasks/tools/install-kubectl/) to install `kubectl` for your operating system.

1. Install other dependencies (if needed):

Some recipes in the justfile may require additional dependencies. Make sure to install them according to your operating system and the recipes you plan to use.

With all the prerequisites installed, you can now proceed to use the justfile for performance testing.

1. Install `kubectl`:

   Follow the [official Kubernetes documentation](https://kubernetes.io/docs/tasks/tools/install-kubectl/) to install `kubectl` for your operating system.

1. Install other dependencies (if needed):

   Some recipes in the justfile may require additional dependencies. Make sure to install them according to your operating system and the recipes you plan to use.

With all the prerequisites installed, you can now proceed to use the justfile for performance testing.

## It's like a Makefile _just_ better

Setting up a local or test Kubernetes environment means orchestrating a bunch of commands, including scripts, yaml files, helm charts etc.
This is typically done via a `Makefile` or `bash scripts`. The problem with `make` is that it is designed as a tool to _build_C source code, it \_can_ run commands but that's not its purpose.
This means that when using `Makefile` we take on the whole unnecessary baggage of the build part.

Raw `bash scripts` are a bit better but after a while they became too verbose and heavy. This is especially true when the setup is created using `defensive coding` practices.

There is a tool that combines best of both worlds; [just](https://github.com/casey/just) is similar to `make`, but focused on commands orchestration.
The `justfile` in the root of this repo contains all imperative logic needed to
quickly create and destroy our performance testing infrastructure. It exposes various knobs and buttons for us to interact with it or change settings.

## Envsubst

`envsubst` is a command-line utility that substitutes the values of environment
variables into strings. It is part of the GNU gettext package and is available
on most Unix-based systems, including Linux and macOS.

In the justfile, `envsubst` is used to replace environment variables in YAML
files with their actual values before applying the YAML to the cluster. This
allows for a more dynamic configuration and easier customization when running
the justfile. Here's an example of how `envsubst` is used in the justfile:

```bash
setup_eks:
@envsubst < {{yaml}}/cluster.yaml | eksctl create cluster --write-kubeconfig=false --config-file -
```

In this example, `envsubst` reads the contents of the cluster.yaml file, replaces any environment variable placeholders with their actual values, and then pipes the result to the eksctl command.

## Justfile overview

The justfile is organized into sections:

- BASE INFRA SETUP: Commands to set up the base infrastructure, including clusters and observability.
- MANAGE PROVIDERS: Commands to deploy, manage and remove various Crossplane providers.
- HELPER RECEPIES: Commands to perform various utility tasks, such as port forwarding, updating Helm repos, and getting cluster kubeconfig.
- RUN TESTS: Commands to run performance tests and collect metrics.
- TEARDOWN: Commands to delete the whole testing setup

Run `just` without any arguments to see all available recipes. Notice some
recipes have parameters.

```bash
Available recipes:
    default                                                # this list of available targets
    setup prov='base'                                      # - aws: eks, uxp, observability, aws provider
    setup_base                                             # * setup base infrastructure with cluster and observability
    setup_azure                                            # * setup azure
    setup_gcp                                              # * setup gcp
    setup_gcp_small                                        # * setup gcp small providers setup_eks get_kubeconfig (deploy_uxp "unstable") deploy_monitoring (install_platform_ref "v0.1.0" "gcp")
    setup_aws_small                                        # * setup aws small providers setup_eks get_kubeconfig (deploy_uxp "unstable") deploy_monitoring (install_platform_ref "v0.1.0" "aws")
    setup_azure_small                                      # * setup azure small providers setup_eks get_kubeconfig (deploy_uxp "unstable") deploy_monitoring (install_platform_ref "v0.1.0" "azure")
    setup_eks                                              # setup eks cluster
    deploy_uxp version='stable' namespace='upbound-system' # deploy uxp
    remove_uxp                                             # remove uxp
    install_platform_ref_aws                               # install_platform_ref_aws: (install_platform_ref "v0.1.0" "aws")
    install_platform_ref_gcp                               # install_platform_ref_gcp: (install_platform_ref "v0.1.0" "gcp")
    install_platform_ref_azure                             # install_platform_ref_azure: (install_platform_ref "v0.1.0" "azure")
    install_platform_ref version='v0.1.0' cloud='gcp'      # install platform-ref GCP package
    nuke_upbound_system                                    # nuke upbound-system namespace
    deploy_platform_ref_cluster op='apply' cloud='gcp'     # deploy platform-ref-gcp claim
    deploy_gcp_small_provider_config                       # deploy GCP small provider config
    deploy_gcp_provider                                    # deploy GCP official provider
    remove_gcp_provider                                    # remove GCP official provider
    deploy_azure_provider                                  # setup Azure official provider and make sure test resource group is created
    remove_azure_provider                                  # remove Azure official provider
    deploy_resource_group op='apply'                       # deploy resource group
    deploy_monitoring                                      # deploy observability
    get_aws_user_id                                        # get caller identity for cluster name
    watch RESOURCE='crossplane'                            # flexible watch
    launch_grafana                                         # port forward grafana, user: admin, pw: prom-operator
    launch_prometheus                                      # port forward prometheus
    copy_node_ip                                           # get node ip
    copy_prometheus_memory_metric prov                     # get prometheus query for memory
    copy_prometheus_url                                    # get prometheus clusterIP for prometheus configuration
    upload_prometheus_metrics                              # upload Prometheus metrics to S3
    update_helm                                            # update helm repos
    get_kubeconfig                                         # get cluster kubeconfig
    test_gcp_deployment                                    # deploy a sample bucket to verify the setup
    delete_bucket                                          # delete GCP test bucket
    run_tests prov iter='1'                                # run tests and collect metrics
    run_tests_gcp                                          # run all tests for provider GCP
    run_tests_azure                                        # run all tests for provider Azure
    delete_eks                                             # delete eks cluster
```

The run_tests prov iter recipe runs performance tests for a specified provider
and a specified number of iterations. It checks if the Prometheus metrics server
is running, gets the provider pod and node IP, and runs the performance tests
using the perf/main.go tool. It then logs the results in the raw_data directory.

### Variables propagation

Variables in the justfile are used to control various aspects of the performance
testing process, such as the type of node, provider versions, and credentials.
These variables are propagated and substituted in the YAML files using the
envsubst command. This allows the performance testing infrastructure to be
dynamically configured and adapted to different scenarios.

### Autoload variables

Variables can be sourced from `.env` file or session environment or justfile.
This is done with the following variables:

```bash
#!/usr/bin/env bash

export KUBECONFIG="$PWD"/config
export AWS_DEFAULT_PROFILE=609897127049_Half-Day-AdminAccess
export GCP_PROVIDER_CREDS=~/gcp-creds-platform.json
export AZURE_PROVIDER_CREDS=~/crossplane-azure-provider-key.json
```

```diff
- Make sure to substitute the variables with the values for your environment
```
> Make sure to substitute those variables with accordingly

## Testing process

To run the test and gather metrics, follow the steps below. Make sure to adjust any additional instructions if needed.

1. Clone the `performance tool` repository into the `perf-tool` folder.

   > In future this will be replaced with a `go run git....` command to run the
   > tool remotely

1. Configure variables in the justfile: Ensure that the variables in the
   justfile are set as desired, with particular attention to the node, credentials,
   and provider versions.

1. Prepare the test environment: Once you've decided on the provider to use
   (let's say you've chosen Azure), run the following command:

```bash
just setup azure
```

This command sets up the performance testing environment for the selected
provider. It creates a new EKS cluster, deploys UXP and the Crossplane provider
for Azure, and configures the necessary resources.

1. In a separate pane/tab/terminal port forward prometheus pod by running `just
launch_prometheus`. This should open a new tab in the default browser so you can
   start seeing the mertics.

> Use `just copy_prometheus_memory_metric azure` to copy the prometheus memory
> utilization metric with correct pod name and paste it to the prometheus
> metrics execute field.

1. Run tests by executing `just run_tests azure 5`.

This command creates 5 test Managed Resources (in the case of Azure, these will
be Container Registries) and starts collecting metrics into a file.

The tests are executed using the configured provider, and the results are analyzed to
evaluate the performance of the Crossplane provider.

1. Metrics should be ready in a the `raw-data` folder with the name of the
   provider, version and number of MRs created.

1. The Go tool will automatically deploy and remove all the test resources, but
   in case you need to remove the resources manually, you can run `kubectl delete
<resourceName> --all`

## Formatting output and interpreting tests results

To format all the raw output files into a CSV, run:

`./scripts/format_data.py`

## Exporting prometheus metrics to S3 bucket

Prometheus database snapshot can be exported to an S3 bucket using the following
script: `./scripts/uploader.sh`
