# Aleo Privacy-First Automation - Key Concepts

## The Core Challenge: Record Ownership + Keeper Execution

**Problem:** User owns private record, but keeper needs to execute it. How?

### The Solution: Your 3-Function Pattern

Each task module follows this clean interface:

```leo
// 1. CHECK STATUS - Public, keeper calls this to find ready tasks
transition check_status(task_id: field) -> bool

// 2. CREATE - User calls to create task  
transition create_task(params...) -> (Receipt, Future)

// 3. EXECUTE - Keeper calls when check_status returns true
transition execute(task: TaskRecord, keeper: address) -> (Receipt, Future)
```

---

## The Real Pattern: Hybrid Public/Private

Given Aleo's constraints, here's the practical solution:

### Public Mappings (for keeper access):
```leo
mapping tasks: field => TaskData {
    owner: address,        // Public (keeper needs to verify)
    token_id: field,      // Public (for token transfer)
    amount: u128,         // Public (keeper needs this)
    next_execution: u32,   // Public (to check if ready)
    status: u8,           // Public
}
```

### Private Records (for receipts):
```leo
record TaskReceipt {
    owner: address,
    task_id: field,
    created_at: u32,
}
```

### Why This Works:

| Function | Where Data Lives | Who Can Access |
|----------|-----------------|----------------|
| `check_status()` | Mapping (public) | Keeper ✓ |
| `create_task()` | Mapping (written) | User → Keeper can read |
| `execute()` | Mapping (read+write) | Keeper ✓ |

---

## How It Works

```
┌──────────┐     ┌─────────────────┐     ┌─────────────┐
│  Keeper  │────▶│ check_status()  │     │   Public    │
│          │     │ returns: true   │     │  Mapping    │
└──────────┘     └────────┬────────┘     │  (tasks)    │
                          │              └──────┬──────┘
                          ▼                     │
                    ┌───────────────┐           │
                    │ execute()     │◀──────────┘
                    │ passes task   │
                    └───────┬───────┘
                            ▼
                    ┌───────────────┐     ┌─────────────┐
                    │ token transfer│────▶│   Token     │
                    │ via registry  │     │  Registry   │
                    └───────────────┘     └─────────────┘
```

1. Keeper scans tasks mapping
2. Calls `check_status(task_id)` - if true, task is ready
3. Keeper calls `execute()` with needed params
4. Program executes token transfer via token_registry
5. Keeper earns fee

---

## Privacy Trade-off

**Full Privacy** (records only): User must be online to execute - no automation

**This Approach**: Some data is public (amounts, addresses) but:
- Execution is automated (keeper does it)
- Receipts are private
- Conditions can be private (check_status can verify private inputs)

---

## Stop-Loss: Still Private!

For stop-loss, we keep the hashed price pattern:

```leo
mapping stop_orders: field => StopData {
    owner: address,
    token_pair: u64,
    amount: u128,
    stop_price_hash: field,  // HASH - not the actual price!
    // ...
}
```

Keeper sees:
- `stop_price_hash` - random field, meaningless
- Can't see actual stop price

This prevents liquidation hunting!
