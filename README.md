# Aleo Advanced Pay & Scheduled Transfers

A fully private, zero-knowledge automation and scheduled payment system built on the Aleo network using Leo 4.0.0. 

## Features
- **Native ALEO & USDCx Support**: Natively interacts with `credits.aleo` and `test_usdcx_stablecoin.aleo` in a single execution model.
- **Scheduled Transfers**: Schedule single transfers to execute at a specific future block height.
- **Recurring Payments**: Setup subscription-like transfers that execute multiple times at set block intervals.
- **Conditional Transfers**: Trigger transfers based on external data (like price feeds) verified by cryptographic Oracle signatures.
- **Multi-party Escrow**: Require multiple participants to cryptographically sign off before releasing funds.

## Architecture: Fully Private Record-Based Keeper System
In a zero-knowledge ecosystem, using public mappings or structs compromises user privacy. This system uses a **100% private Record architecture** to ensure only the User and the assigned Keeper have mathematical visibility over the tasks.

### Core Records
1. `TaskRecord`: Created by the user, but **owned by the Keeper**. This allows the Keeper to privately execute the task when the conditions are met. It contains the funds, `keeper_fee`, and execution rules.
2. `ReceiptRecord`: Created and **owned by the User**. This serves as a private proof of task creation and holds the `expiry_block`.
3. `CancelRecord`: Generated when a user requests cancellation using their `ReceiptRecord`. It is owned by the Keeper to authorize the refund.

### Secure Keeper Mechanism
The Keeper mechanism is designed to be trustless, economically viable, and secure against malicious actors:
1. **Economic Incentives**: Users define a `keeper_fee: u64` when creating a task. Upon successful execution, the Keeper automatically receives this fee as compensation for gas costs and computation.
2. **Replay Protection**: The `execute_transfer` logic is strictly split into `execute_one_time` (which completely consumes and destroys the `TaskRecord`) and `execute_recurring` (which consumes the record and mints the next interval record). This eliminates infinite replay attacks.
3. **Cryptographic Oracle Signatures**: Conditional transfers do not rely on arbitrary inputs. The Keeper must provide a cryptographic `signature` and `oracle_address` to prove the `current_price` is authentic before execution.
4. **Cryptographic Escrow Approvals**: Escrow approvals require a cryptographic signature from the `party_address` to prevent Keepers from unilaterally forging approvals.
5. **Escape Hatch (Liveness Deadlock Fix)**: If a Keeper goes offline or becomes malicious, the User's funds are not trapped. After the `expiry_block` passes, the User can call `force_refund` using their `ReceiptRecord`. This bypasses the Keeper, refunds the initial deposit and fee, and publicly marks the `task_id` in the `escape_hatch_cancelled` mapping to prevent the Keeper from double-spending if they come back online.

## Deployment & Build
Both contracts (`automation_advanced_transfer_v5.aleo` and `advanced_pay.aleo`) are compiled using Leo v4.0.0.

```bash
# Build base automation contract
cd /workspace
leo build

# Build advanced specific contract
cd /workspace/advanced_pay
leo build
```