# Crossplane providers performance testing

1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [It's like a Makefile _just_ better](#it's-like-a-makefile-_just_-better)
4. [Envsubst](#envsubst)
5. [Justfile overview](#justfile-overview)
   - [Variables propagation](#variables-propagation)
6. [Testing process](#testing-process)
7. [Formatting output and interpreting tests results](#formatting-output-and-interpreting-tests-results)

## Introduction

Performance testing crossplane providers automation setup.

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
- MANAGE PROVIDERS: Commands to deploy and manage various Crossplane providers.
- HELPER RECEPIES: Commands to perform various utility tasks, such as port forwarding, updating Helm repos, and getting cluster kubeconfig.
- RUN TESTS: Commands to run performance tests and collect metrics.
- TEARDOWN: Commands to delete resources and clean up the environment.

Run `just` without any arguments to see all available recipes. Notice some
recipes have parameters.

```bash
Available recipes:
    default                            # this list of available targets
    setup prov='base'                  # - aws: eks, uxp, observability, aws provider
    setup_base                         # * setup base infrastructure with cluster and observability
    setup_azure                        # * setup azure
    setup_gcp                          # * setup gcp
    setup_aws                          # * setup aws
    setup_eks                          # setup eks cluster
    deploy_uxp                         # deploy uxp
    deploy_gcp_provider                # deploy GCP official provider
    remove_gcp_provider                # remove GCP official provider
    deploy_azure_provider              # setup Azure official provider
    remove_azure_provider              # remove Azure official provider
    deploy_resource_group op='apply'   # deploy resource group
    deploy_monitoring                  # deploy observability
    watch RESOURCE='crossplane'        # flexible watch
    launch_grafana                     # port forward grafana, user: admin, pw: prom-operator
    launch_prometheus                  # port forward prometheus
    copy_node_ip                       # get node ip
    copy_prometheus_memory_metric prov # get prometheus query for memory
    copy_prometheus_url                # get prometheus clusterIP for prometheus configuration
    update_helm                        # update helm repos
    get_kubeconfig                     # get cluster kubeconfig
    test_gcp_deployment                # deploy a sample bucket to verify the setup
    delete_bucket                      # delete GCP test bucket
    run_tests prov iter='1'            # run tests and collect metrics
    create_test_resource iter='2'      # create arbitrary number of test resource
    delete_eks                         # delete eks cluster
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

The formatting commands provided below are useful for cleaning up and organizing
the output data from the performance tests. Using these commands in Vim, you can
remove unnecessary lines, format values, transpose data, and combine results to
make the output easier to read and analyze.

By following the instructions and running the provided commands in Vim, you can
transform raw performance test output into a clean, columnar layout that is
CSV-compatible. This makes it easier to analyze, compare, and share the
performance test results. Prepare files, run in order.

1. Load all the files
   vim \*.txt

1. Remove unused stuff. The macro under q is already present and removes until
   Experiment Duraition line

```bash
bufdo normal@q w
bufdo :%s/^.*msg="\(.*\) \([0-9.]\+\).*$/\1 \2/g
```

1. Format values output
   `bufdo :%s/[0-9.]\+/\=system('numfmt --to=si --format %.2f', submatch(0))`

1. Transpose data to columnar layout with ; separator to make the file CSV
   compatible
   `bufdo :%d|:r! bash -c "datamash -t: transpose <% | column -t -s: --output-separator=';'"`

1. Delete top empty line
   `bufdo :g/^$/d`

1. Add file name to first column
   `bufdo :%s/\v^/\=expand("%:t:r") .expand("; ")/g`

1. Combine results
   <!-- `fd --extension=txt | sort -V | xargs tail -n +1 | sed 's#> ./#> #g'` -->

   `fd --extension=txt | sort -V | xargs cat`

1. Format columns
   `%s/ of Registry/ seconds /g | %s/CPU/CPU %/g`
