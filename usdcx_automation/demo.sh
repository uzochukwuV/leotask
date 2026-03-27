#!/bin/bash
# ============================================================
# USDCx Automation Hub — Demo Script
# ============================================================
# This script demonstrates the complete USDCx automation flow
# including one-time, recurring, conditional, and multi-party
# escrow transfers.
#
# Usage:
#   ./demo.sh                  — full run (all features)
#   ./demo.sh --one-time       — test one-time transfers only
#   ./demo.sh --recurring      — test recurring transfers only
#   ./demo.sh --conditional    — test conditional transfers only
#   ./demo.sh --escrow         — test multi-party escrow only
#   ./demo.sh --skip-init      — skip initialization
# ============================================================
set -e

# ─── FLAGS ───────────────────────────────────────────────────
SKIP_INIT=false
ONE_TIME=false
RECURRING=false
CONDITIONAL=false
ESCROW=false
ALL=true

for arg in "$@"; do
    case "$arg" in
        --skip-init)     SKIP_INIT=true ;;
        --one-time)      ONE_TIME=true; ALL=false ;;
        --recurring)     RECURRING=true; ALL=false ;;
        --conditional)   CONDITIONAL=true; ALL=false ;;
        --escrow)        ESCROW=true; ALL=false ;;
    esac
done

# ─── CONFIG ──────────────────────────────────────────────────
NETWORK="testnet"
ENDPOINT="https://api.explorer.provable.com/v1"
PROGRAM="usdcx_automation_hub.aleo"
USDCX_PROGRAM="test_usdcx_stablecoin.aleo"

# Admin/Keeper private key (from environment or default)
PRIVATE_KEY="${ALEO_PRIVATE_KEY:-APrivateKey1zkpEhfACCK6CjuLej9PveR9tVJbpaL53snntqkeTqznng1W}"
ADDRESS="${ALEO_ADDRESS:-aleo1hjr3xkvwtkuafnmn8273vd7najxd00gmqseuccj2f50q2ep9dcyq8w8exf}"

# Keeper address (same as admin for demo)
KEEPER_ADDRESS="$ADDRESS"

# Recipient address (different from keeper for demo)
RECIPIENT_ADDRESS="aleo1testrecipient1234567890abcdefghijklmnopqrstuvwxyz"

# USDCx token ID
USDCX_TOKEN_ID="7000field"

# Demo parameters
AMOUNT_ONE_TIME="1000000u128"      # 1 USDCx
AMOUNT_RECURRING="500000u128"      # 0.5 USDCx per execution
AMOUNT_CONDITIONAL="2000000u128"   # 2 USDCx
AMOUNT_ESCROW="5000000u128"        # 5 USDCx

# Block parameters (adjust based on current block height)
TRIGGER_BLOCK_ONE_TIME="1000u32"
TRIGGER_BLOCK_RECURRING="1000u32"
TRIGGER_BLOCK_CONDITIONAL="1000u32"
TRIGGER_BLOCK_ESCROW="1000u32"

# Recurring parameters
INTERVAL_BLOCKS="100u32"
MAX_EXECUTIONS="3u32"

# Conditional parameters
CONDITION_TYPE="1u8"               # 1 = price_above
CONDITION_VALUE="50000u64"         # Price threshold

# Escrow parameters
REQUIRED_APPROVALS="3u8"

# ─── HELPERS ─────────────────────────────────────────────────
step()  { echo ""; echo "══════════════════════════════════════════"; echo "  $1"; echo "══════════════════════════════════════════"; }
info()  { echo "  ▸ $1"; }
ok()    { echo "  ✓ $1"; }
warn()  { echo "  ⚠ $1"; }
error() { echo "  ✗ $1"; }

# Run a transition on our deployed program
own_tx() {
    local func="$1"; shift
    leo execute \
        --network "$NETWORK" \
        --endpoint "$ENDPOINT" \
        --private-key "$PRIVATE_KEY" \
        --broadcast \
        -y \
        "$func" "$@"
}

# Run a transition and capture output
own_tx_capture() {
    local func="$1"; shift
    leo execute \
        --network "$NETWORK" \
        --endpoint "$ENDPOINT" \
        --private-key "$PRIVATE_KEY" \
        --broadcast \
        -y \
        "$func" "$@" 2>&1
}

# ─── BANNER ──────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║        USDCx Automation Hub — Demo Script                ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Program : $PROGRAM                  ║"
echo "║  Keeper  : ${KEEPER_ADDRESS:0:42}... ║"
echo "║  USDCx   : $USDCX_TOKEN_ID                          ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Features:                                               ║"
echo "║    • One-time scheduled transfers                        ║"
echo "║    • Recurring payments with intervals                   ║"
echo "║    • Conditional transfers (price-based)                 ║"
echo "║    • Multi-party escrow with approvals                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ─── STEP 1: INITIALIZE ─────────────────────────────────────
if [ "$SKIP_INIT" = false ]; then
    step "STEP 1 — Initialize Program"
    info "Adding keeper address..."
    
    own_tx add_keeper "$KEEPER_ADDRESS"
    ok "Keeper added"
    sleep 30
fi

# ─── STEP 2: ONE-TIME TRANSFER ───────────────────────────────
if [ "$ALL" = true ] || [ "$ONE_TIME" = true ]; then
    step "STEP 2 — One-Time USDCx Transfer"
    info "Function: create_one_time_transfer"
    info "Amount: $AMOUNT_ONE_TIME USDCx"
    info "Recipient: $RECIPIENT_ADDRESS"
    info "Trigger block: $TRIGGER_BLOCK_ONE_TIME"
    echo ""

    TIMESTAMP="$(date +%s)u32"

    info "Executing create_one_time_transfer..."
    info "Parameters:"
    info "  recipient: $RECIPIENT_ADDRESS"
    info "  amount: $AMOUNT_ONE_TIME"
    info "  trigger_block: $TRIGGER_BLOCK_ONE_TIME"
    info "  timestamp: $TIMESTAMP"
    echo ""

    ONE_TIME_OUTPUT="$(own_tx_capture create_one_time_transfer \
        "$RECIPIENT_ADDRESS" \
        "$AMOUNT_ONE_TIME" \
        "$TRIGGER_BLOCK_ONE_TIME" \
        "$TIMESTAMP")"

    echo "$ONE_TIME_OUTPUT"

    if echo "$ONE_TIME_OUTPUT" | grep -q "Transaction rejected"; then
        error "One-time transfer transaction was REJECTED on-chain."
        exit 1
    else
        ok "One-time transfer created! Task and Auth records generated."
    fi
    echo ""
    sleep 30
fi

# ─── STEP 3: RECURRING TRANSFER ──────────────────────────────
if [ "$ALL" = true ] || [ "$RECURRING" = true ]; then
    step "STEP 3 — Recurring USDCx Transfer"
    info "Function: create_recurring_transfer"
    info "Amount per execution: $AMOUNT_RECURRING USDCx"
    info "Recipient: $RECIPIENT_ADDRESS"
    info "First trigger block: $TRIGGER_BLOCK_RECURRING"
    info "Interval: $INTERVAL_BLOCKS blocks"
    info "Max executions: $MAX_EXECUTIONS"
    echo ""

    TIMESTAMP="$(date +%s)u32"

    info "Executing create_recurring_transfer..."
    info "Parameters:"
    info "  recipient: $RECIPIENT_ADDRESS"
    info "  amount_per_execution: $AMOUNT_RECURRING"
    info "  first_trigger_block: $TRIGGER_BLOCK_RECURRING"
    info "  interval_blocks: $INTERVAL_BLOCKS"
    info "  max_executions: $MAX_EXECUTIONS"
    info "  timestamp: $TIMESTAMP"
    echo ""

    RECURRING_OUTPUT="$(own_tx_capture create_recurring_transfer \
        "$RECIPIENT_ADDRESS" \
        "$AMOUNT_RECURRING" \
        "$TRIGGER_BLOCK_RECURRING" \
        "$INTERVAL_BLOCKS" \
        "$MAX_EXECUTIONS" \
        "$TIMESTAMP")"

    echo "$RECURRING_OUTPUT"

    if echo "$RECURRING_OUTPUT" | grep -q "Transaction rejected"; then
        error "Recurring transfer transaction was REJECTED on-chain."
        exit 1
    else
        ok "Recurring transfer created! Task and Auth records generated."
    fi
    echo ""
    sleep 30
fi

# ─── STEP 4: CONDITIONAL TRANSFER ────────────────────────────
if [ "$ALL" = true ] || [ "$CONDITIONAL" = true ]; then
    step "STEP 4 — Conditional USDCx Transfer"
    info "Function: create_conditional_transfer"
    info "Amount: $AMOUNT_CONDITIONAL USDCx"
    info "Recipient: $RECIPIENT_ADDRESS"
    info "Trigger block: $TRIGGER_BLOCK_CONDITIONAL"
    info "Condition: price_above $CONDITION_VALUE"
    echo ""

    TIMESTAMP="$(date +%s)u32"

    info "Executing create_conditional_transfer..."
    info "Parameters:"
    info "  recipient: $RECIPIENT_ADDRESS"
    info "  amount: $AMOUNT_CONDITIONAL"
    info "  trigger_block: $TRIGGER_BLOCK_CONDITIONAL"
    info "  condition_type: $CONDITION_TYPE (price_above)"
    info "  condition_value: $CONDITION_VALUE"
    info "  timestamp: $TIMESTAMP"
    echo ""

    CONDITIONAL_OUTPUT="$(own_tx_capture create_conditional_transfer \
        "$RECIPIENT_ADDRESS" \
        "$AMOUNT_CONDITIONAL" \
        "$TRIGGER_BLOCK_CONDITIONAL" \
        "$CONDITION_TYPE" \
        "$CONDITION_VALUE" \
        "$TIMESTAMP")"

    echo "$CONDITIONAL_OUTPUT"

    if echo "$CONDITIONAL_OUTPUT" | grep -q "Transaction rejected"; then
        error "Conditional transfer transaction was REJECTED on-chain."
        exit 1
    else
        ok "Conditional transfer created! Task and Auth records generated."
    fi
    echo ""
    sleep 30
fi

# ─── STEP 5: MULTI-PARTY ESCROW ──────────────────────────────
if [ "$ALL" = true ] || [ "$ESCROW" = true ]; then
    step "STEP 5 — Multi-Party USDCx Escrow"
    info "Function: create_multi_party_escrow"
    info "Amount: $AMOUNT_ESCROW USDCx"
    info "Recipient: $RECIPIENT_ADDRESS"
    info "Trigger block: $TRIGGER_BLOCK_ESCROW"
    info "Required approvals: $REQUIRED_APPROVALS"
    echo ""

    TIMESTAMP="$(date +%s)u32"

    info "Executing create_multi_party_escrow..."
    info "Parameters:"
    info "  recipient: $RECIPIENT_ADDRESS"
    info "  amount: $AMOUNT_ESCROW"
    info "  trigger_block: $TRIGGER_BLOCK_ESCROW"
    info "  required_approvals: $REQUIRED_APPROVALS"
    info "  timestamp: $TIMESTAMP"
    echo ""

    ESCROW_OUTPUT="$(own_tx_capture create_multi_party_escrow \
        "$RECIPIENT_ADDRESS" \
        "$AMOUNT_ESCROW" \
        "$TRIGGER_BLOCK_ESCROW" \
        "$REQUIRED_APPROVALS" \
        "$TIMESTAMP")"

    echo "$ESCROW_OUTPUT"

    if echo "$ESCROW_OUTPUT" | grep -q "Transaction rejected"; then
        error "Multi-party escrow transaction was REJECTED on-chain."
        exit 1
    else
        ok "Multi-party escrow created! Task and EscrowAuth records generated."
    fi
    echo ""
    sleep 30
fi

# ─── STEP 6: APPROVAL FLOW ───────────────────────────────────
if [ "$ALL" = true ] || [ "$ESCROW" = true ]; then
    step "STEP 6 — Escrow Approval Flow"
    info "This step demonstrates the approval process for multi-party escrow"
    echo ""

    echo "To approve an escrow:"
    echo "  1. Each party calls approve_escrow(task_id, escrow_auth)"
    echo "  2. EscrowAuth record is consumed"
    echo "  3. Approval count is incremented"
    echo "  4. When approvals_received >= required_approvals, is_approved = true"
    echo ""

    echo "Example approval command:"
    echo "  leo execute approve_escrow \\"
    echo "    --network $NETWORK \\"
    echo "    --endpoint $ENDPOINT \\"
    echo "    --private-key <PARTY_PRIVATE_KEY> \\"
    echo "    --broadcast \\"
    echo "    <task_id> \\"
    echo "    <escrow_auth_record>"
    echo ""
fi

# ─── STEP 7: EXECUTION ───────────────────────────────────────
step "STEP 7 — Task Execution"
info "When conditions are met, keeper executes the task"
echo ""

echo "Execution conditions:"
echo "  • One-time: block.height >= trigger_block"
echo "  • Recurring: block.height >= trigger_block"
echo "  • Conditional: block.height >= trigger_block AND price condition met"
echo "  • Escrow: block.height >= trigger_block AND is_approved = true"
echo ""

echo "Execution command:"
echo "  leo execute execute_transfer \\"
echo "    --network $NETWORK \\"
echo "    --endpoint $ENDPOINT \\"
echo "    --private-key $PRIVATE_KEY \\"
echo "    --broadcast \\"
echo "    <task_id> \\"
echo "    <current_price>"
echo ""

echo "After execution:"
echo "  • USDCx is transferred to recipient"
echo "  • Task is removed (or rescheduled for recurring)"
echo "  • For recurring: next_trigger_block = trigger_block + interval_blocks"
echo ""

# ─── STEP 8: CANCELLATION ────────────────────────────────────
step "STEP 8 — Cancellation Flow"
info "Users can cancel tasks before execution"
echo ""

echo "Cancellation types:"
echo "  • One-time: cancel_transfer(task_auth)"
echo "  • Recurring: cancel_transfer(task_auth) - refunds remaining executions"
echo "  • Conditional: cancel_transfer(task_auth)"
echo "  • Escrow: cancel_escrow(escrow_auth) - only if not yet approved"
echo ""

echo "Cancellation command:"
echo "  leo execute cancel_transfer \\"
echo "    --network $NETWORK \\"
echo "    --endpoint $ENDPOINT \\"
echo "    --private-key <USER_PRIVATE_KEY> \\"
echo "    --broadcast \\"
echo "    <task_auth_record>"
echo ""

echo "After cancellation:"
echo "  • USDCx is refunded to creator"
echo "  • Task is removed from mapping"
echo "  • Auth record is consumed"
echo ""

# ─── DONE ────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║               Demo Complete!                             ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  USDCx Automation Hub Features:                          ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  ✓ One-time scheduled transfers                          ║"
echo "║  ✓ Recurring payments with intervals                     ║"
echo "║  ✓ Conditional transfers (price-based)                   ║"
echo "║  ✓ Multi-party escrow with approvals                     ║"
echo "║  ✓ USDCx token support via test_usdcx_stablecoin.aleo    ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Architecture:                                           ║"
echo "║    • Tasks stored in public mappings                     ║"
echo "║    • Users receive Auth records for cancellation         ║"
echo "║    • Keeper executes when conditions are met             ║"
echo "║    • USDCx escrowed in program balance                   ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Complete Flow:                                          ║"
echo "║    1. User creates task → Task + Auth records            ║"
echo "║    2. USDCx escrowed in program                          ║"
echo "║    3. Keeper monitors conditions                         ║"
echo "║    4. When met → USDCx transferred to recipient          ║"
echo "║    5. User can cancel → USDCx refunded                   ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Security:                                               ║"
echo "║    • Role-based access control                           ║"
echo "║    • Multi-party approval prevents fraud                 ║"
echo "║    • Conditional transfers verify price on-chain         ║"
echo "║    • Recurring payments escrow total amount upfront      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
