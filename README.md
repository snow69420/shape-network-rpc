# Shape Network RPC Node

A complete Shape Network L2 blockchain node deployment solution for Azure Kubernetes Service (AKS) with automated SSL certificates, ingress routing, and comprehensive monitoring.

## 🌟 What is Shape Network?

Shape Network is an Optimism-based Layer 2 (L2) blockchain solution that provides:
- **High-performance transactions** with low fees
- **Ethereum compatibility** through the Optimism Bedrock architecture
- **Decentralized sequencing** for enhanced security
- **Fast finality** with optimistic rollups

This project deploys a full Shape Network node consisting of:
- **op-geth**: Execution client for processing transactions
- **op-node**: Sequencer node for L2 block production
- **NGINX Ingress**: Load balancer with SSL termination
- **cert-manager**: Automated SSL certificate management
- **Homepage**: Web interface displaying node status and endpoints

## 📁 Project Structure

```
shape-network-rpc/
├── 📄 README.md                 # This comprehensive guide
├── 📄 install.sh                # Interactive installation script
├── 📄 healthcheck.sh            # Simplified health monitoring (284 lines)
├── 📄 genesis.json              # Shape Network genesis configuration
├── 📄 rollup.json               # Rollup configuration
├── 📄 .shape-config             # Deployment configuration (generated)
├── 📄 .gitignore               # Git ignore rules (includes docs/)
├── 📁 helm-chart/               # Kubernetes Helm deployment charts
│   └── shape-network-node/
│       ├── 📄 Chart.yaml        # Helm chart metadata
│       ├── 📄 values.yaml       # Configuration values
│       └── 📁 templates/        # Kubernetes manifests
│           ├── 📄 op-geth-deployment.yaml
│           ├── 📄 op-node-deployment.yaml
│           ├── 📄 homepage-deployment.yaml
│           ├── 📄 ingress.yaml
│           ├── 📄 service.yaml
│           └── 📄 configmap.yaml
└── 📁 .git/                     # Git version control
```

**Note**: The `docs/` folder is now ignored by Git (added to `.gitignore`) and contains generated documentation files that are not tracked in version control.

## 🚀 Quick Start

### Prerequisites

Before deploying, ensure you have:
- **Azure CLI** (`az`) installed and logged in
- **kubectl** installed and configured
- **Helm** v3.x installed
- **Azure subscription** with permissions to create resources

### One-Command Deployment

```bash
# Clone the repository
git clone 
cd shape-network-rpc

# Run the interactive installer
./install.sh
```

The installer will guide you through:
1. Azure infrastructure setup (AKS cluster, static IP, NSG rules)
2. Shape Network deployment with SSL certificates
3. Health checks and endpoint verification

## 📋 Installation Scripts

### `install.sh` - Main Installation Script

**Interactive menu-driven deployment with multiple options:**

```bash
./install.sh
```

**Menu Options:**
1. **Azure Infrastructure** - Creates resource group, AKS cluster, static IP, NSG rules
2. **Shape Network + SSL** - Deploys NGINX ingress, Shape Network pods, SSL certificates
3. **Complete Setup** - Full end-to-end deployment (options 1 + 2)
4. **Cleanup** - Remove all Shape Network resources

**Features:**
- ✅ Automated Azure resource provisioning
- ✅ SSL certificate management with Let's Encrypt
- ✅ Multi-port ingress configuration (80, 443, 8545, 8546)
- ✅ Resource optimization for cost efficiency
- ✅ Comprehensive error handling and rollback

### `healthcheck.sh` - Simplified Health Monitoring Script

**Streamlined health checking focused on core functionality:**

```bash
# Basic health check
./healthcheck.sh

# Advanced options
./healthcheck.sh --domain your-domain.com --ip 192.168.1.100
./healthcheck.sh --help
```

**Core Checks Performed:**
- ✅ **SSL Certificate Test** - Basic HTTPS connectivity verification
- ✅ **RPC Endpoint Tests** - Domain RPC, Direct IP RPC, Auth RPC (if available)
- ✅ **Blockchain Status** - Chain ID, sync status, current block, peer count
- ✅ **Configuration Auto-Detection** - Reads from `.shape-config` file

**Key Features:**
- **Simplified Design**: Reduced from ~800 lines to ~284 lines
- **Focused Testing**: Core RPC, SSL, and blockchain functionality
- **Clean Output**: Color-coded results with clear test summaries
- **Error Resilience**: Continues testing even if individual tests fail
- **Auto-Configuration**: Detects domain/IP from config files or uses defaults

**Command-Line Options:**
```bash
./healthcheck.sh                    # Basic check with auto-detection
./healthcheck.sh --domain example.com    # Override domain
./healthcheck.sh --ip 192.168.1.100      # Override IP address
./healthcheck.sh --help                  # Show help information
```

## 🔧 Use Cases and Deployment Scenarios

### Scenario 1: Development Environment

**For testing and development:**

```bash
# Use the interactive installer
./install.sh

# Select option 1: Azure Infrastructure
# Select option 2: Shape Network + SSL
```

**Configuration:**
- Single-node AKS cluster (Standard_D2s_v3)
- Minimal resource allocation
- Development SSL certificates (Let's Encrypt staging)

### Scenario 2: Production Environment

**For production deployment:**

1. **Pre-deployment preparation:**
   ```bash
   # Update DNS settings in values.yaml
   # Configure production SSL certificates
   # Adjust resource limits for production load
   ```

2. **Deployment:**
   ```bash
   ./install.sh
   # Select option 3: Complete Setup
   ```

3. **Post-deployment:**
   ```bash
   # Run comprehensive health checks
   ./healthcheck.sh

   # Monitor sync status
   curl -X POST -H "Content-Type: application/json" \
     --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
     https://your-domain.com/rpc
   ```

### Scenario 3: Custom Configuration

**For advanced users with specific requirements:**

1. **Modify Helm values:**
   ```bash
   # Edit helm-chart/shape-network-node/values.yaml
   # Customize resource limits, network settings, etc.
   ```

2. **Custom deployment:**
   ```bash
   helm upgrade --install shape-network-node ./helm-chart/shape-network-node \
     --namespace shape-network \
     --create-namespace \
     --set ingress.hostname="your-custom-domain.com" \
     --set resources.opGeth.requests.cpu="1000m"
   ```

## 🌐 Access Your Node

After successful deployment, your Shape Network node will be available at:

### Endpoints
- **Homepage**: `https://your-domain.com`
- **HTTP JSON-RPC**: `https://your-domain.com/rpc`
- **WebSocket**: `wss://your-domain.com/ws`

### Example RPC Calls

**Check sync status:**
```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  https://your-domain.com/rpc
```

**Get latest block:**
```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  https://your-domain.com/rpc
```

**Check peer count:**
```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  https://your-domain.com/rpc
```

## ⚙️ Configuration

### Core Configuration Files

- **`genesis.json`**: Shape Network genesis block and initial state
- **`rollup.json`**: L2 rollup configuration and parameters
- **`values.yaml`**: Helm deployment configuration

### Key Configuration Options

**Resource Allocation:**
```yaml
resources:
  opGeth:
    requests:
      memory: "2Gi"
      cpu: "400m"
    limits:
      memory: "3Gi"
      cpu: "800m"
```

**Network Configuration:**
```yaml
l1:
  rpcEndpoint: "https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
  beaconEndpoint: "https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
```

**SSL Configuration:**
```yaml
ssl:
  enabled: true
  domain: "your-domain.com"
  issuer: "letsencrypt-prod"
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

**Automated health monitoring:**
```bash
./healthcheck.sh
```

**Manual checks:**
```bash
# Check pod status
kubectl get pods -n shape-network

# Check logs
kubectl logs -n shape-network shape-node-op-node-XXXXX
kubectl logs -n shape-network shape-node-op-geth-XXXXX

# Check ingress
kubectl get ingress -n shape-network
```

### Common Issues

**Node not syncing:**
- Check L1 RPC provider connectivity
- Verify peer connections
- Review op-node logs for L1 fetch errors

**SSL certificate issues:**
- Verify DNS configuration
- Check cert-manager pod status
- Review certificate validity

**Resource constraints:**
- Monitor pod resource usage
- Adjust resource limits in values.yaml
- Consider scaling AKS node pool

## 📊 Performance Optimization

### Resource Optimization

**Recommended settings for different workloads:**

**Development:**
- CPU: 400m-800m per component
- Memory: 1Gi-2Gi per component
- Storage: 50Gi-100Gi

**Production:**
- CPU: 1000m-2000m per component
- Memory: 4Gi-8Gi per component
- Storage: 500Gi-1Ti

### Network Optimization

**Peer discovery:**
- Configured bootnodes for initial peer discovery
- Automatic peer management
- Optimized P2P port configuration

**RPC optimization:**
- Batched requests support
- WebSocket for real-time updates
- Connection pooling and rate limiting

## 🔒 Security Features

### SSL/TLS
- Automated Let's Encrypt certificates
- SSL redirect for secure connections
- Certificate auto-renewal

### Network Security
- Azure Network Security Groups (NSG)
- Kubernetes network policies
- Pod security contexts

### Access Control
- JWT authentication for op-node communication
- Restricted API access
- Secure configuration management

## � Recent Updates & Improvements

### Version 1.1.0 - September 2025

**Health Check Script Simplification:**
- ✅ **Simplified `healthcheck.sh`**: Reduced from ~800 lines to ~284 lines
- ✅ **Focused Core Functionality**: RPC endpoints, SSL, blockchain status
- ✅ **Improved Error Handling**: Continues testing on individual failures
- ✅ **Clean Output**: Removed redundant text, better formatting
- ✅ **Auto-Configuration**: Smart domain/IP detection from `.shape-config`

**Repository Organization:**
- ✅ **Git Ignore Updates**: Added `docs/` folder to `.gitignore`
- ✅ **Documentation Cleanup**: Removed tracked docs files from repository
- ✅ **File Consolidation**: Eliminated duplicate healthcheck files

**Key Improvements:**
- **Performance**: Faster health checks with focused testing
- **Reliability**: Better error handling and resilience
- **Maintainability**: Cleaner, more focused codebase
- **User Experience**: Clearer output and better documentation

### Configuration Management

**`.shape-config` File:**
The installer generates a configuration file that stores:
```bash
# Example .shape-config content
DNS_FQDN="your-domain.com"
STATIC_IP="192.168.1.100"
RESOURCE_GROUP="shape-network-rg"
AKS_CLUSTER="shape-network-cluster"
USER_EMAIL="admin@yourdomain.com"
```

**Auto-Detection Features:**
- Healthcheck script automatically reads from `.shape-config`
- Fallback to default values if config file missing
- Command-line overrides available for custom testing

## �📚 Documentation

**Note**: The `docs/` folder is now ignored by Git (added to `.gitignore`) and contains generated documentation files that are not tracked in version control. These files include:

- **SSL Implementation**: SSL certificate management and troubleshooting
- **RPC Analysis**: L1 RPC provider configuration and optimization
- **Port Configuration**: Network port mapping and firewall rules
- **Resource Usage**: Performance monitoring and optimization
- **Troubleshooting**: Common issues and resolution steps

**To view documentation locally:**
```bash
# List available documentation files
ls -la docs/

# View specific documentation
cat docs/README.md
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly with `./healthcheck.sh`
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues and questions:
1. Check the troubleshooting documentation in `docs/`
2. Run `./healthcheck.sh` for diagnostic information
3. Review pod logs for detailed error messages
4. Create an issue on GitHub with relevant logs

---

**Last Updated**: September 1, 2025
**Version**: 1.1.0
**Shape Network**: Mainnet
**Health Check**: Simplified (284 lines)
