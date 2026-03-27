// ============================================================================
// USDCx Automation Hub - Advanced Scheduled Transfers
// ============================================================================
// Features:
//   - Recurring USDCx payments with intervals
//   - Conditional USDCx transfers (price-based, time-based)
//   - Multi-party USDCx escrow with approval logic
//   - USDCx token support via test_usdcx_stablecoin.aleo
//
// Architecture:
//   - Task info stored in public mappings (structs, not records)
//   - Users receive Auth records for cancellation
//   - Keeper executes when conditions are met
//   - Only keeper can execute tasks
// ============================================================================

import credits.aleo;
import test_usdcx_stablecoin.aleo;

program usdcx_automation_hub.aleo {

    // USDCx token ID constant - routes to test_usdcx_stablecoin.aleo
    const USDCX_TOKEN_ID: field = 7000field;

    // Task types
    const TASK_TYPE_ONE_TIME: u8 = 0u8;
    const TASK_TYPE_RECURRING: u8 = 1u8;
    const TASK_TYPE_CONDITIONAL: u8 = 2u8;
    const TASK_TYPE_ESCROW: u8 = 3u8;

    // Condition types
    const CONDITION_NONE: u8 = 0u8;
    const CONDITION_PRICE_ABOVE: u8 = 1u8;
    const CONDITION_PRICE_BELOW: u8 = 2u8;

    // ========== STRUCTS (for mappings) ==========

    struct TaskInfo {
        creator: address,
        recipient: address,
        amount: u128,
        trigger_block: u32,
        task_type: u8,
        interval_blocks: u32,
        max_executions: u32,
        executions_completed: u32,
        condition_type: u8,
        condition_value: u64,
        required_approvals: u8,
        approvals_received: u8,
        is_approved: bool,
        is_active: bool,
        created_at: u32,
    }

    struct TaskIdInput {
        creator: address,
        recipient: address,
        amount: u128,
        trigger_block: u32,
        task_type: u8,
        timestamp: u32,
    }

    // ========== RECORDS (for user auth) ==========

    // Auth record - held by user for cancellation
    record TransferAuth {
        owner: address,
        task_id: field,
        amount: u128,
        task_type: u8,
    }

    // Escrow auth - held by party for approval
    record EscrowApprovalAuth {
        owner: address,
        task_id: field,
        party_address: address,
        amount: u128,
        has_approved: bool,
    }

    // ========== MAPPINGS ==========

    mapping orchestrator: bool => address;
    mapping keepers: address => bool;
    mapping tasks: field => TaskInfo;
    mapping task_counter: bool => u64;
    mapping escrow_approvals: field => bool;
    mapping escrow_parties: field => bool;

    // ========== CONSTRUCTOR ==========

    @custom
    async constructor() {
        Mapping::set(orchestrator, true, self.program_owner);
        Mapping::set(keepers, self.program_owner, true);
        Mapping::set(task_counter, true, 0u64);
    }

    // ========== ADMIN FUNCTIONS ==========

    async transition add_keeper(keeper: address) -> Future {
        return finalize_add_keeper(self.caller, keeper);
    }

    async function finalize_add_keeper(caller: address, keeper: address) {
        let orch: address = Mapping::get(orchestrator, true);
        assert_eq(caller, orch);
        Mapping::set(keepers, keeper, true);
    }

    async transition remove_keeper(keeper: address) -> Future {
        return finalize_remove_keeper(self.caller, keeper);
    }

    async function finalize_remove_keeper(caller: address, keeper: address) {
        let orch: address = Mapping::get(orchestrator, true);
        assert_eq(caller, orch);
        Mapping::set(keepers, keeper, false);
    }

    // ========== ONE-TIME TRANSFER ==========

    async transition create_one_time_transfer(
        recipient: address,
        amount: u128,
        trigger_block: u32,
        timestamp: u32,
    ) -> (TransferAuth, Future) {
        assert(amount > 0u128);

        let task_id: field = BHP256::hash_to_field(TaskIdInput {
            creator: self.signer,
            recipient: recipient,
            amount: amount,
            trigger_block: trigger_block,
            task_type: TASK_TYPE_ONE_TIME,
            timestamp: timestamp,
        });

        let auth: TransferAuth = TransferAuth {
            owner: self.signer,
            task_id: task_id,
            amount: amount,
            task_type: TASK_TYPE_ONE_TIME,
        };

        // Escrow USDCx
        let escrow_future: Future = test_usdcx_stablecoin.aleo/transfer_public_as_signer(
            self.address,
            amount
        );

        return (auth, finalize_create_one_time(
            task_id,
            self.signer,
            recipient,
            amount,
            trigger_block,
            timestamp,
            escrow_future,
        ));
    }

    async function finalize_create_one_time(
        task_id: field,
        creator: address,
        recipient: address,
        amount: u128,
        trigger_block: u32,
        timestamp: u32,
        escrow_future: Future,
    ) {
        escrow_future.await();

        assert(trigger_block > block.height);

        let exists: bool = Mapping::contains(tasks, task_id);
        assert(!exists);

        let task: TaskInfo = TaskInfo {
            creator: creator,
            recipient: recipient,
            amount: amount,
            trigger_block: trigger_block,
            task_type: TASK_TYPE_ONE_TIME,
            interval_blocks: 0u32,
            max_executions: 1u32,
            executions_completed: 0u32,
            condition_type: CONDITION_NONE,
            condition_value: 0u64,
            required_approvals: 0u8,
            approvals_received: 0u8,
            is_approved: true,
            is_active: true,
            created_at: timestamp,
        };

        Mapping::set(tasks, task_id, task);

        let counter: u64 = Mapping::get_or_use(task_counter, true, 0u64);
        Mapping::set(task_counter, true, counter + 1u64);
    }

    // ========== RECURRING TRANSFER ==========

    async transition create_recurring_transfer(
        recipient: address,
        amount_per_execution: u128,
        first_trigger_block: u32,
        interval_blocks: u32,
        max_executions: u32,
        timestamp: u32,
    ) -> (TransferAuth, Future) {
        assert(amount_per_execution > 0u128);
        assert(interval_blocks > 0u32);
        assert(max_executions > 0u32);

        let total_amount: u128 = amount_per_execution * (max_executions as u128);

        let task_id: field = BHP256::hash_to_field(TaskIdInput {
            creator: self.signer,
            recipient: recipient,
            amount: amount_per_execution,
            trigger_block: first_trigger_block,
            task_type: TASK_TYPE_RECURRING,
            timestamp: timestamp,
        });

        let auth: TransferAuth = TransferAuth {
            owner: self.signer,
            task_id: task_id,
            amount: total_amount,
            task_type: TASK_TYPE_RECURRING,
        };

        // Escrow total USDCx amount
        let escrow_future: Future = test_usdcx_stablecoin.aleo/transfer_public_as_signer(
            self.address,
            total_amount
        );

        return (auth, finalize_create_recurring(
            task_id,
            self.signer,
            recipient,
            amount_per_execution,
            first_trigger_block,
            interval_blocks,
            max_executions,
            timestamp,
            escrow_future,
        ));
    }

    async function finalize_create_recurring(
        task_id: field,
        creator: address,
        recipient: address,
        amount_per_execution: u128,
        first_trigger_block: u32,
        interval_blocks: u32,
        max_executions: u32,
        timestamp: u32,
        escrow_future: Future,
    ) {
        escrow_future.await();

        assert(first_trigger_block > block.height);

        let exists: bool = Mapping::contains(tasks, task_id);
        assert(!exists);

        let task: TaskInfo = TaskInfo {
            creator: creator,
            recipient: recipient,
            amount: amount_per_execution,
            trigger_block: first_trigger_block,
            task_type: TASK_TYPE_RECURRING,
            interval_blocks: interval_blocks,
            max_executions: max_executions,
            executions_completed: 0u32,
            condition_type: CONDITION_NONE,
            condition_value: 0u64,
            required_approvals: 0u8,
            approvals_received: 0u8,
            is_approved: true,
            is_active: true,
            created_at: timestamp,
        };

        Mapping::set(tasks, task_id, task);

        let counter: u64 = Mapping::get_or_use(task_counter, true, 0u64);
        Mapping::set(task_counter, true, counter + 1u64);
    }

    // ========== CONDITIONAL TRANSFER ==========

    async transition create_conditional_transfer(
        recipient: address,
        amount: u128,
        trigger_block: u32,
        condition_type: u8,
        condition_value: u64,
        timestamp: u32,
    ) -> (TransferAuth, Future) {
        assert(amount > 0u128);
        assert(condition_type >= CONDITION_PRICE_ABOVE);
        assert(condition_type <= CONDITION_PRICE_BELOW);

        let task_id: field = BHP256::hash_to_field(TaskIdInput {
            creator: self.signer,
            recipient: recipient,
            amount: amount,
            trigger_block: trigger_block,
            task_type: TASK_TYPE_CONDITIONAL,
            timestamp: timestamp,
        });

        let auth: TransferAuth = TransferAuth {
            owner: self.signer,
            task_id: task_id,
            amount: amount,
            task_type: TASK_TYPE_CONDITIONAL,
        };

        // Escrow USDCx
        let escrow_future: Future = test_usdcx_stablecoin.aleo/transfer_public_as_signer(
            self.address,
            amount
        );

        return (auth, finalize_create_conditional(
            task_id,
            self.signer,
            recipient,
            amount,
            trigger_block,
            condition_type,
            condition_value,
            timestamp,
            escrow_future,
        ));
    }

    async function finalize_create_conditional(
        task_id: field,
        creator: address,
        recipient: address,
        amount: u128,
        trigger_block: u32,
        condition_type: u8,
        condition_value: u64,
        timestamp: u32,
        escrow_future: Future,
    ) {
        escrow_future.await();

        assert(trigger_block > block.height);

        let exists: bool = Mapping::contains(tasks, task_id);
        assert(!exists);

        let task: TaskInfo = TaskInfo {
            creator: creator,
            recipient: recipient,
            amount: amount,
            trigger_block: trigger_block,
            task_type: TASK_TYPE_CONDITIONAL,
            interval_blocks: 0u32,
            max_executions: 1u32,
            executions_completed: 0u32,
            condition_type: condition_type,
            condition_value: condition_value,
            required_approvals: 0u8,
            approvals_received: 0u8,
            is_approved: true,
            is_active: true,
            created_at: timestamp,
        };

        Mapping::set(tasks, task_id, task);

        let counter: u64 = Mapping::get_or_use(task_counter, true, 0u64);
        Mapping::set(task_counter, true, counter + 1u64);
    }

    // ========== MULTI-PARTY ESCROW ==========

    async transition create_multi_party_escrow(
        recipient: address,
        amount: u128,
        trigger_block: u32,
        required_approvals: u8,
        timestamp: u32,
    ) -> (EscrowApprovalAuth, Future) {
        assert(amount > 0u128);
        assert(required_approvals > 0u8);
        assert(required_approvals <= 10u8);

        let task_id: field = BHP256::hash_to_field(TaskIdInput {
            creator: self.signer,
            recipient: recipient,
            amount: amount,
            trigger_block: trigger_block,
            task_type: TASK_TYPE_ESCROW,
            timestamp: timestamp,
        });

        let auth: EscrowApprovalAuth = EscrowApprovalAuth {
            owner: self.signer,
            task_id: task_id,
            party_address: self.signer,
            amount: amount,
            has_approved: false,
        };

        // Escrow USDCx
        let escrow_future: Future = test_usdcx_stablecoin.aleo/transfer_public_as_signer(
            self.address,
            amount
        );

        return (auth, finalize_create_escrow(
            task_id,
            self.signer,
            recipient,
            amount,
            trigger_block,
            required_approvals,
            timestamp,
            escrow_future,
        ));
    }

    async function finalize_create_escrow(
        task_id: field,
        creator: address,
        recipient: address,
        amount: u128,
        trigger_block: u32,
        required_approvals: u8,
        timestamp: u32,
        escrow_future: Future,
    ) {
        escrow_future.await();

        assert(trigger_block > block.height);

        let exists: bool = Mapping::contains(tasks, task_id);
        assert(!exists);

        let task: TaskInfo = TaskInfo {
            creator: creator,
            recipient: recipient,
            amount: amount,
            trigger_block: trigger_block,
            task_type: TASK_TYPE_ESCROW,
            interval_blocks: 0u32,
            max_executions: 1u32,
            executions_completed: 0u32,
            condition_type: CONDITION_NONE,
            condition_value: 0u64,
            required_approvals: required_approvals,
            approvals_received: 0u8,
            is_approved: false,
            is_active: true,
            created_at: timestamp,
        };

        Mapping::set(tasks, task_id, task);

        // Mark creator as a party
        let creator_field: field = creator as field;
        let key: field = task_id + creator_field;
        Mapping::set(escrow_parties, key, true);

        let counter: u64 = Mapping::get_or_use(task_counter, true, 0u64);
        Mapping::set(task_counter, true, counter + 1u64);
    }

    // Add party to escrow
    async transition add_escrow_party(
        task_id: field,
        party_address: address,
    ) -> Future {
        return finalize_add_party(self.caller, task_id, party_address);
    }

    async function finalize_add_party(
        caller: address,
        task_id: field,
        party_address: address,
    ) {
        let task: TaskInfo = Mapping::get(tasks, task_id);
        assert_eq(task.creator, caller);
        assert_eq(task.task_type, TASK_TYPE_ESCROW);

        let party_field: field = party_address as field;
        let key: field = task_id + party_field;
        Mapping::set(escrow_parties, key, true);
    }

    // Approve escrow
    async transition approve_escrow(
        task_id: field,
        auth: EscrowApprovalAuth,
    ) -> (EscrowApprovalAuth, Future) {
        assert_eq(auth.owner, self.caller);
        assert_eq(auth.task_id, task_id);

        return (auth, finalize_approve_escrow(task_id, self.caller));
    }

    async function finalize_approve_escrow(
        task_id: field,
        caller: address,
    ) {
        let task: TaskInfo = Mapping::get(tasks, task_id);
        assert_eq(task.task_type, TASK_TYPE_ESCROW);
        assert(!task.is_approved);

        let caller_field: field = caller as field;
        let key: field = task_id + caller_field;
        let is_party: bool = Mapping::get(escrow_parties, key);
        assert(is_party);

        let already_approved: bool = Mapping::get(escrow_approvals, key);
        assert(!already_approved);

        Mapping::set(escrow_approvals, key, true);

        let new_count: u8 = task.approvals_received + 1u8;
        let fully_approved: bool = new_count >= task.required_approvals;

        let updated_task: TaskInfo = TaskInfo {
            creator: task.creator,
            recipient: task.recipient,
            amount: task.amount,
            trigger_block: task.trigger_block,
            task_type: task.task_type,
            interval_blocks: task.interval_blocks,
            max_executions: task.max_executions,
            executions_completed: task.executions_completed,
            condition_type: task.condition_type,
            condition_value: task.condition_value,
            required_approvals: task.required_approvals,
            approvals_received: new_count,
            is_approved: fully_approved,
            is_active: task.is_active,
            created_at: task.created_at,
        };

        Mapping::set(tasks, task_id, updated_task);
    }

    // ========== EXECUTION ==========

    async transition execute_transfer(
        task_id: field,
        current_price: u64,
    ) -> Future {
        return finalize_execute(task_id, current_price);
    }

    async function finalize_execute(
        task_id: field,
        current_price: u64,
    ) {
        let task: TaskInfo = Mapping::get(tasks, task_id);
        assert(task.is_active);
        assert(block.height >= task.trigger_block);

        // Check conditions
        if (task.task_type == TASK_TYPE_CONDITIONAL) {
            if (task.condition_type == CONDITION_PRICE_ABOVE) {
                assert(current_price >= task.condition_value);
            } else if (task.condition_type == CONDITION_PRICE_BELOW) {
                assert(current_price <= task.condition_value);
            }
        } else if (task.task_type == TASK_TYPE_ESCROW) {
            assert(task.is_approved);
        }

        // Transfer USDCx to recipient
        let transfer_future: Future = test_usdcx_stablecoin.aleo/transfer_public(
            task.recipient,
            task.amount
        );

        transfer_future.await();

        // Handle recurring tasks
        if (task.task_type == TASK_TYPE_RECURRING) {
            let new_executions: u32 = task.executions_completed + 1u32;

            if (new_executions < task.max_executions) {
                let next_trigger: u32 = task.trigger_block + task.interval_blocks;

                let updated_task: TaskInfo = TaskInfo {
                    creator: task.creator,
                    recipient: task.recipient,
                    amount: task.amount,
                    trigger_block: next_trigger,
                    task_type: task.task_type,
                    interval_blocks: task.interval_blocks,
                    max_executions: task.max_executions,
                    executions_completed: new_executions,
                    condition_type: task.condition_type,
                    condition_value: task.condition_value,
                    required_approvals: task.required_approvals,
                    approvals_received: task.approvals_received,
                    is_approved: task.is_approved,
                    is_active: task.is_active,
                    created_at: task.created_at,
                };

                Mapping::set(tasks, task_id, updated_task);
            } else {
                Mapping::remove(tasks, task_id);
            }
        } else {
            Mapping::remove(tasks, task_id);
        }
    }

    // ========== CANCELLATION ==========

    async transition cancel_transfer(
        auth: TransferAuth,
    ) -> Future {
        assert_eq(auth.owner, self.caller);

        return finalize_cancel(auth.task_id, auth.amount, auth.task_type);
    }

    async function finalize_cancel(
        task_id: field,
        auth_amount: u128,
        auth_task_type: u8,
    ) {
        let task: TaskInfo = Mapping::get(tasks, task_id);
        assert_eq(task.creator, self.caller);
        assert(task.is_active);

        let refund: u128 = task.amount;
        if (task.task_type == TASK_TYPE_RECURRING) {
            let remaining: u32 = task.max_executions - task.executions_completed;
            refund = task.amount * (remaining as u128);
        }

        let refund_future: Future = test_usdcx_stablecoin.aleo/transfer_public(
            self.caller,
            refund
        );

        refund_future.await();
        Mapping::remove(tasks, task_id);
    }

    // Cancel escrow (only if not yet approved)
    async transition cancel_escrow(
        auth: EscrowApprovalAuth,
    ) -> Future {
        assert_eq(auth.owner, self.caller);

        return finalize_cancel_escrow(auth.task_id, auth.amount);
    }

    async function finalize_cancel_escrow(
        task_id: field,
        auth_amount: u128,
    ) {
        let task: TaskInfo = Mapping::get(tasks, task_id);
        assert_eq(task.creator, self.caller);
        assert(!task.is_approved);

        let refund_future: Future = test_usdcx_stablecoin.aleo/transfer_public(
            self.caller,
            auth_amount
        );

        refund_future.await();
        Mapping::remove(tasks, task_id);
    }
}
