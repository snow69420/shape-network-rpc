# Shape Network Port Configuration Documentation

## Overview
This document outlines all ports used by the Shape Network deployment on Azure AKS and the corresponding Azure infrastructure requirements.

## Architecture Summary
- **Azure AKS Cluster**: `shape-aks` in resource group `shape-network-rg`
- **Static IP**: `172.203.24.65` (shape-static-ip)
- **DNS**: `shape-mainnet-snow.eastus2.cloudapp.azure.com`
- **Load Balancer**: Azure LoadBalancer with NGINX Ingress Controller
- **Multi-port Architecture**: HTTP/HTTPS homepage + direct RPC/WebSocket access

## Port Mapping

### 🌐 External Ports (Internet → Azure LoadBalancer)

| Port | Protocol | Service | Description | Access URL |
|------|----------|---------|-------------|------------|
| **80** | TCP | Homepage | HTTP traffic to homepage pod | `http://172.203.24.65` |
| **443** | TCP | Homepage | HTTPS traffic to homepage pod | `https://172.203.24.65` |
| **8545** | TCP | JSON-RPC | Shape Network JSON-RPC endpoint | `http://172.203.24.65:8545` |
| **8546** | TCP | WebSocket | Shape Network WebSocket endpoint | `ws://172.203.24.65:8546` |

### 🔧 Internal Kubernetes Ports (Pod → Pod)

| Port | Protocol | Service | Component | Description |
|------|----------|---------|-----------|-------------|
| **8545** | TCP | JSON-RPC | op-geth | Ethereum JSON-RPC API |
| **8546** | TCP | WebSocket | op-geth | Ethereum WebSocket API |
| **8551** | TCP | Auth RPC | op-geth | Authenticated RPC for op-node |
| **9545** | TCP | RPC | op-node | Optimism Node RPC |
| **9003** | TCP | P2P | op-node | Peer-to-peer networking |
| **39393** | TCP | P2P | op-geth | Peer-to-peer networking |
| **7300** | TCP | Metrics | op-node | Prometheus metrics |
| **6060** | TCP | Metrics | op-geth | Debug/metrics endpoint |
| **80** | TCP | HTTP | homepage | NGINX homepage pod |

### 🔍 Discovery Ports (P2P Networking)

| Port | Protocol | Service | Component | Description |
|------|----------|---------|-----------|-------------|
| **30301** | UDP | Discovery | bootnode | Ethereum node discovery |
| **30301** | TCP | Discovery | bootnode | Ethereum node discovery |

## Azure Infrastructure Requirements

### 1. Network Security Group (NSG) Rules

The following inbound rules must be configured in the AKS node resource group NSG:

```bash
# HTTP Homepage
Allow-HTTP-Homepage: Port 80, Protocol TCP, Priority 1080, Allow, Inbound

# HTTPS Homepage  
Allow-HTTPS-Homepage: Port 443, Protocol TCP, Priority 1443, Allow, Inbound

# JSON-RPC
Allow-JSON-RPC-Shape: Port 8545, Protocol TCP, Priority 9545, Allow, Inbound

# WebSocket
Allow-WebSocket-Shape: Port 8546, Protocol TCP, Priority 9546, Allow, Inbound
```

### 2. Azure LoadBalancer Configuration

The NGINX Ingress Controller LoadBalancer service must expose these ports:

```yaml
ports:
  - name: http
    port: 80
    targetPort: 80
    protocol: TCP
  - name: https
    port: 443
    targetPort: 443
    protocol: TCP
  - name: rpc-http
    port: 8545
    targetPort: 8545
    protocol: TCP
  - name: rpc-ws
    port: 8546
    targetPort: 8546
    protocol: TCP
```

### 3. NGINX TCP Stream Configuration

NGINX Ingress Controller requires TCP stream configuration for direct port forwarding:

```yaml
tcp:
  8545: "shape-network/shape-node-op-geth:8545"
  8546: "shape-network/shape-node-op-geth:8546"
```

## Service Mapping

### Kubernetes Services

1. **Homepage Service** (`homepage`)
   - ClusterIP: Internal cluster communication
   - Port 80 → homepage pod port 80

2. **op-geth Service** (`shape-node-op-geth`)
   - ClusterIP: Internal cluster communication
   - Port 8545 → op-geth pod port 8545 (JSON-RPC)
   - Port 8546 → op-geth pod port 8546 (WebSocket)
   - Port 8551 → op-geth pod port 8551 (Auth RPC)

3. **op-node Service** (`shape-node-op-node`)
   - ClusterIP: Internal cluster communication
   - Port 9545 → op-node pod port 9545 (RPC)

4. **NGINX Ingress Service** (`ingress-nginx-controller`)
   - LoadBalancer: External traffic entry point
   - Static IP: 172.203.24.65
   - Ports: 80, 443, 8545, 8546

## Traffic Flow

### HTTP/HTTPS Traffic (Ports 80/443)
```
Internet → Azure LoadBalancer:80/443 → NGINX Ingress:80/443 → Homepage Pod:80
```

### JSON-RPC Traffic (Port 8545)
```
Internet → Azure LoadBalancer:8545 → NGINX TCP Stream:8545 → op-geth Pod:8545
```

### WebSocket Traffic (Port 8546)
```
Internet → Azure LoadBalancer:8546 → NGINX TCP Stream:8546 → op-geth Pod:8546
```

### Internal Communication
```
op-node Pod:8551 → op-geth Pod:8551 (Auth RPC)
External Peers → op-node Pod:9003 (P2P)
External Peers → op-geth Pod:39393 (P2P)
```

## Verification Commands

### 1. Check Azure Infrastructure
```bash
# Run the automated check script
./check-azure-ports.sh

# Manual NSG check
az network nsg rule list --resource-group MC_shape-network-rg_shape-aks_eastus2 --nsg-name aks-agentpool-*-nsg

# Manual LoadBalancer check
kubectl get svc ingress-nginx-controller -n ingress-nginx -o yaml
```

### 2. Test External Connectivity
```bash
# Homepage
curl http://172.203.24.65
curl http://shape-mainnet-snow.eastus2.cloudapp.azure.com

# JSON-RPC
curl -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://172.203.24.65:8545

# WebSocket (using wscat if available)
wscat -c ws://172.203.24.65:8546
```

### 3. Monitor Internal Services
```bash
# Check pod connectivity
kubectl get pods -n shape-network -o wide

# Check service endpoints
kubectl get svc -n shape-network

# Check NGINX configuration
kubectl get configmap tcp-services-configmap -n ingress-nginx -o yaml
```

## Troubleshooting

### Common Issues

1. **Port not accessible externally**
   - Check NSG rules in node resource group
   - Verify LoadBalancer service configuration
   - Ensure NGINX TCP stream configuration

2. **WebSocket connection fails**
   - Verify NGINX TCP stream is configured
   - Check that port 8546 is open in NSG
   - Ensure op-geth WebSocket is enabled

3. **Homepage not loading**
   - Check homepage pod status
   - Verify ingress configuration
   - Test homepage service directly

### Debug Commands

```bash
# Check all port configurations
grep -r "port\|Port" helm-chart/shape-network-node/

# Verify NSG rules
az network nsg rule list --resource-group MC_shape-network-rg_shape-aks_eastus2 --nsg-name <nsg-name> --query "[?direction=='Inbound' && access=='Allow']"

# Test internal connectivity
kubectl exec -it <pod-name> -n shape-network -- nc -zv shape-node-op-geth 8545

# Check NGINX logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

## Security Considerations

1. **Port Exposure**: Only necessary ports (80, 443, 8545, 8546) are exposed externally
2. **Internal Communication**: All internal services use ClusterIP (not exposed)
3. **Authentication**: op-geth auth RPC (8551) is internal-only with JWT authentication
4. **Monitoring**: Metrics ports (7300, 6060) are internal-only

## Future Enhancements

1. **SSL/TLS**: Add cert-manager for automatic SSL certificates
2. **Rate Limiting**: Implement rate limiting on RPC endpoints
3. **DDoS Protection**: Consider Azure DDoS Protection Standard
4. **WAF**: Add Web Application Firewall for additional security
5. **VPN**: Consider VPN access for administrative endpoints

---

**Generated**: $(date)
**Version**: Shape Network v1.0 on Azure AKS
**Architecture**: Multi-port LoadBalancer with NGINX Ingress Controller
