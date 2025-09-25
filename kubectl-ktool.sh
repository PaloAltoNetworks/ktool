#!/bin/bash
#
# kubectl-ktool: A kubectl plugin for the Konnector agent.

# --- CONFIGURATION ---
RELEASE="%%RELEASE_VERSION%%"
GITHUB_USER="PaloAltoNetworks"
GITHUB_REPO="ktool"
SCRIPT_NAME="kubectl-ktool.sh"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/releases/latest"
INSTALLATION_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/install.sh"

# --- Helper Functions ---
error() {
    echo "Error: $1" >&2
    exit 1
}

WARN() {
    echo -e "\033[33mWarning:\033[0m $1" >&2
}

# --- Detailed Usage Function ---
usage() {
    echo "Usage: kubectl ktool <command> [options]"
    echo
    echo "A tool for managing and collecting support data for the Konnector agent."
    echo
    echo "Commands:"
    echo "  collect-logs    Collects a comprehensive diagnostic support bundle."
    echo "  upgrade         Upgrades this tool to the latest version from GitHub."
    echo "  version         Prints the current version of this tool."
    echo
    echo "Options for 'collect-logs':"
    echo "  -n, --namespace=<namespace>   The namespace where the agent is installed. (Default: panw)"
    echo "  --kubeconfig=<path>           Path to a specific kubeconfig file to use."
    echo "  --context=<context>           The name of the kubeconfig context to use."
    echo
    echo "Note: Options can be passed with a space (e.g., --namespace my-ns) or an equals sign (e.g., --namespace=my-ns)."
    echo
    echo "Run 'kubectl ktool <command> --help' for more information on a specific command."
    exit 1
}

# --- Automatic Update Check Logic ---

# get_latest_release gets the latest release tag from GitHub.
# It encapsulates the logic to fetch and parse the release information.
#
# Arguments:
#   $@: Additional arguments to pass to curl (e.g., --max-time).
#
# Outputs:
#   The latest release tag string (e.g., "ktool-v1.2.3").
#   Returns empty and a non-zero exit code on failure.
get_latest_release() {
    local LATEST_RELEASE_JSON
    LATEST_RELEASE_JSON=$(curl -fsSL "$@" "${GITHUB_API_URL}" 2>/dev/null)
    if [ -z "$LATEST_RELEASE_JSON" ]; then
        return 1
    fi

    local LATEST_RELEASE
    LATEST_RELEASE=$(echo "$LATEST_RELEASE_JSON" | grep -m 1 '"tag_name":' | cut -d'"' -f4)

    if [ -z "$LATEST_RELEASE" ]; then
        return 1
    fi
    echo "$LATEST_RELEASE"
}

# parse_major_version extracts the major version number from a release string.
#
# Arguments:
#   $1: The release string (e.g., "v1.2.3").
#
# Outputs:
#   The major version number (e.g., "1").
#   Returns empty and a non-zero exit code on failure.
parse_major_version() {
    local release_string="$1"
    if [[ "$release_string" =~ v([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        return 1
    fi
}

# check_for_updates checks if a newer version of the script is available.
# It performs a quick check in the background and warns the user if an
# update is found. It enforces mandatory updates for new major versions.
#
# Arguments:
#   $1: The command argument passed to the main script (e.g., "version", "upgrade").
check_for_updates() {
    local command_arg="$1"
    if [[ "$command_arg" == "upgrade" ]]; then
        return
    fi

    local LATEST_RELEASE
    LATEST_RELEASE=$(get_latest_release --max-time 3)

    if [ -z "$LATEST_RELEASE" ] || [ "$RELEASE" == "$LATEST_RELEASE" ]; then
        return
    fi

    local CURRENT_MAJOR_RELEASE
    CURRENT_MAJOR_RELEASE=$(parse_major_version "$RELEASE")
    if [ -z "$CURRENT_MAJOR_RELEASE" ]; then
        WARN "Could not parse current release version: ${RELEASE}"
        return
    fi
    
    local LATEST_MAJOR_RELEASE
    LATEST_MAJOR_RELEASE=$(parse_major_version "$LATEST_RELEASE")
    if [ -z "$LATEST_MAJOR_RELEASE" ]; then
        WARN "Could not parse latest release version: ${LATEST_RELEASE}"
        return
    fi

    if [ "$LATEST_MAJOR_RELEASE" -gt "$CURRENT_MAJOR_RELEASE" ]; then
        # For major version changes, the update is considered mandatory for most commands.
        case "$command_arg" in
            version|""|-h|--help)
                # For non-critical commands, just show a strong warning.
                WARN "MANDATORY UPDATE RECOMMENDED. A new major release (${LATEST_RELEASE}) is available. Please run 'kubectl ktool upgrade'."
                ;;
            *)
                # For all other commands, block execution and demand an upgrade.
                error "Mandatory update required. A new major release (${LATEST_RELEASE}) is available. Please run 'kubectl ktool upgrade'."
                ;;
        esac
    else
        # For minor or patch updates, a simple warning is sufficient.
        WARN "A new release (${LATEST_RELEASE}) is available. Please run 'kubectl ktool upgrade' to update."
    fi
}

# handle_upgrade manages the script upgrade process.
# It replaces the current script with the latest version from GitHub using the
# official install.sh script.
handle_upgrade() {
    echo "Current release: ${RELEASE}"
    echo "Fetching latest release information from GitHub..."
    
    local LATEST_RELEASE
    LATEST_RELEASE=$(get_latest_release)
    if [ -z "$LATEST_RELEASE" ]; then
        error "Could not fetch release information from GitHub. Check network connection or API response."
    fi

    echo "Latest release available: ${LATEST_RELEASE}"
    if [ "$RELEASE" == "$LATEST_RELEASE" ]; then
        echo "You are already using the latest release."
        exit 0
    fi

    echo "Upgrading to ${LATEST_RELEASE}..."
    if curl -fsSL "${INSTALLATION_SCRIPT_URL}" | bash; then
        echo "Upgrade complete to release ${LATEST_RELEASE}."
    else
        error "The upgrade process failed."
    fi
    exit 0
}

# --- Version Command Logic ---
handle_version() {
    echo "${RELEASE}"
}


# --- Collect Logs Logic ---
check_dependencies() {
    for cmd in helm tar; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "ERROR: '$cmd' command not found. Please ensure it's installed and in your PATH." >&2
            exit 1
        fi
    done
}

collect_logs() {
    check_dependencies

    NAMESPACE="panw"
    KUBECONFIG_FLAG=""
    CONTEXT_FLAG=""
    HELM_CONTEXT_FLAG=""
    BUNDLE_DIR=""

    trap 'if [ -n "${BUNDLE_DIR}" ]; then rm -rf "${BUNDLE_DIR}"; fi' EXIT INT TERM

    shift
    
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -n|--namespace|--namespace=*)
                if [[ "$1" == *=* ]]; then
                    NAMESPACE="${1#*=}"
                    shift 1
                else
                    if [[ -z "$2" || "$2" == -* ]]; then echo "ERROR: Option '$1' requires an argument." >&2; exit 1; fi
                    NAMESPACE="$2"
                    shift 2
                fi
                ;;
            --kubeconfig|--kubeconfig=*)
                if [[ "$1" == *=* ]]; then
                    KUBECONFIG_FLAG="--kubeconfig ${1#*=}"
                    shift 1
                else
                    if [[ -z "$2" || "$2" == -* ]]; then echo "ERROR: Option '$1' requires an argument." >&2; exit 1; fi
                    KUBECONFIG_FLAG="--kubeconfig $2"
                    shift 2
                fi
                ;;
            --context|--context=*)
                if [[ "$1" == *=* ]]; then
                    local context_val="${1#*=}"
                    CONTEXT_FLAG="--context ${context_val}"
                    HELM_CONTEXT_FLAG="--kube-context ${context_val}"
                    shift 1
                else
                    if [[ -z "$2" || "$2" == -* ]]; then echo "ERROR: Option '$1' requires an argument." >&2; exit 1; fi
                    CONTEXT_FLAG="--context $2"
                    HELM_CONTEXT_FLAG="--kube-context $2"
                    shift 2
                fi
                ;;
            *)
                echo "ERROR: Unknown option for collect-logs: $1" >&2
                exit 1
                ;;
        esac
    done

    KUBECTL_BASE_CMD="kubectl ${KUBECONFIG_FLAG} ${CONTEXT_FLAG}"
    HELM_BASE_CMD="helm ${KUBECONFIG_FLAG} ${HELM_CONTEXT_FLAG}"

    echo "--> Verifying namespace '${NAMESPACE}' exists..."
    if ! ${KUBECTL_BASE_CMD} get namespace "${NAMESPACE}" &> /dev/null; then
        echo "ERROR: Namespace '${NAMESPACE}' not found. Please verify the namespace name and your cluster context." >&2
        exit 1
    fi

    KONNECTOR_HELM_RELEASE="konnector"
    K8S_MANAGER_HELM_RELEASE="k8s-connector-release"
    BUNDLE_DIR="konnector-support-bundle-${NAMESPACE}-${RELEASE}-$(date +"%Y%m%d-%H%M%S")"
    
    echo "Starting support bundle collection for namespace: ${NAMESPACE}"
    echo "Output will be saved to ${BUNDLE_DIR}.tar.gz"

    if ! mkdir -p "${BUNDLE_DIR}"; then
        echo "ERROR: Failed to create temporary bundle directory: ${BUNDLE_DIR}" >&2
        exit 1
    fi

    collect_cmd() {
        local title="$1"
        local cmd="$2"
        local file="$3"
        echo "  -> Collecting ${title}..."
        if ! bash -c "$cmd" > "${BUNDLE_DIR}/${file}" 2>&1; then
            echo "WARN: Collection for '${title}' failed. See ${BUNDLE_DIR}/${file} for details." >&2
        fi
    }

    echo "[1/6] Collecting Cluster Information..."
    mkdir -p "${BUNDLE_DIR}/cluster-info"
    collect_cmd "Cluster info" "${KUBECTL_BASE_CMD} cluster-info" "cluster-info/info.txt"
    collect_cmd "Kubernetes version" "${KUBECTL_BASE_CMD} version" "cluster-info/version.txt"
    collect_cmd "Node details" "${KUBECTL_BASE_CMD} get nodes -o wide" "cluster-info/nodes.txt"

    echo "[2/6] Collecting Namespace Information..."
    mkdir -p "${BUNDLE_DIR}/namespace-info"
    collect_cmd "Events in namespace" "${KUBECTL_BASE_CMD} get events -n ${NAMESPACE} --sort-by='.lastTimestamp'" "namespace-info/events.txt"

    echo "[3/6] Collecting Helm Release Information..."
    mkdir -p "${BUNDLE_DIR}/helm"
    collect_cmd "Helm status for ${KONNECTOR_HELM_RELEASE}" "${HELM_BASE_CMD} status ${KONNECTOR_HELM_RELEASE} -n ${NAMESPACE}" "helm/status-${KONNECTOR_HELM_RELEASE}.txt"
    collect_cmd "Helm values for ${KONNECTOR_HELM_RELEASE}" "${HELM_BASE_CMD} get values ${KONNECTOR_HELM_RELEASE} -n ${NAMESPACE} -a" "helm/values-${KONNECTOR_HELM_RELEASE}.yaml"
    collect_cmd "Helm status for ${K8S_MANAGER_HELM_RELEASE}" "${HELM_BASE_CMD} status ${K8S_MANAGER_HELM_RELEASE} -n ${NAMESPACE}" "helm/status-${K8S_MANAGER_HELM_RELEASE}.txt"
    collect_cmd "Helm values for ${K8S_MANAGER_HELM_RELEASE}" "${HELM_BASE_CMD} get values ${K8S_MANAGER_HELM_RELEASE} -n ${NAMESPACE} -a" "helm/values-${K8S_MANAGER_HELM_RELEASE}.yaml"

    echo "[4/6] Collecting Workload Statuses..."
    mkdir -p "${BUNDLE_DIR}/workloads"
    collect_cmd "All workloads (wide)" "${KUBECTL_BASE_CMD} get all -n ${NAMESPACE} -o wide" "workloads/get-all-wide.txt"
    collect_cmd "All workloads (yaml)" "${KUBECTL_BASE_CMD} get all -n ${NAMESPACE} -o yaml" "workloads/get-all.yaml"
    
    echo "  -> Describing all workloads..."
    for kind in pod deployment statefulset daemonset service configmap replicaset ingress; do
        RESOURCES=$(${KUBECTL_BASE_CMD} get "$kind" -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
        if [ -n "$RESOURCES" ]; then
            mkdir -p "${BUNDLE_DIR}/workloads/${kind}"
            for name in $RESOURCES; do
                collect_cmd "${kind}/${name}" "${KUBECTL_BASE_CMD} describe ${kind} ${name} -n ${NAMESPACE}" "workloads/${kind}/${name}.describe.txt"
            done
        fi
    done

    echo "[5/6] Collecting Pod Logs..."
    mkdir -p "${BUNDLE_DIR}/logs"
    PODS=$(${KUBECTL_BASE_CMD} get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    for pod in $PODS; do
        CONTAINERS=$(${KUBECTL_BASE_CMD} get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name} {.spec.initContainers[*].name}' 2>/dev/null)
        for container in $CONTAINERS; do
            collect_cmd "Logs for ${pod}/${container}" "${KUBECTL_BASE_CMD} logs ${pod} -c ${container} -n ${NAMESPACE}" "logs/${pod}_${container}.log"
            collect_cmd "Previous logs for ${pod}/${container}" "${KUBECTL_BASE_CMD} logs ${pod} -c ${container} -n ${NAMESPACE} --previous" "logs/${pod}_${container}.previous.log"
        done
    done

    echo "[6/6] Collecting Operator Configurations..."
    mkdir -p "${BUNDLE_DIR}/operator"
    collect_cmd "Validating Webhooks" "${KUBECTL_BASE_CMD} get validatingwebhookconfigurations -l 'app.kubernetes.io/instance in (${KONNECTOR_HELM_RELEASE}, ${K8S_MANAGER_HELM_RELEASE})' -o yaml" "operator/validating-webhooks.yaml"
    collect_cmd "Mutating Webhooks" "${KUBECTL_BASE_CMD} get mutatingwebhookconfigurations -l 'app.kubernetes.io/instance in (${KONNECTOR_HELM_RELEASE}, ${K8S_MANAGER_HELM_RELEASE})' -o yaml" "operator/mutating-webhooks.yaml"
    
    echo "Packaging support bundle..."
    if ! tar -czf "${BUNDLE_DIR}.tar.gz" "${BUNDLE_DIR}"; then
        echo "ERROR: Failed to create tarball for support bundle." >&2
        exit 1
    fi
    
    echo "Support bundle created successfully: ${BUNDLE_DIR}.tar.gz"
}


# --- SCRIPT EXECUTION STARTS HERE ---

# Run the synchronous update check. This is critical for the blocking logic.
check_for_updates "$1"

# --- MAIN COMMAND ROUTER ---
case "$1" in
    collect-logs)
        collect_logs "$@"
        ;;
    upgrade)
        handle_upgrade
        ;;
    version)
        handle_version
        ;;
    ""|-h|--help)
        usage
        ;;
    *)
        error "Unknown command '$1'"
        ;;
esac
