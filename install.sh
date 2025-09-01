#!/bin/bash

# Shape Network Unified Installation Script
# Single point of entry for complete Shape Network deployment
# Includes Azure infrastructure, Shape Network nodes, and SSL certificates
#
# Usage:
# ./install.sh  # Interactive menu
#   1) Azure Infrastructure - Creates resource group, AKS cluster, static IP, NSG rules
#   2) Shape Network + SSL - Deploys NGINX ingress, Shape Network pods, services, SSL
#   3) Complete Setup - Full end-to-end deployment (1 + 2)
#   4) Cleanup - Remove all Shape Network resources
#
# Features:
# - Interactive menu-driven deployment
# - Integrated SSL certificate management
# - Automated sequencing and health checks
# - Comprehensive error handling and cleanup

set -e

# Configuration
RESOURCE_GROUP="rg-shape-network"
LOCATION="eastus2"
AKS_CLUSTER="aks-shape-network"
STATIC_IP_NAME="shape-snow-mainnet-static-ip"
DNS_LABEL=""
NODE_COUNT=1
NODE_SIZE="Standard_D2s_v3"
KUBERNETES_VERSION="1.30.14"

# User configuration (will be prompted if not found in .shape-config)
USER_EMAIL=""
DNS_FQDN=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${GREEN}$1${NC}"
}

# Load existing configuration or prompt for missing values
load_or_prompt_config() {
    log_info "Loading configuration..."

    if [[ -f ".shape-config" ]]; then
        log_info "Found existing .shape-config, loading values..."
        source .shape-config

        # Export variables for Helm templating
        export DNS_FQDN
        export USER_EMAIL
        export DNS_LABEL

        log_success "Configuration loaded successfully"
    else
        log_info "No .shape-config found, configuration will be prompted during installation"
    fi
}

# Prompt for DNS label configuration
prompt_dns_config() {
    echo ""
    log_header "🔧 Azure DNS Configuration"
    echo ""

    # Prompt for DNS label if not set
    if [ -z "$DNS_LABEL" ]; then
        echo -e "${CYAN}Azure DNS Configuration${NC}"
        echo "Your Shape Network will be accessible at:"
        echo "https://[your-dns-label].eastus2.cloudapp.azure.com"
        echo ""
        echo "Choose a unique DNS label name (lowercase, no spaces, 3-63 characters):"
        echo "• Use only lowercase letters, numbers, and hyphens"
        echo "• Cannot start or end with a hyphen"
        echo "• Must be unique within Azure region"
        echo ""

        while true; do
            read -p "Enter your DNS label name: " dns_input
            # Validate DNS label format (Azure rules)
            if [[ "$dns_input" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] && [ ${#dns_input} -ge 3 ] && [ ${#dns_input} -le 63 ]; then
                DNS_LABEL="$dns_input"
                log_success "DNS label set to: $DNS_LABEL"
                log_info "Your domain will be: https://$DNS_LABEL.eastus2.cloudapp.azure.com"
                break
            else
                log_error "Invalid DNS label format. Please use only lowercase letters, numbers, and hyphens (3-63 characters, cannot start/end with hyphen)."
            fi
        done
    fi

    # Export variables for Helm templating
    export DNS_FQDN
    export USER_EMAIL
    export DNS_LABEL
}

# Prompt for email configuration
prompt_email_config() {
    echo ""
    log_header "🔧 SSL Certificate Configuration"
    echo ""

    # Prompt for email if not set
    if [ -z "$USER_EMAIL" ]; then
        echo -e "${CYAN}Let's Encrypt SSL Certificate Configuration${NC}"
        echo "SSL certificates require a valid email address for:"
        echo "• Certificate expiration notifications"
        echo "• Account recovery"
        echo "• Important security updates"
        echo ""
        while true; do
            read -p "Enter your email address for SSL certificates: " email_input
            if [[ "$email_input" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                USER_EMAIL="$email_input"
                log_success "Email set to: $USER_EMAIL"
                break
            else
                log_error "Invalid email format. Please enter a valid email address."
            fi
        done
    fi

    # Export variables for Helm templating
    export DNS_FQDN
    export USER_EMAIL
    export DNS_LABEL
}

# Save user configuration to .shape-config
save_user_configuration() {
    log_info "Saving user configuration..."

    # Preserve existing values if they exist
    local existing_resource_group="${RESOURCE_GROUP:-rg-shape-network}"
    local existing_aks_cluster="${AKS_CLUSTER:-aks-shape-network}"
    local existing_static_ip="${STATIC_IP:-}"
    local existing_dns_fqdn="${DNS_FQDN:-}"
    local existing_node_resource_group="${NODE_RESOURCE_GROUP:-}"
    local existing_location="${LOCATION:-eastus2}"
    local existing_dns_label="${DNS_LABEL:-mainnet-shape-snow}"

    cat > .shape-config << EOF
# Shape Network Configuration - Generated by install.sh
RESOURCE_GROUP="$existing_resource_group"
AKS_CLUSTER="$existing_aks_cluster"
STATIC_IP="$existing_static_ip"
DNS_FQDN="$existing_dns_fqdn"
NODE_RESOURCE_GROUP="$existing_node_resource_group"
LOCATION="$existing_location"
DNS_LABEL="$existing_dns_label"
USER_EMAIL="$USER_EMAIL"
INSTALL_DATE="$(date)"
EOF

    log_success "Configuration saved to .shape-config"

    # Export variables for Helm templating
    export DNS_FQDN
    export USER_EMAIL
    export DNS_LABEL
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi

    # Check Helm
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed. Please install it first."
        exit 1
    fi

    # Check Azure login
    if ! az account show &> /dev/null; then
        log_error "Please login to Azure CLI first: az login"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# Cleanup function
cleanup_resources() {
    log_info "Cleaning up existing resources..."

    # Delete shape-network namespace
    if kubectl get namespace shape-network &>/dev/null; then
        log_info "Deleting shape-network namespace..."
        kubectl delete namespace shape-network --ignore-not-found=true --timeout=300s
        # Wait for namespace to be fully deleted
        for i in {1..30}; do
            if ! kubectl get namespace shape-network &>/dev/null; then
                break
            fi
            log_info "Waiting for shape-network namespace deletion... (${i}/30)"
            sleep 10
        done
        if kubectl get namespace shape-network &>/dev/null; then
            log_warning "shape-network namespace still exists, continuing anyway..."
        fi
    fi

    # Delete ingress-nginx namespace
    if kubectl get namespace ingress-nginx &>/dev/null; then
        log_info "Deleting ingress-nginx namespace..."
        kubectl delete namespace ingress-nginx --ignore-not-found=true --timeout=300s
    fi

    # Delete cert-manager namespace
    if kubectl get namespace cert-manager &>/dev/null; then
        log_info "Deleting cert-manager namespace..."
        kubectl delete namespace cert-manager --ignore-not-found=true --timeout=300s
    fi

    # Clean up Helm releases
    if helm list -A | grep -q "shape-network-node"; then
        log_info "Uninstalling shape-network-node Helm release..."
        helm uninstall shape-network-node --namespace shape-network --ignore-not-found
    fi

    if helm list -A | grep -q "ingress-nginx"; then
        log_info "Uninstalling ingress-nginx Helm release..."
        # Check if it's in ingress-nginx namespace
        if helm list -A | grep "ingress-nginx" | grep -q "ingress-nginx"; then
            helm uninstall ingress-nginx --namespace ingress-nginx --ignore-not-found
        else
            # Check if it's in default namespace
            if kubectl get deployment ingress-nginx-controller -n default &>/dev/null; then
                log_info "Found ingress-nginx in default namespace, removing it..."
                helm uninstall ingress-nginx --namespace default --ignore-not-found
                # Also clean up any resources left behind
                kubectl delete namespace ingress-nginx --ignore-not-found=true
            fi
        fi
    fi

    if helm list -A | grep -q "cert-manager"; then
        log_info "Uninstalling cert-manager Helm release..."
        helm uninstall cert-manager --namespace cert-manager --ignore-not-found
    fi

    # Clean up cluster-level resources
    log_info "Cleaning up cluster-level resources..."

    # Delete ingress-nginx cluster roles and bindings
    if kubectl get clusterrole ingress-nginx &>/dev/null; then
        log_info "Deleting ingress-nginx cluster role..."
        kubectl delete clusterrole ingress-nginx --ignore-not-found=true
    fi

    if kubectl get clusterrolebinding ingress-nginx &>/dev/null; then
        log_info "Deleting ingress-nginx cluster role binding..."
        kubectl delete clusterrolebinding ingress-nginx --ignore-not-found=true
    fi

    # Delete cert-manager cluster roles and bindings
    local cert_manager_cluster_roles=("cert-manager-cainjector" "cert-manager-controller-approve:cert-manager-io" "cert-manager-controller-certificates" "cert-manager-controller-certificatesigningrequests" "cert-manager-controller-challenges" "cert-manager-controller-clusterissuers" "cert-manager-controller-ingress-shim" "cert-manager-controller-issuers" "cert-manager-controller-orders" "cert-manager-webhook:subjectaccessreviews")

    for role in "${cert_manager_cluster_roles[@]}"; do
        if kubectl get clusterrole "$role" &>/dev/null; then
            log_info "Deleting cert-manager cluster role: $role"
            kubectl delete clusterrole "$role" --ignore-not-found=true
        fi

        if kubectl get clusterrolebinding "$role" &>/dev/null; then
            log_info "Deleting cert-manager cluster role binding: $role"
            kubectl delete clusterrolebinding "$role" --ignore-not-found=true
        fi
    done

    # Clean up orphaned resources
    log_info "Cleaning up orphaned resources..."

    # Delete any remaining ingress-nginx resources
    kubectl delete clusterrole,clusterrolebinding,validatingwebhookconfiguration,mutatingwebhookconfiguration,ingressclass -l app.kubernetes.io/name=ingress-nginx --ignore-not-found=true

    # Delete any remaining cert-manager resources
    kubectl delete clusterrole,clusterrolebinding,validatingwebhookconfiguration,mutatingwebhookconfiguration -l app.kubernetes.io/instance=cert-manager --ignore-not-found=true

    # Delete orphaned IngressClass resources
    kubectl delete ingressclass nginx --ignore-not-found=true

    # Delete Shape Network specific resources
    log_info "Cleaning up Shape Network specific resources..."

    # Delete PVCs created by Shape Network
    kubectl delete pvc -l app.kubernetes.io/name=shape-network-node --ignore-not-found=true

    # Delete ConfigMaps created by Shape Network
    kubectl delete configmap -l app.kubernetes.io/name=shape-network-node --ignore-not-found=true

    # Delete Secrets created by Shape Network
    kubectl delete secret -l app.kubernetes.io/name=shape-network-node --ignore-not-found=true

    # Delete ServiceAccounts created by Shape Network
    kubectl delete serviceaccount -l app.kubernetes.io/name=shape-network-node --ignore-not-found=true

    # Delete Roles and RoleBindings created by Shape Network
    kubectl delete role,rolebinding -l app.kubernetes.io/name=shape-network-node --ignore-not-found=true

    # Delete Jobs created by Shape Network (SSL post-install hooks)
    kubectl delete job -l app.kubernetes.io/name=shape-network-node --ignore-not-found=true

    # Delete NetworkPolicies if any
    kubectl delete networkpolicy -l app.kubernetes.io/name=shape-network-node --ignore-not-found=true

    # Delete PriorityClasses if any
    kubectl delete priorityclass -l app.kubernetes.io/name=shape-network-node --ignore-not-found=true

    # Delete ResourceQuotas if any
    kubectl delete resourcequota -l app.kubernetes.io/name=shape-network-node --ignore-not-found=true

    # Delete any remaining custom resources
    kubectl delete certificaterequests,certificates,challenges,clusterissuers,issuers,orders -l app.kubernetes.io/name=shape-network-node --ignore-not-found=true

    # Wait a moment for resources to be deleted
    sleep 5

    log_success "Cleanup completed"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"

    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
        log_success "Resource group created"
    fi
}

# Configure Azure Network Security Group
configure_azure_ports() {
    log_info "Configuring Azure Network Security Group rules"

    local node_rg="$NODE_RESOURCE_GROUP"

    if [ -z "$node_rg" ]; then
        log_warning "Node resource group not found, skipping NSG configuration"
        return
    fi

    local nsg_name=$(az network nsg list --resource-group "$node_rg" --query "[0].name" -o tsv 2>/dev/null)

    if [ -z "$nsg_name" ]; then
        log_warning "Could not find Network Security Group"
        return
    fi

    log_info "Found NSG: $nsg_name in resource group: $node_rg"

    local ports=("80:HTTP-Homepage" "443:HTTPS-Homepage" "8545:HTTP-JSON-RPC" "8546:WebSocket-Shape")
    local priority=1100

    for port_rule in "${ports[@]}"; do
        IFS=':' read -r port name <<< "$port_rule"

        if az network nsg rule show --resource-group "$node_rg" --nsg-name "$nsg_name" --name "Allow-$name" &>/dev/null; then
            log_info "✅ NSG rule Allow-$name already exists"
        else
            log_info "Creating NSG rule for port $port ($name)..."

            az network nsg rule create \
                --resource-group "$node_rg" \
                --nsg-name "$nsg_name" \
                --name "Allow-$name" \
                --protocol Tcp \
                --direction Inbound \
                --priority $priority \
                --source-address-prefix '*' \
                --source-port-range '*' \
                --destination-address-prefix '*' \
                --destination-port-range "$port" \
                --access Allow \
                --description "Allow $name traffic for Shape Network" \
                --output none

            if [ $? -eq 0 ]; then
                log_success "✅ Created NSG rule for port $port ($name)"
            else
                log_warning "⚠️  Failed to create NSG rule for port $port ($name)"
            fi
        fi
        priority=$((priority + 10))
    done

    log_success "Azure Network Security Group configuration completed"
}

# Create static public IP
create_static_ip() {
    log_info "Creating static public IP: $STATIC_IP_NAME"

    # Use the DNS label for the public IP
    local dns_label_to_use="$DNS_LABEL"

    if az network public-ip show --resource-group "$NODE_RESOURCE_GROUP" --name "$STATIC_IP_NAME" &> /dev/null; then
        log_warning "Static IP $STATIC_IP_NAME already exists"
    else
        az network public-ip create \
            --resource-group "$NODE_RESOURCE_GROUP" \
            --name "$STATIC_IP_NAME" \
            --location "$LOCATION" \
            --allocation-method Static \
            --sku Standard \
            --dns-name "$dns_label_to_use"
        log_success "Static IP created with DNS label: $dns_label_to_use"
    fi

    STATIC_IP=$(az network public-ip show \
        --resource-group "$NODE_RESOURCE_GROUP" \
        --name "$STATIC_IP_NAME" \
        --query ipAddress \
        --output tsv)
    DNS_FQDN=$(az network public-ip show \
        --resource-group "$NODE_RESOURCE_GROUP" \
        --name "$STATIC_IP_NAME" \
        --query dnsSettings.fqdn \
        --output tsv)

    log_success "Static IP: $STATIC_IP"
    log_success "DNS FQDN: $DNS_FQDN"
}

# Create AKS cluster
create_aks_cluster() {
    log_info "Creating AKS cluster: $AKS_CLUSTER"

    if az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER" &> /dev/null; then
        log_warning "AKS cluster $AKS_CLUSTER already exists"
    else
        az aks create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$AKS_CLUSTER" \
            --location "$LOCATION" \
            --node-count "$NODE_COUNT" \
            --node-vm-size "$NODE_SIZE" \
            --enable-managed-identity \
            --generate-ssh-keys

        log_success "AKS cluster created successfully"
    fi

    NODE_RESOURCE_GROUP=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER" --query nodeResourceGroup --output tsv)
    log_info "Node Resource Group: $NODE_RESOURCE_GROUP"
}

# Configure kubectl
configure_kubectl() {
    log_info "Configuring kubectl for AKS cluster"

    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER" --overwrite-existing

    if kubectl cluster-info &> /dev/null; then
        log_success "kubectl configured successfully"
        kubectl get nodes
    else
        log_error "Failed to configure kubectl"
        exit 1
    fi
}

# Install NGINX Ingress Controller
install_nginx_ingress() {
    log_info "Installing NGINX Ingress Controller with TCP/UDP support"

    # Check for existing installations in wrong namespaces
    if kubectl get deployment ingress-nginx-controller -n default &>/dev/null; then
        log_warning "Found existing NGINX Ingress Controller in default namespace, removing it..."
        helm uninstall ingress-nginx --namespace default --ignore-not-found
        # Clean up any leftover resources
        kubectl delete clusterrole ingress-nginx --ignore-not-found=true
        kubectl delete clusterrolebinding ingress-nginx --ignore-not-found=true
        kubectl delete validatingwebhookconfiguration ingress-nginx-admission --ignore-not-found=true
        kubectl delete service ingress-nginx-controller -n default --ignore-not-found=true
        kubectl delete deployment ingress-nginx-controller -n default --ignore-not-found=true
        kubectl delete configmap ingress-nginx-controller -n default --ignore-not-found=true
        kubectl delete serviceaccount ingress-nginx -n default --ignore-not-found=true
        sleep 5
    fi

    # Add Helm repo
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
    helm repo update

    # Install/upgrade ingress-nginx
    if [ -n "$STATIC_IP" ]; then
        # Use existing static IP if available
        helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --create-namespace \
            --set controller.service.type=LoadBalancer \
            --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-resource-group"="$NODE_RESOURCE_GROUP" \
            --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-pip-name"="$STATIC_IP_NAME" \
            --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
            --set controller.service.externalTrafficPolicy=Cluster \
            --set tcp.8545="shape-network/shape-node-op-geth:8545" \
            --set tcp.8546="shape-network/shape-node-op-geth:8546" \
            --wait \
            --timeout=10m > /dev/null
    else
        # Use LoadBalancer without static IP
        helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --create-namespace \
            --set controller.service.type=LoadBalancer \
            --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
            --set controller.service.externalTrafficPolicy=Cluster \
            --set tcp.8545="shape-network/shape-node-op-geth:8545" \
            --set tcp.8546="shape-network/shape-node-op-geth:8546" \
            --wait \
            --timeout=10m > /dev/null
    fi

    log_success "NGINX Ingress Controller installed"

    # Wait for LoadBalancer IP (only if we expect one)
    if [ -n "$STATIC_IP" ]; then
        for i in {1..24}; do
            INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

            if [ ! -z "$INGRESS_IP" ] && [ "$INGRESS_IP" != "<pending>" ]; then
                if [ "$INGRESS_IP" = "$STATIC_IP" ]; then
                    log_success "✅ LoadBalancer assigned correct static IP: $INGRESS_IP"
                    break
                else
                    log_warning "LoadBalancer has unexpected IP: $INGRESS_IP (expected: $STATIC_IP)"
                fi
            fi

            log_info "Waiting for IP assignment... (${i}/24)"
            sleep 5
        done

        if [ -z "$INGRESS_IP" ] || [ "$INGRESS_IP" = "<pending>" ]; then
            log_error "LoadBalancer IP assignment timed out"
            exit 1
        fi
    else
        log_info "Skipping LoadBalancer IP check (no static IP configured)"
    fi
}

# Install cert-manager
install_cert_manager() {
    log_info "Installing cert-manager for SSL certificate management"

    # Add Helm repo
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm repo update

    # Install/upgrade cert-manager
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.13.3 \
        --set installCRDs=true \
        --wait \
        --timeout=5m > /dev/null

    log_success "cert-manager installed successfully"

    # Wait for cert-manager to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
    log_success "cert-manager is ready"
}

# Deploy Shape Network with SSL
deploy_shape_network_ssl() {
    log_info "Deploying Shape Network with SSL support"

    if [ ! -d "./helm-chart/shape-network-node" ]; then
        log_error "Helm chart directory not found"
        exit 1
    fi

    # Export environment variables for Helm templating
    export DNS_FQDN
    export USER_EMAIL
    export DNS_LABEL

    log_info "Using DNS_FQDN: $DNS_FQDN"
    log_info "Using USER_EMAIL: $USER_EMAIL"
    log_info "Using DNS_LABEL: $DNS_LABEL"

    # Deploy Shape Network
    helm upgrade --install shape-network-node ./helm-chart/shape-network-node \
        --namespace shape-network \
        --create-namespace \
        --set ingress.enabled=true \
        --set ingress.className=nginx \
        --set ingress.tls.enabled=true \
        --set certManager.enabled=true \
        --set homepage.enabled=true \
        --set service.type=ClusterIP \
        --set ssl.domain="$DNS_FQDN" \
        --set ssl.email="$USER_EMAIL" \
        --set global.domain="$DNS_FQDN" \
        --set certManager.clusterIssuer.email="$USER_EMAIL" \
        --set ingress.hostname="$DNS_FQDN" \
        --wait \
        --timeout=15m > /dev/null

    log_success "Shape Network deployed with SSL configuration"

    # Wait for pods to be ready
    kubectl wait --for=condition=ready pod -l component=op-geth -n shape-network --timeout=600s
    kubectl wait --for=condition=ready pod -l component=op-node -n shape-network --timeout=600s
    kubectl wait --for=condition=ready pod -l component=homepage -n shape-network --timeout=300s

    log_success "All Shape Network pods are ready"

    # Wait for SSL certificate
    log_info "Waiting for SSL certificate to be issued..."
    kubectl wait --for=condition=ready certificate/shape-node-tls -n shape-network --timeout=600s 2>/dev/null || true

    if kubectl get certificate shape-node-tls -n shape-network -o jsonpath='{.status.conditions[0].status}' 2>/dev/null | grep -q "True"; then
        log_success "SSL certificate is ready"
    else
        log_warning "SSL certificate is still being processed (this is normal)"
    fi
}

# Test deployment
test_deployment() {
    log_info "Running comprehensive health checks..."

    # Run the healthcheck script
    if [ -f "./healthcheck.sh" ]; then
        ./healthcheck.sh
    else
        log_warning "healthcheck.sh not found, running basic tests"

        # Basic connectivity test
        if curl -s --max-time 10 "http://$DNS_FQDN" | grep -q "Hello"; then
            log_success "Homepage is accessible"
        else
            log_warning "Homepage not yet responding"
        fi

        # Basic RPC test for HTTP JSON-RPC
        local rpc_response=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
            "http://$DNS_FQDN:8545" \
            --max-time 10 2>/dev/null)

        if echo "$rpc_response" | grep -q "0x168"; then
            log_success "HTTP JSON-RPC is working (Chain ID: 0x168)"
        else
            log_warning "HTTP JSON-RPC not yet responding"
        fi

        # Basic WebSocket test
        local ws_response=$(curl -s -I \
            -H "Connection: Upgrade" \
            -H "Upgrade: websocket" \
            -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
            -H "Sec-WebSocket-Version: 13" \
            "http://$DNS_FQDN:8546" \
            --max-time 10 2>/dev/null)

        if echo "$ws_response" | grep -q "101 Switching Protocols"; then
            log_success "WebSocket is working"
        else
            log_warning "WebSocket not yet responding"
        fi
    fi
}



# Interactive menu
show_menu() {
    echo ""
    log_header "═══════════════════════════════════════════════════════════════"
    log_header "🚀 Shape Network Unified Installation Menu"
    log_header "═══════════════════════════════════════════════════════════════"
    echo ""
    echo -e "${BLUE}Please select what you want to install:${NC}"
    echo ""
    echo -e "${GREEN}1)${NC} ${CYAN}Azure Infrastructure${NC}"
    echo "   └── Resource Group, AKS Cluster, Static IP, NSG Rules"
    echo ""
    echo -e "${GREEN}2)${NC} ${CYAN}Shape Network + SSL${NC}"
    echo "   └── NGINX Ingress, Shape Network Pods, Services, SSL Certificates"
    echo ""
    echo -e "${GREEN}3)${NC} ${CYAN}Complete Setup (1 + 2)${NC}"
    echo "   └── Full end-to-end deployment with SSL"
    echo ""
    echo -e "${GREEN}4)${NC} ${CYAN}Cleanup${NC}"
    echo "   └── Remove all Shape Network resources"
    echo ""
    echo -e "${GREEN}5)${NC} ${CYAN}Exit${NC}"
    echo ""
    echo -n "Enter your choice [1-5]: "
}

# Azure Infrastructure Installation
install_azure_infrastructure() {
    log_header "🏗️  Installing Azure Infrastructure"
    echo ""

    # Prompt for DNS configuration if not already set
    prompt_dns_config

    log_info "This will create:"
    log_info "• Resource Group: $RESOURCE_GROUP"
    log_info "• AKS Cluster: $AKS_CLUSTER"
    log_info "• Static IP: $STATIC_IP_NAME"
    log_info "• Network Security Group rules"
    echo ""

    read -p "Continue with Azure infrastructure installation? [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_warning "Azure infrastructure installation cancelled"
        return 1
    fi

    echo ""
    check_prerequisites
    create_resource_group
    create_aks_cluster
    configure_kubectl
    create_static_ip
    configure_azure_ports

    log_success "🎉 Azure Infrastructure deployment completed!"
    echo ""
    log_info "Next: Run option 2 to deploy Shape Network with SSL"
    echo ""

    save_user_configuration
}

# Shape Network + SSL Installation
install_shape_network_ssl() {
    log_header "⚙️  Installing Shape Network + SSL"
    echo ""

    # Check if we have DNS configuration from Azure infrastructure
    if [ -z "$DNS_FQDN" ]; then
        log_error "❌ DNS configuration not found!"
        log_error "Please run option 1 (Azure Infrastructure) first to create the DNS configuration."
        return 1
    fi

    log_success "✅ Using DNS: $DNS_FQDN"

    # Prompt for email configuration if not already set
    prompt_email_config

    # Check if infrastructure exists (optional for Shape Network only deployment)
    local infra_exists=true
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "⚠️  Azure infrastructure not found, deploying Shape Network only..."
        infra_exists=false
    elif ! az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER" &> /dev/null; then
        log_warning "⚠️  AKS cluster not found, deploying Shape Network only..."
        infra_exists=false
    fi

    if [ "$infra_exists" = true ]; then
        # Get existing configuration
        NODE_RESOURCE_GROUP=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER" --query nodeResourceGroup -o tsv)

        if az network public-ip show --resource-group "$NODE_RESOURCE_GROUP" --name "$STATIC_IP_NAME" &> /dev/null; then
            STATIC_IP=$(az network public-ip show --resource-group "$NODE_RESOURCE_GROUP" --name "$STATIC_IP_NAME" --query ipAddress -o tsv)
            log_success "✅ Found static IP: $STATIC_IP"
        fi
    fi

    log_info "This will install:"
    log_info "• NGINX Ingress Controller"
    log_info "• cert-manager for SSL certificates"
    log_info "• Shape Network (op-geth + op-node)"
    log_info "• Homepage pod"
    log_info "• SSL certificates from Let's Encrypt"
    echo ""

    read -p "Continue with Shape Network + SSL installation? [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_warning "Shape Network + SSL installation cancelled"
        return 1
    fi

    echo ""
    if [ "$infra_exists" = true ]; then
        configure_kubectl
    fi
    install_nginx_ingress
    install_cert_manager
    deploy_shape_network_ssl
    test_deployment

    log_success "🎉 Shape Network + SSL deployment completed!"
    echo ""
    log_info "🌐 Secure Endpoints:"
    log_info "Homepage: https://$DNS_FQDN"
    log_info "WebSocket: wss://$DNS_FQDN"
    echo ""
    log_info "🔍 Run: ./healthcheck.sh  # Comprehensive health checks"
    echo ""

    save_user_configuration
}

# Complete setup
install_complete_setup() {
    log_header "🚀 Complete Shape Network Setup"
    echo ""

    # Prompt for DNS configuration if not already set
    prompt_dns_config

    # Prompt for email configuration if not already set
    prompt_email_config

    log_info "This will perform a complete end-to-end deployment:"
    log_info "1. Azure Infrastructure"
    log_info "2. Shape Network + SSL Certificates"
    echo ""

    read -p "Continue with complete setup? [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_warning "Complete setup cancelled"
        return 1
    fi

    echo ""
    check_prerequisites
    create_resource_group
    create_aks_cluster
    configure_kubectl
    create_static_ip
    configure_azure_ports
    install_nginx_ingress
    install_cert_manager
    deploy_shape_network_ssl
    test_deployment

    log_success "🎉 Complete deployment finished!"
    echo ""
    log_info "📋 Complete Setup Summary:"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "AKS Cluster: $AKS_CLUSTER"
    log_info "Static IP: $STATIC_IP"
    log_info "DNS Name: $DNS_FQDN"
    echo ""
    log_info "🔒 Secure Endpoints:"
    log_info "Homepage: https://$DNS_FQDN"
    log_info "HTTP JSON-RPC: https://$DNS_FQDN"
    log_info "WebSocket: wss://$DNS_FQDN"
    echo ""
    log_info "🔍 Run: ./healthcheck.sh  # Full health checks"
    echo ""

    save_user_configuration
}

# Cleanup function for menu
cleanup_menu() {
    log_header "🧹 Cleanup Shape Network Resources"
    echo ""

    log_info "This will remove:"
    log_info "• shape-network namespace and all resources"
    log_info "• ingress-nginx namespace and cluster resources"
    log_info "• cert-manager namespace and cluster resources"
    log_info "• All Helm releases"
    log_info "• Cluster roles and role bindings"
    log_info "• Webhook configurations"
    log_info "• IngressClass resources"
    log_info "• Persistent Volume Claims (PVCs)"
    log_info "• ConfigMaps and Secrets"
    log_info "• ServiceAccounts, Roles, and RoleBindings"
    log_info "• Jobs and custom resources"
    log_info "• Persistent Volume Claims (PVCs)"
    log_info "• ConfigMaps and Secrets"
    log_info "• ServiceAccounts, Roles, and RoleBindings"
    log_info "• Jobs and custom resources"
    echo ""

    read -p "Continue with cleanup? [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_warning "Cleanup cancelled"
        return 1
    fi

    echo ""
    cleanup_resources

    log_success "🎉 Cleanup completed!"
    echo ""
    log_info "The cluster is now clean and ready for a fresh installation."
    echo ""
}

# Main execution
main() {
    clear
    echo ""
    log_header "🚀 Shape Network Unified Installation Script"
    log_header "═══════════════════════════════════════════════════════════════"
    log_info "Single point of entry for complete Shape Network deployment"
    log_info "Includes Azure infrastructure, Shape Network nodes, and SSL certificates"
    echo ""

    # Load or prompt for configuration
    load_or_prompt_config

    while true; do
        show_menu
        read choice

        case $choice in
            1)
                echo ""
                install_azure_infrastructure
                if [ $? -eq 0 ]; then
                    echo ""
                    read -p "Press Enter to return to menu..."
                fi
                ;;
            2)
                echo ""
                install_shape_network_ssl
                if [ $? -eq 0 ]; then
                    echo ""
                    read -p "Press Enter to return to menu..."
                fi
                ;;
            3)
                echo ""
                install_complete_setup
                if [ $? -eq 0 ]; then
                    echo ""
                    read -p "Press Enter to return to menu..."
                fi
                ;;
            4)
                echo ""
                cleanup_menu
                if [ $? -eq 0 ]; then
                    echo ""
                    read -p "Press Enter to return to menu..."
                fi
                ;;
            5)
                echo ""
                log_info "👋 Goodbye!"
                echo ""
                exit 0
                ;;
            *)
                echo ""
                log_error "❌ Invalid option. Please choose 1-5."
                echo ""
                read -p "Press Enter to continue..."
                ;;
        esac

        clear
        echo ""
        log_header "🚀 Shape Network Unified Installation Script"
        log_header "═══════════════════════════════════════════════════════════════"
        log_info "Single point of entry for complete Shape Network deployment"
        log_info "Includes Azure infrastructure, Shape Network nodes, and SSL certificates"
        echo ""
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
