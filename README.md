# Leotask - Advanced Scheduled Transfer System

A comprehensive automation platform for Aleo blockchain with support for recurring payments, conditional transfers, multi-party escrow, and USDCx token support.

## Features

### 🔄 Recurring Payments
- Execute transfers multiple times at regular intervals
- Automatic rescheduling after each execution
- Cancel remaining executions at any time

### ⚡ Conditional Transfers
- Execute only when specific conditions are met
- Price-based triggers (above/below threshold)
- Time-based triggers (block height)
- Cancel if conditions are never met

### 👥 Multi-Party Escrow
- Require approval from multiple parties before execution
- Configurable approval thresholds (up to 10 parties)
- Prevent single-party fraud
- Cancel before approval if needed

### 💰 USDCx Support
- Support for USDCx (Superfluid wrapper of USDC) tokens
- Configurable token program addresses
- Admin-controlled token management

### 🤖 Clean Keeper Bot Architecture
- Automatic task execution when conditions are met
- Support for all task types
- HTTP API for task management
- Process manager with auto-restart

### 🧪 Extensive Test Suite
- Comprehensive feature tests
- Edge case and boundary condition tests
- Stress testing with concurrent tasks
- HTML and text report generation

## Architecture

### Smart Contract (`src/main.leo`)

The Leo smart contract implements:

- **Task Management:** Create, execute, and cancel tasks
- **Escrow System:** Secure fund escrow with role-based access
- **Multi-Party Logic:** Approval tracking and verification
- **Token Support:** Multiple token types (ALEO, USDCx)

### Keeper Bot (`keeper-bot/`)

The keeper bot provides:

- **Task Execution:** Automatic execution when conditions are met
- **HTTP API:** RESTful API for task management
- **Process Management:** Auto-restart and health monitoring
- **Price Oracle:** Integration with price feeds for conditional transfers

### Test Suite (`keeper-bot/test_*.mjs`)

Comprehensive testing:

- **Feature Tests:** All new features
- **Edge Case Tests:** Error handling and boundary conditions
- **Stress Tests:** Concurrent task registration
- **Report Generation:** HTML and text reports

## Quick Start

### Prerequisites

1. **Leo Compiler** (v3.5.0+)
   ```bash
   leo --version
   ```

2. **snarkOS**
   ```bash
   snarkos --version
   ```

3. **Node.js** (v18+)
   ```bash
   node --version
   ```

4. **Aleo Testnet Account** with funds

### Installation

1. **Clone Repository:**
   ```bash
   git clone <repository-url>
   cd leotask
   ```

2. **Install Dependencies:**
   ```bash
   cd keeper-bot
   npm install
   ```

3. **Configure Environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

4. **Compile Smart Contract:**
   ```bash
   cd src
   leo build
   ```

5. **Deploy Smart Contract:**
   ```bash
   leo deploy --network testnet
   ```

6. **Start Keeper Bot:**
   ```bash
   cd keeper-bot
   npm start
   ```

## Usage

### One-Time Transfer

```javascript
const response = await fetch('http://localhost:3001/api/tasks/register', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    taskId: '0x1234567890abcdef',
    recipient: 'aleo1recipientaddress',
    amount: 1000000,  // 1 ALEO in microcredits
    triggerBlock: '1000',
    tokenType: 0,  // 0=ALEO, 1=USDCx
  }),
});
```

### Recurring Transfer

```javascript
const response = await fetch('http://localhost:3001/api/tasks/register-recurring', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    taskId: '0x1234567890abcdef',
    recipient: 'aleo1recipientaddress',
    amountPerExecution: 1000000,  // 1 ALEO per execution
    firstTriggerBlock: '1000',
    intervalBlocks: 100,  // Execute every 100 blocks
    maxExecutions: 10,    // Execute 10 times
    tokenType: 0,
  }),
});
```

### Conditional Transfer

```javascript
const response = await fetch('http://localhost:3001/api/tasks/register-conditional', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    taskId: '0x1234567890abcdef',
    recipient: 'aleo1recipientaddress',
    amount: 1000000,
    triggerBlock: '1000',
    conditionType: 1,  // 1=price_above, 2=price_below
    conditionValue: 50000,  // Price threshold
    tokenType: 0,
  }),
});
```

### Multi-Party Escrow

```javascript
// Create escrow
const createResponse = await fetch('http://localhost:3001/api/tasks/register-escrow', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    taskId: '0x1234567890abcdef',
    recipient: 'aleo1recipientaddress',
    amount: 10000000,  // 10 ALEO
    triggerBlock: '1000',
    requiredApprovals: 3,  // Need 3 approvals
    tokenType: 0,
  }),
});

// Approve escrow
const approveResponse = await fetch('http://localhost:3001/api/tasks/0x1234567890abcdef/approve', {
  method: 'POST',
});
```

## API Reference

### Task Registration

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/tasks/register` | POST | Register one-time transfer |
| `/api/tasks/register-recurring` | POST | Register recurring transfer |
| `/api/tasks/register-conditional` | POST | Register conditional transfer |
| `/api/tasks/register-escrow` | POST | Register multi-party escrow |

### Task Management

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/tasks` | GET | Get all tasks |
| `/api/tasks/:taskId` | GET | Get single task |
| `/api/tasks/type/:type` | GET | Get tasks by type (0-3) |
| `/api/tasks/:taskId/approve` | POST | Approve escrow |

### System

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Bot health status |

## Testing

### Run All Tests

```bash
cd keeper-bot
node run_all_tests.mjs
```

### Run Quick Tests

```bash
node run_all_tests.mjs --quick
```

### Generate HTML Report

```bash
node run_all_tests.mjs --report
```

### Run Specific Test Suites

```bash
# Feature tests
node test_all_features.mjs

# Edge case tests
node test_edge_cases.mjs

# Specific feature tests
node test_all_features.mjs --one-time
node test_all_features.mjs --recurring
node test_all_features.mjs --conditional
node test_all_features.mjs --escrow
node test_all_features.mjs --usdcx
node test_all_features.mjs --stress
```

## Configuration

### Environment Variables

Create a `.env` file in the `keeper-bot/` directory:

```env
# Required
PRIVATE_KEY=your_private_key_here

# Optional
PROGRAM_ID=automation_advanced_transferv4.aleo
NETWORK=testnet
NETWORK_ID=1
API_ENDPOINT=https://api.explorer.provable.com/v1/testnet
QUERY_ENDPOINT=https://api.explorer.provable.com/v1
BROADCAST_ENDPOINT=https://api.explorer.provable.com/v1/testnet/transaction/broadcast
BLOCK_INTERVAL=15000
API_PORT=3001
FRONTEND_ORIGIN=*
PRICE_ORACLE_URL=
```

## Task Types

### 0 - One-Time Transfer
Execute once when trigger block is reached.

### 1 - Recurring Transfer
Execute at intervals, reschedule after each execution.

### 2 - Conditional Transfer
Execute when both block height and price conditions are met.

### 3 - Multi-Party Escrow
Execute when block height is reached and all approvals are received.

## Token Types

### 0 - ALEO
Native Aleo token.

### 1 - USDCx
Superfluid wrapper of USDC token.

## Security

### Escrow Safety
- Funds are escrowed in the program's public balance
- Only the creator can cancel before approval
- Multi-party approval prevents single-party fraud

### Conditional Transfer Safety
- Price conditions are verified on-chain
- Keeper cannot execute if conditions are not met
- User can cancel if conditions are never met

### Recurring Payment Safety
- Total amount is escrowed upfront
- User can cancel remaining executions
- Keeper reschedules automatically

### Role-Based Access Control
- Admin role can update token programs and keeper address
- Keeper role can execute tasks
- Users can cancel their own tasks

## Architecture Details

### Smart Contract

The Leo smart contract implements:

1. **Task Management**
   - Create tasks with various types
   - Execute tasks when conditions are met
   - Cancel tasks before execution

2. **Escrow System**
   - Secure fund escrow
   - Role-based access control
   - Multi-party approval tracking

3. **Token Support**
   - Multiple token types
   - Configurable token programs
   - Admin-controlled updates

### Keeper Bot

The keeper bot provides:

1. **Task Execution**
   - Automatic execution when conditions are met
   - Support for all task types
   - Price oracle integration

2. **HTTP API**
   - RESTful API for task management
   - Health monitoring
   - Task querying

3. **Process Management**
   - Auto-restart on crash
   - Health monitoring
   - Log management

### Test Suite

Comprehensive testing:

1. **Feature Tests**
   - All new features
   - Integration tests
   - Stress tests

2. **Edge Case Tests**
   - Error handling
   - Boundary conditions
   - Concurrent operations

3. **Report Generation**
   - HTML reports
   - Text reports
   - Detailed error logs

## Future Enhancements

### Advanced Conditions
- Time-based conditions (execute after specific date)
- Block range conditions (execute within block range)
- Composite conditions (AND/OR logic)

### Token Swaps
- Swap tokens before transfer
- DEX integration
- Slippage protection

### Yield Farming
- Stake escrowed funds
- Distribute yield to users
- Auto-compound

### Governance
- DAO approval for large transfers
- Voting mechanism
- Proposal system

### Analytics
- Task execution history
- Performance metrics
- User statistics

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new features
5. Run the test suite
6. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

For questions or issues:
- Open an issue on GitHub
- Check the documentation in `plans/` directory
- Review the test suite for usage examples

## Acknowledgments

- Aleo team for the Leo language and snarkOS
- Superfluid protocol for USDCx support
- Community for feedback and testing
