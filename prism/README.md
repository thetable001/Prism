# Prism

A composable DeFi lending pool built on Stacks with event-driven architecture and functional composition principles.

## Overview

Prism is a sophisticated lending protocol that enables users to supply liquidity, borrow assets, and earn yield through an algorithmically managed interest rate model. The protocol features dynamic yield curves, risk management controls, and liquidation mechanisms to maintain pool health.

## Key Features

### 🏦 Core Lending Operations
- **Liquidity Supply**: Contribute tokens to earn yield based on pool utilization
- **Borrowing**: Take loans against collateral with dynamic interest rates
- **Collateral Management**: Lock and unlock security deposits with health checks
- **Debt Servicing**: Repay loans with accrued interest

### 📈 Dynamic Yield Model
- Utilization-based interest rates with configurable parameters
- Optimal utilization ratio targeting (default: 80%)
- Progressive rate increases with spike protection
- Real-time interest accrual using block timestamps

### 🛡️ Risk Management
- Health ratio monitoring (default: 75% minimum)
- Automated liquidation system with incentives
- Collateral seizure with liquidator rewards
- Treasury fee collection for protocol sustainability

### ⚙️ Governance Controls
- Yield curve parameter adjustment
- Risk control configuration
- Pool administration by owner

## Technical Architecture

### Smart Contract Design
- **Event-driven architecture** for efficient state management
- **Functional composition** with pure read-only functions
- **Scaled arithmetic** for precise financial calculations
- **Error handling** with comprehensive response codes

### Interest Rate Model
```
Base Rate + Utilization Rate × Slope + Spike Rate (if over optimal)
```

### Health Factor Calculation
```
Health Factor = (Collateral Value × Min Health Ratio) / Debt Amount
```

## Usage

### For Liquidity Providers

1. **Supply Liquidity**
   ```clarity
   (contribute-liquidity amount)
   ```
   - Earn yield based on pool utilization
   - Receive interest-bearing tokens
   - Withdraw anytime (subject to pool liquidity)

2. **Withdraw Liquidity**
   ```clarity
   (retrieve-liquidity amount)
   ```

### For Borrowers

1. **Deposit Collateral**
   ```clarity
   (lock-collateral security-amount)
   ```

2. **Borrow Assets**
   ```clarity
   (request-loan loan-amount)
   ```
   - Must maintain minimum health ratio
   - Interest accrues over time

3. **Repay Debt**
   ```clarity
   (service-debt payment-amount)
   ```

4. **Withdraw Collateral**
   ```clarity
   (unlock-collateral release-amount)
   ```

### For Liquidators

```clarity
(execute-liquidation target-borrower debt-coverage)
```
- Liquidate unhealthy positions
- Receive liquidation rewards
- Help maintain protocol stability

## Configuration

### Default Parameters

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| Base Yield | 2% | Minimum borrowing rate |
| Slope Coefficient | 10% | Rate increase per utilization |
| Spike Rate | 60% | Additional rate above optimal |
| Optimal Ratio | 80% | Target utilization |
| Health Ratio Min | 75% | Minimum collateralization |
| Liquidator Reward | 10% | Liquidation incentive |
| Treasury Cut | 10% | Protocol fee |

### Governance Functions

Only the pool owner can modify:
- Yield curve parameters
- Risk management controls
- Pool initialization

## Error Codes

| Code | Error | Description |
|------|-------|-------------|
| 201 | ACCESS_DENIED | Unauthorized operation |
| 202 | INVALID_PARAMS | Invalid input parameters |
| 203 | BALANCE_TOO_LOW | Insufficient balance |
| 204 | HEALTH_CHECK_FAILED | Health ratio violation |
| 205 | POOL_INACTIVE | Pool not operational |
| 206 | LIQUIDATION_NOT_ALLOWED | Position is healthy |
| 207 | BORROWER_NOT_FOUND | No borrowing position |
| 208 | OPERATION_FAILED | General operation failure |

## Security Features

- **Health monitoring** prevents over-leveraging
- **Liquidation mechanisms** protect pool solvency
- **Access controls** for governance functions
- **Input validation** for all operations
- **Safe arithmetic** prevents overflow/underflow

## View Functions

Query pool and account states:
- `compute-utilization-ratio`: Current pool utilization
- `derive-borrowing-cost`: Current borrowing rate
- `derive-supply-yield`: Current supply rate
- `calculate-supplier-balance`: User's supply balance
- `calculate-borrower-debt`: User's debt amount
- `assess-account-health`: Position health status

## Getting Started

1. Deploy the contract to Stacks blockchain
2. Initialize pool state with `initialize-pool-state`
3. Configure parameters via governance functions
4. Begin supplying liquidity and borrowing
