# USDCx Automation Hub - Architecture Design

## Overview

The USDCx Automation Hub is a comprehensive automation platform for USDCx (Superfluid wrapper of USDC) on Aleo blockchain. It provides recurring payments, conditional transfers, and multi-party escrow functionality.

## Features

### 1. One-Time USDCx Transfers

**Description:** Simple scheduled transfers that execute once when the trigger block is reached.

**Flow:**
1. User creates a scheduled transfer with recipient, amount, and trigger block
2. USDCx is escrowed in the program's public balance
3. User receives a `TaskAuth` record for cancellation
4. Keeper executes when trigger block is reached
5. USDCx is transferred to recipient

**Smart Contract Functions:**
- `create_one_time_transfer()` - Create a one-time transfer
- `execute_transfer()` - Execute the transfer
- `cancel_transfer()` - Cancel before execution

**API Endpoints:**
- `POST /api/tasks/register` - Register a one-time transfer

---

### 2. Recurring USDCx Payments

**Description:** Transfers that execute multiple times at regular intervals.

**Flow:**
1. User creates a recurring transfer with:
   - Amount per execution
   - First trigger block
   - Interval between executions
   - Maximum number of executions
2. Total amount is escrowed (amount_per_execution × max_executions)
3. User receives a `TaskAuth` record for cancellation
4. Keeper executes at each interval
5. After each execution, next trigger block is calculated
6. Task is removed after all executions complete

**Smart Contract Functions:**
- `create_recurring_transfer()` - Create a recurring transfer
- `execute_transfer()` - Execute and reschedule
- `cancel_transfer()` - Cancel remaining executions

**API Endpoints:**
- `POST /api/tasks/register-recurring` - Register a recurring transfer

**Example:**
```javascript
// Pay 100 USDCx every 100 blocks for 10 times
{
  taskId: "0x123",
  recipient: "aleo1...",
  amountPerExecution: 100000000,  // 100 USDCx in microcredits
  firstTriggerBlock: "1000",
  intervalBlocks: 100,
  maxExecutions: 10
}
```

---

### 3. Conditional USDCx Transfers

**Description:** Transfers that execute only when specific conditions are met.

**Condition Types:**
- `PRICE_ABOVE` (1): Execute when price is above threshold
- `PRICE_BELOW` (2): Execute when price is below threshold

**Flow:**
1. User creates a conditional transfer with:
   - Recipient and amount
   - Trigger block (earliest execution time)
   - Condition type and value
2. USDCx is escrowed
3. User receives a `TaskAuth` record for cancellation
4. Keeper monitors both block height and price
5. Transfer executes only when:
   - Block height >= trigger block
   - Price condition is met
6. If condition is not met, keeper waits and checks again

**Smart Contract Functions:**
- `create_conditional_transfer()` - Create a conditional transfer
- `execute_transfer()` - Execute with price verification
- `cancel_transfer()` - Cancel before execution

**API Endpoints:**
- `POST /api/tasks/register-conditional` - Register a conditional transfer

**Example:**
```javascript
// Sell 1000 USDCx when price drops below 0.95
{
  taskId: "0x456",
  recipient: "aleo1...",
  amount: 1000000000,  // 1000 USDCx
  triggerBlock: "1000",
  conditionType: 2,  // price_below
  conditionValue: 95000  // 0.95 in microcredits
}
```

---

### 4. Multi-Party USDCx Escrow

**Description:** Transfers that require approval from multiple parties before execution.

**Flow:**
1. Creator creates an escrow with:
   - Recipient and amount
   - Trigger block
   - Required number of approvals
2. USDCx is escrowed
3. Creator receives an `EscrowAuth` record
4. Creator adds parties to the escrow
5. Each party approves using their `EscrowAuth` record
6. Keeper executes only when:
   - Block height >= trigger block
   - All required approvals are received
7. If not approved, creator can cancel and reclaim USDCx

**Smart Contract Functions:**
- `create_multi_party_escrow()` - Create an escrow
- `add_escrow_party()` - Add a party to the escrow
- `approve_escrow()` - Approve the escrow
- `execute_transfer()` - Execute when approved
- `cancel_escrow()` - Cancel before approval

**API Endpoints:**
- `POST /api/tasks/register-escrow` - Register an escrow
- `POST /api/tasks/:taskId/approve` - Approve an escrow

**Example:**
```javascript
// Transfer 10000 USDCx, requires 3 out of 5 approvals
{
  taskId: "0x789",
  recipient: "aleo1...",
  amount: 10000000000,  // 10000 USDCx
  triggerBlock: "1000",
  requiredApprovals: 3
}
```

---

## Smart Contract Architecture

### Data Structures

```leo
record Task {
    owner: address,
    task_id: field,
    creator: address,
    recipient: address,
    amount: u128,
    trigger_block: u32,
    task_type: u8,           // 0=one-time, 1=recurring, 2=conditional, 3=escrow
    interval_blocks: u32,    // For recurring
    max_executions: u32,     // For recurring
    executions_completed: u32, // For recurring
    condition_type: u8,      // 0=none, 1=price_above, 2=price_below
    condition_value: u64,    // For conditional
    required_approvals: u8,  // For escrow
    approvals_received: u8,  // For escrow
    is_approved: bool,       // For escrow
    is_active: bool,
    created_at: u32,
}

record TaskAuth {
    owner: address,
    task_id: field,
    amount: u128,
    task_type: u8,
}

record EscrowAuth {
    owner: address,
    task_id: field,
    party_address: address,
    amount: u128,
    has_approved: bool,
}
```

### Mappings

```leo
mapping orchestrator: bool => address;           // Admin address
mapping keepers: address => bool;                // Keeper addresses
mapping tasks: field => Task;                    // Task information
mapping task_counter: bool => u64;               // Task counter
mapping escrow_approvals: field => bool;         // Escrow approvals
mapping escrow_parties: field => bool;           // Escrow parties
```

### Constants

```leo
const USDCX_TOKEN_ID: field = 7000field;         // Routes to test_usdcx_stablecoin.aleo
const TASK_TYPE_ONE_TIME: u8 = 0u8;
const TASK_TYPE_RECURRING: u8 = 1u8;
const TASK_TYPE_CONDITIONAL: u8 = 2u8;
const TASK_TYPE_ESCROW: u8 = 3u8;
const CONDITION_NONE: u8 = 0u8;
const CONDITION_PRICE_ABOVE: u8 = 1u8;
const CONDITION_PRICE_BELOW: u8 = 2u8;
```

---

## Keeper Bot Architecture

### Task Types

The keeper bot supports four task types:

1. **One-Time (0):** Execute once when trigger block is reached
2. **Recurring (1):** Execute at intervals, reschedule after each execution
3. **Conditional (2):** Execute when both block height and price conditions are met
4. **Escrow (3):** Execute when block height is reached and all approvals are received

### Execution Logic

```javascript
async function checkAndExecute() {
  for (const task of taskStore.values()) {
    // Check block height
    if (currentBlock < task.triggerBlock) continue;
    
    // Check task-specific conditions
    if (task.taskType === TASK_TYPES.CONDITIONAL) {
      if (!checkPriceCondition(task)) continue;
    }
    
    if (task.taskType === TASK_TYPES.ESCROW) {
      if (!task.isApproved) continue;
    }
    
    // Execute task
    await executeTask(task);
    
    // Handle recurring tasks
    if (task.taskType === TASK_TYPES.RECURRING) {
      rescheduleRecurringTask(task);
    }
  }
}
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/tasks/register` | POST | Register one-time transfer |
| `/api/tasks/register-recurring` | POST | Register recurring transfer |
| `/api/tasks/register-conditional` | POST | Register conditional transfer |
| `/api/tasks/register-escrow` | POST | Register multi-party escrow |
| `/api/tasks/:taskId/approve` | POST | Approve escrow |
| `/api/tasks` | GET | Get all tasks |
| `/api/tasks/:taskId` | GET | Get single task |
| `/api/tasks/type/:type` | GET | Get tasks by type |
| `/health` | GET | Bot health status |

---

## Test Suite

### Feature Tests (`test_all_features.mjs`)

Tests all new features:
- One-time transfers
- Recurring transfers
- Conditional transfers
- Multi-party escrow
- Stress test with multiple concurrent tasks
- Task query API

**Usage:**
```bash
node test_all_features.mjs                    # Run all tests
node test_all_features.mjs --one-time         # Test one-time only
node test_all_features.mjs --recurring        # Test recurring only
node test_all_features.mjs --conditional      # Test conditional only
node test_all_features.mjs --escrow           # Test escrow only
node test_all_features.mjs --stress           # Stress test
```

---

## Security Considerations

### 1. Escrow Safety
- USDCx is escrowed in the program's public balance
- Only the creator can cancel before approval
- Multi-party approval prevents single-party fraud

### 2. Conditional Transfer Safety
- Price conditions are verified on-chain
- Keeper cannot execute if conditions are not met
- User can cancel if conditions are never met

### 3. Recurring Payment Safety
- Total amount is escrowed upfront
- User can cancel remaining executions
- Keeper reschedules automatically

### 4. Role-Based Access Control
- Admin role can add/remove keepers
- Keeper role can execute tasks
- Users can cancel their own tasks

---

## Future Enhancements

### 1. Advanced Conditions
- Time-based conditions (execute after specific date)
- Block range conditions (execute within block range)
- Composite conditions (AND/OR logic)

### 2. Token Swaps
- Swap tokens before transfer
- DEX integration
- Slippage protection

### 3. Yield Farming
- Stake escrowed funds
- Distribute yield to users
- Auto-compound

### 4. Governance
- DAO approval for large transfers
- Voting mechanism
- Proposal system

### 5. Analytics
- Task execution history
- Performance metrics
- User statistics

---

## Deployment

### Prerequisites
1. Leo compiler installed
2. snarkOS installed
3. Node.js installed
4. Aleo testnet account with funds

### Steps

1. **Compile Smart Contract:**
   ```bash
   cd src
   leo build
   ```

2. **Deploy Smart Contract:**
   ```bash
   leo deploy --network testnet
   ```

3. **Configure Keeper Bot:**
   ```bash
   cd keeper-bot
   cp .env.example .env
   # Edit .env with your private key and program ID
   ```

4. **Start Keeper Bot:**
   ```bash
   npm start
   ```

5. **Run Tests:**
   ```bash
   node test_all_features.mjs
   ```

---

## Conclusion

The USDCx Automation Hub provides a comprehensive automation platform for USDCx on Aleo blockchain with support for:
- One-time scheduled transfers
- Recurring payments
- Conditional transfers
- Multi-party escrow

The clean keeper bot architecture ensures reliable execution, while the extensive test suite provides confidence in the system's correctness and robustness.
