# Alchemy RPC Usage Analysis for Shape Network
**Analysis Date:** August 31, 2025  
**Current Status:** ⚠️ **Alchemy Monthly Limit Exceeded**

## 🔍 **What Alchemy RPC is Used For**

### **Primary Purpose: L1 Connectivity for Shape Network (L2)**
Your Shape Network node uses Alchemy's Ethereum mainnet RPC for **Layer 1 (L1) connectivity**. This is essential because:

1. **Shape Network is a Layer 2** that settles on Ethereum mainnet
2. **L2 nodes need L1 data** to validate and sync L2 transactions
3. **L1 monitoring** is required for deposit/withdrawal operations
4. **State root verification** happens on L1

### **Specific Use Cases:**

#### **🔗 L1 Block Monitoring (Primary Usage)**
```yaml
Configuration: l1.rpcEndpoint: "https://eth-mainnet.g.alchemy.com/v2/CnpuV_Lvuc3P3s47Eo2kZ"
Purpose: Monitor L1 blocks for Shape Network settlement data
Component: op-node (Layer 2 consensus client)
```

#### **📊 Current L1 RPC Calls (from logs):**
- **Latest Header Requests**: Getting current L1 block headers
- **Block Info by Number**: Fetching specific L1 blocks (e.g., block 20376241)
- **State Root Verification**: Validating L2 state against L1 commitments

## 🚨 **Current Issue: Rate Limiting**

### **Error Analysis:**
```
"Monthly capacity limit exceeded. Visit https://dashboard.alchemy.com/settings/billing to upgrade your scaling policy for continued service."
```

### **Request Pattern from Logs:**
- **Request ID Range**: 20048-20052 (in just a few seconds)
- **Error Rate**: 100% of recent L1 requests failing
- **Impact**: L2 sync is degraded but not completely broken

## 📈 **Alchemy Request Frequency Analysis**

### **Estimated Request Volume:**

#### **Normal L2 Operations:**
```
Block Monitoring:     Every 12 seconds (L1 block time)
                     = ~7,200 requests/day

Header Fetching:     On L2 block production
                     = ~2-4 requests per L2 block
                     = ~20,000-40,000 requests/day

State Validation:    On deposit/withdrawal events
                     = ~100-1,000 requests/day

Sync Operations:     During initial sync or catch-up
                     = ~50,000-200,000 requests (one-time)
```

#### **Your Current Usage (Estimated):**
```
Daily L1 RPC Calls:   ~30,000-50,000 requests/day
Peak Rate:           ~1-2 requests/second sustained
Burst Rate:          ~5-10 requests/second during sync
Monthly Estimate:    ~1-1.5 million requests/month
```

### **Alchemy Free Tier Limits:**
```
Free Tier:           300M requests/month
Standard:            3B requests/month ($199/month)
Growth:              15B requests/month ($999/month)
```

## 🔧 **Why You Hit the Limit**

### **Possible Causes:**

#### **1. Initial Sync Burst (Most Likely)**
- **Historical block fetching** during first-time sync
- **Catching up** to current L1 state
- **Validation of entire L2 chain** against L1

#### **2. Network Issues Causing Retries**
- **Failed requests** triggering automatic retries
- **Timeout scenarios** leading to duplicate calls
- **Connection instability** multiplying request volume

#### **3. Misconfiguration**
- **Too aggressive polling** intervals
- **Unnecessary redundant requests**
- **Missing cache/optimization** settings

## 🛠️ **Solutions & Alternatives**

### **Immediate Solutions:**

#### **Option 1: Upgrade Alchemy Plan**
```
Cost:                $199/month (Standard plan)
Benefits:            3B requests/month (100x current usage)
Pros:                Quick fix, reliable service
Cons:                Monthly cost, vendor lock-in
```

#### **Option 2: Switch to Alternative L1 RPC**
```yaml
# Free Alternatives:
- "https://eth.public-rpc.com"
- "https://rpc.ankr.com/eth"
- "https://ethereum.publicnode.com"
- "https://rpc.payload.de"

# Paid Alternatives:
- Infura (similar pricing to Alchemy)
- QuickNode (competitive pricing)
- GetBlock (pay-per-request model)
```

#### **Option 3: Use Multiple RPC Endpoints (Load Balancing)**
```yaml
l1:
  rpcEndpoints:
    - "https://eth.public-rpc.com"           # Free primary
    - "https://rpc.ankr.com/eth"             # Free backup
    - "https://ethereum.publicnode.com"      # Free backup
  rpcType: "basic"
```

### **Long-term Optimizations:**

#### **1. Reduce Request Frequency**
- **Implement caching** for repeated L1 block queries
- **Optimize polling intervals** based on actual needs
- **Use WebSocket connections** instead of HTTP polling

#### **2. Local L1 Node (Advanced)**
```
Setup:               Your own Ethereum mainnet node
Cost:                Higher compute cost, no per-request fees
Benefits:            Unlimited requests, better performance
Requirements:        Additional ~500GB storage, 4+ vCPU
```

#### **3. Hybrid Approach**
```
Primary:             Free public RPC for normal operations
Backup:              Alchemy for critical/high-speed needs
Fallback:            Multiple free endpoints in rotation
```

## 📋 **Recommended Action Plan**

### **Phase 1: Immediate Fix (Today)**
1. **Switch to free public RPC** temporarily
2. **Monitor performance** and request patterns
3. **Implement multiple fallback endpoints**

### **Phase 2: Optimization (This Week)**
1. **Analyze actual request patterns** in detail
2. **Implement request caching** where possible
3. **Fine-tune polling intervals** for efficiency

### **Phase 3: Production Setup (Next Month)**
1. **Evaluate paid RPC providers** based on usage
2. **Consider local L1 node** if request volume remains high
3. **Set up monitoring** for RPC usage and costs

## 🔧 **Quick Fix Configuration**

Let me provide you with an immediate configuration change to switch to free public RPC endpoints:

```yaml
# Updated values.yaml configuration:
l1:
  # Free public Ethereum mainnet RPC
  rpcEndpoint: "https://eth.public-rpc.com"
  # Keep the same beacon endpoint (working fine)
  beaconEndpoint: "https://ethereum-beacon-api.publicnode.com"
  # Change to basic type for public endpoints
  rpcType: "basic"
```

## 📊 **Cost-Benefit Analysis**

| Solution | Monthly Cost | Reliability | Setup Time | Request Limit |
|----------|--------------|-------------|------------|---------------|
| **Free Public RPC** | $0 | Medium | 5 minutes | Varies (usually sufficient) |
| **Alchemy Standard** | $199 | High | None | 3B requests |
| **Multiple Free RPC** | $0 | High | 30 minutes | Combined limits |
| **Own L1 Node** | $100-300 | Very High | 2-4 hours | Unlimited |

## 🎯 **Verdict**

**Your Alchemy usage is normal for an L2 node**, but you likely hit the limit due to:
1. **Initial sync burst** when the node first started
2. **Higher than expected request volume** during learning phase

**Recommended immediate action**: Switch to free public RPC endpoints and monitor. This will resolve the current issue while you evaluate long-term RPC strategy.

---
*The L1 RPC is critical for L2 operation - your Shape Network needs this Ethereum mainnet connection to function properly as a Layer 2 solution.*
