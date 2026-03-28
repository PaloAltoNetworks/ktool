# ktool

`ktool` is a [`kubectl`](https://kubernetes.io/docs/reference/kubectl/) plugin that collects diagnostic logs and cluster state from Kubernetes environments running the **Konnector** agent. It aggregates relevant workload information into a single compressed archive that can be shared with Palo Alto Networks support for investigation.

## What It Collects

The `collect-logs` command gathers the following data from the target namespace:

| Step | Category | Details |
|------|----------|---------|
| 1/6 | **Cluster Information** | Cluster info, Kubernetes version, node details |
| 2/6 | **Namespace Events** | Events sorted by last timestamp |
| 3/6 | **Helm Releases** | Status and values for `konnector` and `k8s-connector-release` charts |
| 4/6 | **Workload Statuses** | All resources (wide & YAML), plus `describe` output for pods, deployments, statefulsets, daemonsets, services, configmaps, replicasets, and ingresses |
| 5/6 | **Pod Logs** | Current and previous logs for every container (including init containers) |
| 6/6 | **Operator Configurations** | Validating and mutating webhook configurations |

## Prerequisites

- [`kubectl`](https://kubernetes.io/docs/tasks/tools/) configured with access to the target cluster
- [`helm`](https://helm.sh/docs/intro/install/)
- `curl`, `tar`, `bash`

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/PaloAltoNetworks/ktool/main/install.sh | bash
```

The installer downloads the latest release from GitHub and places the plugin at `/usr/local/bin/kubectl-ktool` (requires `sudo`).

To verify the installation:

```bash
kubectl ktool version
```

## Usage

### Collect Diagnostic Logs

```bash
kubectl ktool collect-logs -n <namespace>
```

For example, targeting the `panw` namespace (default):

```bash
kubectl ktool collect-logs
```

Or specifying a custom namespace:

```bash
kubectl ktool collect-logs -n my-namespace
```

The tool generates a compressed archive in your current directory:

```
./konnector-support-bundle-<namespace>-<version>-<timestamp>.tar.gz
```

### Options for `collect-logs`

| Option | Description |
|--------|-------------|
| `-n`, `--namespace` | Namespace where the agent is installed (default: `panw`) |
| `--kubeconfig` | Path to a specific kubeconfig file |
| `--context` | The kubeconfig context to use |

Options accept both space-separated and `=` syntax:

```bash
kubectl ktool collect-logs --namespace=my-ns --context=my-cluster
kubectl ktool collect-logs -n my-ns --kubeconfig /path/to/kubeconfig
```

### Upgrade

`ktool` checks for updates automatically on each run. To upgrade manually:

```bash
kubectl ktool upgrade
```

> **Note:** Major version updates are mandatory — the tool will block execution until you upgrade.

### Help

```bash
kubectl ktool --help
```

## License

This project is licensed under the [Apache License 2.0](LICENSE).
