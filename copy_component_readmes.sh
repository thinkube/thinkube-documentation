#!/bin/bash
# copy_component_readmes.sh
# Description:
#   Copies all component READMEs from ansible playbook directories
#   to thinkube-documentation with standardized naming format:
#   - XX_core_componentName_README.md
#   - XX_optional_componentName_README.md
#
# Numbering extracted from actual thinkube-installer deployment sequence
#
# Usage:
#   cd /home/thinkube/thinkube-platform/thinkube-documentation
#   ./copy_component_readmes.sh

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ANSIBLE_DIR="/home/thinkube/thinkube-platform/thinkube/ansible"
OUTPUT_DIR="$(pwd)/components"

# Core component mapping (from ACTUAL thinkube-installer Deploy.vue sequence)
# Format: "number:path_from_ansible_dir:display_name:has_readme"
declare -a CORE_COMPONENTS=(
    "01:00_initial_setup:env-setup:yes"
    "02:40_thinkube/core/infrastructure:python-setup:no"  # 00_setup_python_k8s.yaml - no dir README
    "03:00_initial_setup:github-cli:yes"
    "04:30_networking:networking:yes"  # zerotier OR tailscale
    "05:40_thinkube/core/infrastructure:setup-python-k8s:no"  # Duplicate playbook
    "06:40_thinkube/core/infrastructure/k8s:k8s:yes"
    "07:40_thinkube/core/infrastructure/k8s:k8s-join-workers:yes"
    "08:40_thinkube/core/infrastructure/gpu_operator:gpu-operator:yes"
    "09:40_thinkube/core/infrastructure/dns-server:dns-server:yes"
    "10:40_thinkube/core/infrastructure/coredns:coredns:yes"
    "11:40_thinkube/core/infrastructure/coredns:coredns-configure-nodes:yes"
    "12:40_thinkube/core/infrastructure/acme-certificates:acme-certificates:yes"
    "13:40_thinkube/core/infrastructure/ingress:ingress:yes"
    "14:40_thinkube/core/postgresql:postgresql:yes"
    "15:40_thinkube/core/keycloak:keycloak:yes"
    "16:40_thinkube/core/harbor:harbor:yes"
    "17:40_thinkube/core/harbor-images:harbor-images:yes"  # Covers playbooks 17-20
    "21:40_thinkube/core/seaweedfs:seaweedfs:yes"
    "22:40_thinkube/core/juicefs:juicefs:yes"
    "23:40_thinkube/core/argo-workflows:argo-workflows:yes"
    "24:40_thinkube/core/argocd:argocd:yes"
    "25:40_thinkube/core/devpi:devpi:yes"
    "26:40_thinkube/core/gitea:gitea:yes"
    "27:40_thinkube/core/code-server:code-server:yes"
    "28:40_thinkube/core/mlflow:mlflow:yes"
    "29:40_thinkube/core/jupyterhub:jupyterhub:yes"
    "30:40_thinkube/core/thinkube-control:thinkube-control:yes"
)

# Optional component mapping
# Format: "number:path_from_ansible_dir:display_name:has_readme"
declare -a OPTIONAL_COMPONENTS=(
    "31:40_thinkube/optional/prometheus:prometheus:yes"
    "32:40_thinkube/optional/nats:nats:yes"
    "33:40_thinkube/optional/knative:knative:yes"
    "34:40_thinkube/optional/clickhouse:clickhouse:yes"
    "35:40_thinkube/optional/opensearch:opensearch:yes"
    "36:40_thinkube/optional/valkey:valkey:yes"
    "37:40_thinkube/optional/chroma:chroma:yes"
    "38:40_thinkube/optional/qdrant:qdrant:yes"
    "39:40_thinkube/optional/weaviate:weaviate:yes"
    "40:40_thinkube/optional/perses:perses:yes"
    "41:40_thinkube/optional/pgadmin:pgadmin:yes"
    "42:40_thinkube/optional/litellm:litellm:yes"
    "43:40_thinkube/optional/langfuse:langfuse:yes"
    "44:40_thinkube/optional/argilla:argilla:yes"
    "45:40_thinkube/optional/cvat:cvat:yes"
)

echo -e "${BLUE}=== Thinkube Component README Copier ===${NC}"
echo -e "${BLUE}Source: ${ANSIBLE_DIR}${NC}"
echo -e "${BLUE}Output: ${OUTPUT_DIR}${NC}"
echo ""

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Function to copy component README
copy_component_readme() {
    local component_number="$1"
    local component_path="$2"
    local component_name="$3"
    local component_type="$4"  # "core" or "optional"
    local has_readme="$5"

    local full_path="${ANSIBLE_DIR}/${component_path}"
    local readme_path="${full_path}/README.md"

    if [[ "$has_readme" == "no" ]]; then
        echo -e "${YELLOW}⏭${NC} Skipped: ${component_number}_${component_type}_${component_name} (no README - setup/config step)"
        return 2
    fi

    if [[ -f "$readme_path" ]]; then
        local output_file="${OUTPUT_DIR}/${component_number}_${component_type}_${component_name}_README.md"
        cp "$readme_path" "$output_file"
        echo -e "${GREEN}✓${NC} Copied: ${component_number}_${component_type}_${component_name}_README.md"
        return 0
    else
        echo -e "${RED}✗${NC} Missing: ${component_path}/README.md (expected to exist)"
        return 1
    fi
}

# Process core components
echo -e "${BLUE}Processing core components...${NC}"
core_count=0
core_success=0
core_skipped=0

for component_spec in "${CORE_COMPONENTS[@]}"; do
    IFS=':' read -r number path name has_readme <<< "$component_spec"
    ((core_count++))
    result=0
    copy_component_readme "$number" "$path" "$name" "core" "$has_readme" || result=$?
    if [[ $result -eq 0 ]]; then
        ((core_success++))
    elif [[ $result -eq 2 ]]; then
        ((core_skipped++))
    fi
done

echo ""

# Process optional components
echo -e "${BLUE}Processing optional components...${NC}"
optional_count=0
optional_success=0

for component_spec in "${OPTIONAL_COMPONENTS[@]}"; do
    IFS=':' read -r number path name has_readme <<< "$component_spec"
    ((optional_count++))
    if copy_component_readme "$number" "$path" "$name" "optional" "$has_readme"; then
        ((optional_success++))
    fi
done

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "Core components:     ${GREEN}${core_success}${NC} copied, ${YELLOW}${core_skipped}${NC} skipped, total: ${core_count}"
echo -e "Optional components: ${GREEN}${optional_success}${NC}/${optional_count} copied"
echo -e "Total copied:        ${GREEN}$((core_success + optional_success))${NC}"
echo -e ""
echo -e "${BLUE}Output directory:${NC} ${OUTPUT_DIR}"

# List output files
echo ""
echo -e "${BLUE}Generated files (sorted by component number):${NC}"
ls -1 "${OUTPUT_DIR}"/*.md 2>/dev/null | sort -t_ -k1 -n | while read -r file; do
    echo "  - $(basename "$file")"
done

exit 0
