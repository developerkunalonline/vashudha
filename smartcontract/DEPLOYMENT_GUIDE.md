# HarvestMind Smart Contracts — Deployment & Integration Guide

## Files
- `HGCToken.sol` — ERC-20 token (HarvestGreen Credit)
- `ImpactRegistry.sol` — Immutable rescue audit trail + triggers minting
- `HGCMarketplace.sol` — Peer-to-peer HGC trading with 2% fee

---

## Step 1 — Wallets to create BEFORE deploying

You need 4 separate MetaMask wallets. Label them clearly:

| Wallet | Role |
|--------|------|
| DEPLOYER | Your main wallet. Deploys all contracts. Is the `owner`. |
| TREASURY | HarvestMind's 50% HGC accumulation wallet |
| BACKEND_HOT_WALLET | Your Railway.app backend signs transactions from here |
| FEE_WALLET | Receives 2% marketplace fees in MATIC |

Save all private keys securely. Fund DEPLOYER and BACKEND_HOT_WALLET with testnet MATIC from:
→ https://faucet.polygon.technology (select Amoy testnet)

---

## Step 2 — Deploy in this exact order on Remix IDE (remix.ethereum.org)

### Connect MetaMask to Polygon Amoy testnet
Network name: Polygon Amoy
RPC URL: https://rpc-amoy.polygon.technology
Chain ID: 80002
Currency: MATIC
Explorer: https://amoy.polygonscan.com

### Deploy Contract 1: HGCToken.sol
Constructor args:
- `_treasury` → paste your TREASURY wallet address
- `_minter`   → paste your BACKEND_HOT_WALLET address

**Save the deployed address → call it HGC_TOKEN_ADDRESS**

---

### Deploy Contract 2: ImpactRegistry.sol
Constructor args:
- `_hgcToken`  → paste HGC_TOKEN_ADDRESS
- `_recorder`  → paste BACKEND_HOT_WALLET address

**Save the deployed address → call it IMPACT_REGISTRY_ADDRESS**

---

### Deploy Contract 3: HGCMarketplace.sol
Constructor args:
- `_hgcToken`       → paste HGC_TOKEN_ADDRESS
- `_feeWallet`      → paste FEE_WALLET address
- `_floorPriceWei`  → 400000000000000000
  (= 0.4 MATIC per HGC, roughly ₹800 at current MATIC price)

**Save the deployed address → call it MARKETPLACE_ADDRESS**

---

### Final permission setup (IMPORTANT — do this or minting will fail)

After deploying, go to HGCToken in Remix and call:
```
setAuthorizedMinter(IMPACT_REGISTRY_ADDRESS)
```
This allows ImpactRegistry to mint HGC. Without this step, recording a rescue will fail.

---

## Step 3 — Environment variables for your backend (Railway.app)

```env
HGC_TOKEN_ADDRESS=0x...
IMPACT_REGISTRY_ADDRESS=0x...
MARKETPLACE_ADDRESS=0x...
BACKEND_PRIVATE_KEY=your_backend_hot_wallet_private_key
POLYGON_RPC_URL=https://rpc-amoy.polygon.technology
```

---

## Step 4 — Backend integration (Node.js / ethers.js)

Install: `npm install ethers`

### When NGO taps "I've Delivered It":

```javascript
import { ethers } from 'ethers';

const provider = new ethers.JsonRpcProvider(process.env.POLYGON_RPC_URL);
const signer   = new ethers.Wallet(process.env.BACKEND_PRIVATE_KEY, provider);

const REGISTRY_ABI = [
  "function recordRescue(string rescueId, string donorName, address donorWallet, string ngoName, uint256 kgRescued) external"
];

const registry = new ethers.Contract(
  process.env.IMPACT_REGISTRY_ADDRESS,
  REGISTRY_ABI,
  signer
);

async function onDeliveryConfirmed(rescue) {
  const tx = await registry.recordRescue(
    rescue.id,           // e.g. "rescue_0042"
    rescue.donorName,    // e.g. "Hotel Pearl Palace"
    rescue.donorWallet,  // restaurant's custodial wallet
    rescue.ngoName,      // e.g. "Akshaya Patra"
    rescue.kgRescued     // e.g. 40
  );

  const receipt = await tx.wait();
  
  // Save tx hash to Supabase for the Impact Certificate
  await supabase.from('rescues').update({
    blockchain_tx: receipt.hash,
    hgc_minted: true
  }).eq('id', rescue.id);
  
  return receipt.hash; // Show on Impact Certificate
}
```

### When company retires credits:

```javascript
const HGC_ABI = [
  "function retire(uint256 amount, string reason) external"
];

const hgc = new ethers.Contract(process.env.HGC_TOKEN_ADDRESS, HGC_ABI, signer);

async function retireCredits(companyWallet, hgcAmount, reason) {
  // Company must have approved signer to act on their behalf first
  // OR: use company's own signer if they connect MetaMask
  const tx = await hgc.retire(
    ethers.parseUnits(hgcAmount.toString(), 18),
    reason  // e.g. "TCS Q3 2025 ESG Report"
  );
  return await tx.wait();
}
```

---

## Step 5 — Reading data for Impact Certificate (frontend)

```javascript
const REGISTRY_ABI_READ = [
  "function getRescue(string rescueId) view returns (tuple(string,string,address,string,uint256,uint256,uint256,uint256,uint256,bool,string))",
  "function getGlobalImpact() view returns (uint256,uint256,uint256,uint256)"
];

const registry = new ethers.Contract(IMPACT_REGISTRY_ADDRESS, REGISTRY_ABI_READ, provider);

// Fetch a specific rescue for certificate page
const record = await registry.getRescue("rescue_0042");

// Fetch global counters for command center dashboard
const [totalRescues, totalKg, totalMeals, totalCO2] = await registry.getGlobalImpact();
```

---

## Verify contracts on Polygonscan (for judge credibility)

1. Go to https://amoy.polygonscan.com
2. Search your contract address
3. Click "Contract" tab → "Verify and Publish"
4. Select: Solidity (Single file), version 0.8.20, MIT license
5. Paste the source code
6. Submit — contract is now publicly readable on-chain

This shows judges full transparency. Anyone can verify no pre-minting happened.

---

## Carbon Math Summary (for judges)

| Input | Calculation | Output |
|-------|------------|--------|
| 40 kg rescued | × 2.5 | 100 kg CO₂ prevented |
| 100 kg CO₂ | ÷ 1000 | 0.1 tonnes CO₂ |
| 0.1 tonnes CO₂ | = | 0.1 HGC minted |
| 0.1 HGC | ÷ 2 | 0.05 HGC to restaurant |
| 0.1 HGC | ÷ 2 | 0.05 HGC to treasury |
| 0.05 HGC | × ₹800 floor | ₹40 minimum earned by restaurant |
