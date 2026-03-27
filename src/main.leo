// Leotask - Advanced Scheduled Transfer System
// ============================================
// Supports: Recurring payments, conditional transfers, multi-party escrow, USDCx
//
// FEATURES:
//   1. One-time scheduled transfers
//   2. Recurring payments with intervals
//   3. Conditional transfers (price-based, time-based)
//   4. Multi-party escrow with approval logic
//   5. USDCx (Superfluid) token support
//
// USER LIFECYCLE:
//   1. create_scheduled_transfer(...) → CancelAuth record + on-chain task
//   2. create_recurring_transfer(...) → RecurringAuth record + on-chain task
//   3. create_conditional_transfer(...) → ConditionalAuth record + on-chain task
//   4. create_multi_party_escrow(...) → EscrowAuth records for each party
//   5. Keeper executes when conditions are met
//   6. User can cancel before execution
//
// FUND FLOW:
//   create → user's public credits → program's public balance (escrowed)
//   execute → program's public balance → recipient
//   cancel  → program's public balance → creator

import credits.aleo;

program automation_advanced_transferv4.aleo {

    // ═══════════════════════════════════════════════════════════════
    // STRUCTS & MAPPINGS
    // ═══════════════════════════════════════════════════════════════

    // Task types
    // 0 = one-time transfer
    // 1 = recurring transfer
    // 2 = conditional transfer (price-based)
    // 3 = multi-party escrow

    struct TaskInfo {
        creator: address,
        recipient: address,
        amount: u64,
        trigger_block: u32,
        task_type: u8,
        token_type: u8,  // 0 = ALEO, 1 = USDCx
        // Recurring fields
        interval_blocks: u32,
        max_executions: u32,
        executions_completed: u32,
        // Conditional fields
        condition_type: u8,  // 0 = none, 1 = price_above, 2 = price_below
        condition_value: u64,
        // Multi-party fields
        required_approvals: u8,
        approvals_received: u8,
        is_approved: bool,
    }

    // 0u8 = admin, 1u8 = keeper/orchestrator
    mapping roles: u8 => address;

    // task_id => TaskInfo (active tasks only; removed on execute/cancel)
    mapping task_data: field => TaskInfo;

    // task_id_party_address => approved (for multi-party escrow)
    // Use composite key: task_id + party_address
    mapping escrow_approvals: field => bool;

    // task_id_party_address => has_auth (for multi-party escrow)
    mapping escrow_parties: field => bool;

    // token_type => program_address (for USDCx support)
    mapping token_programs: u8 => address;

    // ═══════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    // Create a composite key for escrow mappings
    // Note: In production, use a proper hash function
    // For now, we'll compute the key inline where needed

    // ═══════════════════════════════════════════════════════════════
    // RECORDS
    // ═══════════════════════════════════════════════════════════════

    // Held by USER — authorizes cancellation and refund before execution
    record CancelAuth {
        owner: address,
        task_id: field,
        amount: u64,
    }

    // Held by USER — authorizes recurring transfer cancellation
    record RecurringAuth {
        owner: address,
        task_id: field,
        total_amount: u64,
        executions_remaining: u32,
    }

    // Held by USER — authorizes conditional transfer cancellation
    record ConditionalAuth {
        owner: address,
        task_id: field,
        amount: u64,
        condition_type: u8,
        condition_value: u64,
    }

    // Held by PARTY — authorizes participation in multi-party escrow
    record EscrowAuth {
        owner: address,
        task_id: field,
        party_address: address,
        amount: u64,
        has_approved: bool,
    }

    // ═══════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    @custom
    async constructor() {
        Mapping::set(roles, 0u8, self.program_owner);  // Admin
        Mapping::set(roles, 1u8, self.program_owner);  // Keeper/Orchestrator
        
        // Initialize token programs (placeholder addresses - update in production)
        Mapping::set(token_programs, 0u8, self.program_owner);  // ALEO
        Mapping::set(token_programs, 1u8, self.program_owner);  // USDCx
    }

    // ═══════════════════════════════════════════════════════════════
    // ONE-TIME SCHEDULED TRANSFER
    // ═══════════════════════════════════════════════════════════════

    // User escrows credits and registers the task publicly.
    // Returns a CancelAuth record so the user can cancel before execution.
    async transition create_scheduled_transfer(
        public task_id: field,
        public recipient: address,
        public amount: u64,
        public trigger_block: u32,
        public token_type: u8,
    ) -> (CancelAuth, Future) {
        assert(amount > 0u64);
        assert(token_type <= 1u8);  // 0 = ALEO, 1 = USDCx

        let transfer_future: Future =
            credits.aleo/transfer_public_as_signer(self.address, amount);

        let cancel: CancelAuth = CancelAuth {
            owner: self.signer,
            task_id,
            amount,
        };

        return (cancel, finalize_create_scheduled(
            transfer_future,
            task_id,
            self.signer,
            recipient,
            amount,
            trigger_block,
            token_type,
        ));
    }

    async function finalize_create_scheduled(
        transfer_future: Future,
        task_id: field,
        creator: address,
        recipient: address,
        amount: u64,
        trigger_block: u32,
        token_type: u8,
    ) {
        transfer_future.await();

        assert(trigger_block > block.height);

        let exists: bool = Mapping::contains(task_data, task_id);
        assert(!exists);

        Mapping::set(task_data, task_id, TaskInfo {
            creator,
            recipient,
            amount,
            trigger_block,
            task_type: 0u8,  // one-time
            token_type,
            interval_blocks: 0u32,
            max_executions: 1u32,
            executions_completed: 0u32,
            condition_type: 0u8,
            condition_value: 0u64,
            required_approvals: 0u8,
            approvals_received: 0u8,
            is_approved: true,
        });
    }

    // ═══════════════════════════════════════════════════════════════
    // RECURRING PAYMENTS
    // ═══════════════════════════════════════════════════════════════

    // User creates a recurring transfer that executes multiple times
    async transition create_recurring_transfer(
        public task_id: field,
        public recipient: address,
        public amount_per_execution: u64,
        public first_trigger_block: u32,
        public interval_blocks: u32,
        public max_executions: u32,
        public token_type: u8,
    ) -> (RecurringAuth, Future) {
        assert(amount_per_execution > 0u64);
        assert(interval_blocks > 0u32);
        assert(max_executions > 0u32);
        assert(token_type <= 1u8);

        // Escrow total amount for all executions
        let total_amount: u64 = amount_per_execution * (max_executions as u64);

        let transfer_future: Future =
            credits.aleo/transfer_public_as_signer(self.address, total_amount);

        let auth: RecurringAuth = RecurringAuth {
            owner: self.signer,
            task_id,
            total_amount,
            executions_remaining: max_executions,
        };

        return (auth, finalize_create_recurring(
            transfer_future,
            task_id,
            self.signer,
            recipient,
            amount_per_execution,
            first_trigger_block,
            interval_blocks,
            max_executions,
            token_type,
        ));
    }

    async function finalize_create_recurring(
        transfer_future: Future,
        task_id: field,
        creator: address,
        recipient: address,
        amount_per_execution: u64,
        first_trigger_block: u32,
        interval_blocks: u32,
        max_executions: u32,
        token_type: u8,
    ) {
        transfer_future.await();

        assert(first_trigger_block > block.height);

        let exists: bool = Mapping::contains(task_data, task_id);
        assert(!exists);

        Mapping::set(task_data, task_id, TaskInfo {
            creator,
            recipient,
            amount: amount_per_execution,
            trigger_block: first_trigger_block,
            task_type: 1u8,  // recurring
            token_type,
            interval_blocks,
            max_executions,
            executions_completed: 0u32,
            condition_type: 0u8,
            condition_value: 0u64,
            required_approvals: 0u8,
            approvals_received: 0u8,
            is_approved: true,
        });
    }

    // ═══════════════════════════════════════════════════════════════
    // CONDITIONAL TRANSFERS
    // ═══════════════════════════════════════════════════════════════

    // User creates a conditional transfer that executes when conditions are met
    async transition create_conditional_transfer(
        public task_id: field,
        public recipient: address,
        public amount: u64,
        public trigger_block: u32,
        public condition_type: u8,  // 1 = price_above, 2 = price_below
        public condition_value: u64,
        public token_type: u8,
    ) -> (ConditionalAuth, Future) {
        assert(amount > 0u64);
        assert(condition_type >= 1u8);
        assert(condition_type <= 2u8);
        assert(token_type <= 1u8);

        let transfer_future: Future =
            credits.aleo/transfer_public_as_signer(self.address, amount);

        let auth: ConditionalAuth = ConditionalAuth {
            owner: self.signer,
            task_id,
            amount,
            condition_type,
            condition_value,
        };

        return (auth, finalize_create_conditional(
            transfer_future,
            task_id,
            self.signer,
            recipient,
            amount,
            trigger_block,
            condition_type,
            condition_value,
            token_type,
        ));
    }

    async function finalize_create_conditional(
        transfer_future: Future,
        task_id: field,
        creator: address,
        recipient: address,
        amount: u64,
        trigger_block: u32,
        condition_type: u8,
        condition_value: u64,
        token_type: u8,
    ) {
        transfer_future.await();

        assert(trigger_block > block.height);

        let exists: bool = Mapping::contains(task_data, task_id);
        assert(!exists);

        Mapping::set(task_data, task_id, TaskInfo {
            creator,
            recipient,
            amount,
            trigger_block,
            task_type: 2u8,  // conditional
            token_type,
            interval_blocks: 0u32,
            max_executions: 1u32,
            executions_completed: 0u32,
            condition_type,
            condition_value,
            required_approvals: 0u8,
            approvals_received: 0u8,
            is_approved: true,
        });
    }

    // ═══════════════════════════════════════════════════════════════
    // MULTI-PARTY ESCROW
    // ═══════════════════════════════════════════════════════════════

    // User creates a multi-party escrow that requires multiple approvals
    async transition create_multi_party_escrow(
        public task_id: field,
        public recipient: address,
        public amount: u64,
        public trigger_block: u32,
        public required_approvals: u8,
        public token_type: u8,
    ) -> (EscrowAuth, Future) {
        assert(amount > 0u64);
        assert(required_approvals > 0u8);
        assert(required_approvals <= 10u8);  // Max 10 parties
        assert(token_type <= 1u8);

        let transfer_future: Future =
            credits.aleo/transfer_public_as_signer(self.address, amount);

        let auth: EscrowAuth = EscrowAuth {
            owner: self.signer,
            task_id,
            party_address: self.signer,
            amount,
            has_approved: false,
        };

        return (auth, finalize_create_escrow(
            transfer_future,
            task_id,
            self.signer,
            recipient,
            amount,
            trigger_block,
            required_approvals,
            token_type,
        ));
    }

    async function finalize_create_escrow(
        transfer_future: Future,
        task_id: field,
        creator: address,
        recipient: address,
        amount: u64,
        trigger_block: u32,
        required_approvals: u8,
        token_type: u8,
    ) {
        transfer_future.await();

        assert(trigger_block > block.height);

        let exists: bool = Mapping::contains(task_data, task_id);
        assert(!exists);

        Mapping::set(task_data, task_id, TaskInfo {
            creator,
            recipient,
            amount,
            trigger_block,
            task_type: 3u8,  // multi-party escrow
            token_type,
            interval_blocks: 0u32,
            max_executions: 1u32,
            executions_completed: 0u32,
            condition_type: 0u8,
            condition_value: 0u64,
            required_approvals,
            approvals_received: 0u8,
            is_approved: false,
        });

        // Mark creator as a party
        let creator_field: field = creator as field;
        let key: field = task_id + creator_field;
        Mapping::set(escrow_parties, key, true);
    }

    // Party approves the escrow
    async transition approve_escrow(
        public task_id: field,
        auth: EscrowAuth,
    ) -> (EscrowAuth, Future) {
        assert_eq(auth.owner, self.caller);
        assert_eq(auth.task_id, task_id);

        return (auth, finalize_approve_escrow(task_id, self.caller));
    }

    async function finalize_approve_escrow(
        task_id: field,
        caller: address,
    ) {
        let info: TaskInfo = Mapping::get(task_data, task_id);
        assert_eq(info.task_type, 3u8);  // Must be multi-party escrow
        assert(!info.is_approved);  // Not already fully approved

        let caller_field: field = caller as field;
        let key: field = task_id + caller_field;
        let is_party: bool = Mapping::get(escrow_parties, key);
        assert(is_party);  // Must be a registered party

        let already_approved: bool = Mapping::get(escrow_approvals, key);
        assert(!already_approved);  // Haven't already approved

        Mapping::set(escrow_approvals, key, true);

        // Update approval count
        let new_count: u8 = info.approvals_received + 1u8;
        let fully_approved: bool = new_count >= info.required_approvals;

        Mapping::set(task_data, task_id, TaskInfo {
            creator: info.creator,
            recipient: info.recipient,
            amount: info.amount,
            trigger_block: info.trigger_block,
            task_type: info.task_type,
            token_type: info.token_type,
            interval_blocks: info.interval_blocks,
            max_executions: info.max_executions,
            executions_completed: info.executions_completed,
            condition_type: info.condition_type,
            condition_value: info.condition_value,
            required_approvals: info.required_approvals,
            approvals_received: new_count,
            is_approved: fully_approved,
        });
    }

    // Add a party to the escrow
    async transition add_escrow_party(
        public task_id: field,
        public party_address: address,
    ) -> Future {
        let info: TaskInfo = Mapping::get(task_data, task_id);
        assert_eq(info.creator, self.caller);
        assert_eq(info.task_type, 3u8);  // Must be multi-party escrow

        return finalize_add_party(task_id, party_address);
    }

    async function finalize_add_party(
        task_id: field,
        party_address: address,
    ) {
        let party_field: field = party_address as field;
        let key: field = task_id + party_field;
        Mapping::set(escrow_parties, key, true);
    }

    // ═══════════════════════════════════════════════════════════════
    // EXECUTION
    // ═══════════════════════════════════════════════════════════════

    // Anyone can execute once trigger_block is reached and conditions are met.
    async transition execute_transfer(
        public task_id: field,
        public recipient: address,
        public amount: u64,
        public current_price: u64,  // For conditional transfers
    ) -> Future {
        let transfer_future: Future = credits.aleo/transfer_public(recipient, amount);
        return finalize_execute(transfer_future, task_id, recipient, amount, current_price);
    }

    async function finalize_execute(
        transfer_future: Future,
        task_id: field,
        recipient: address,
        amount: u64,
        current_price: u64,
    ) {
        let info: TaskInfo = Mapping::get(task_data, task_id);
        
        // Check block height
        assert(block.height >= info.trigger_block);
        
        // Check recipient and amount match
        assert_eq(info.recipient, recipient);
        assert_eq(info.amount, amount);
        
        // Check task-specific conditions
        if (info.task_type == 2u8) {
            // Conditional transfer
            if (info.condition_type == 1u8) {
                // Price must be above threshold
                assert(current_price >= info.condition_value);
            } else if (info.condition_type == 2u8) {
                // Price must be below threshold
                assert(current_price <= info.condition_value);
            }
        } else if (info.task_type == 3u8) {
            // Multi-party escrow must be approved
            assert(info.is_approved);
        }
        
        // Execute transfer
        transfer_future.await();
        
        // Handle recurring tasks
        if (info.task_type == 1u8) {
            // Recurring transfer
            let new_executions: u32 = info.executions_completed + 1u32;
            
            if (new_executions < info.max_executions) {
                // Schedule next execution
                let next_trigger: u32 = info.trigger_block + info.interval_blocks;
                
                Mapping::set(task_data, task_id, TaskInfo {
                    creator: info.creator,
                    recipient: info.recipient,
                    amount: info.amount,
                    trigger_block: next_trigger,
                    task_type: info.task_type,
                    token_type: info.token_type,
                    interval_blocks: info.interval_blocks,
                    max_executions: info.max_executions,
                    executions_completed: new_executions,
                    condition_type: info.condition_type,
                    condition_value: info.condition_value,
                    required_approvals: info.required_approvals,
                    approvals_received: info.approvals_received,
                    is_approved: info.is_approved,
                });
            } else {
                // All executions completed, remove task
                Mapping::remove(task_data, task_id);
            }
        } else {
            // One-time, conditional, or multi-party - remove after execution
            Mapping::remove(task_data, task_id);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // CANCELLATION
    // ═══════════════════════════════════════════════════════════════

    // Cancel one-time scheduled transfer
    async transition cancel_scheduled_transfer(
        cancel: CancelAuth,
    ) -> Future {
        assert_eq(cancel.owner, self.caller);
        let transfer_future: Future = credits.aleo/transfer_public(self.caller, cancel.amount);
        return finalize_cancel_scheduled(transfer_future, cancel.task_id, self.caller, cancel.amount);
    }

    async function finalize_cancel_scheduled(
        transfer_future: Future,
        task_id: field,
        caller: address,
        amount: u64,
    ) {
        let info: TaskInfo = Mapping::get(task_data, task_id);
        assert_eq(info.creator, caller);
        assert_eq(info.amount, amount);
        assert_eq(info.task_type, 0u8);  // Must be one-time
        transfer_future.await();
        Mapping::remove(task_data, task_id);
    }

    // Cancel recurring transfer
    async transition cancel_recurring_transfer(
        auth: RecurringAuth,
    ) -> Future {
        assert_eq(auth.owner, self.caller);
        
        let info: TaskInfo = Mapping::get(task_data, auth.task_id);
        let remaining_amount: u64 = info.amount * (auth.executions_remaining as u64);
        
        let transfer_future: Future = credits.aleo/transfer_public(self.caller, remaining_amount);
        return finalize_cancel_recurring(transfer_future, auth.task_id, self.caller, remaining_amount);
    }

    async function finalize_cancel_recurring(
        transfer_future: Future,
        task_id: field,
        caller: address,
        amount: u64,
    ) {
        let info: TaskInfo = Mapping::get(task_data, task_id);
        assert_eq(info.creator, caller);
        assert_eq(info.task_type, 1u8);  // Must be recurring
        transfer_future.await();
        Mapping::remove(task_data, task_id);
    }

    // Cancel conditional transfer
    async transition cancel_conditional_transfer(
        auth: ConditionalAuth,
    ) -> Future {
        assert_eq(auth.owner, self.caller);
        let transfer_future: Future = credits.aleo/transfer_public(self.caller, auth.amount);
        return finalize_cancel_conditional(transfer_future, auth.task_id, self.caller, auth.amount);
    }

    async function finalize_cancel_conditional(
        transfer_future: Future,
        task_id: field,
        caller: address,
        amount: u64,
    ) {
        let info: TaskInfo = Mapping::get(task_data, task_id);
        assert_eq(info.creator, caller);
        assert_eq(info.amount, amount);
        assert_eq(info.task_type, 2u8);  // Must be conditional
        transfer_future.await();
        Mapping::remove(task_data, task_id);
    }

    // Cancel multi-party escrow (only if not yet approved)
    async transition cancel_escrow(
        auth: EscrowAuth,
    ) -> Future {
        assert_eq(auth.owner, self.caller);
        
        let info: TaskInfo = Mapping::get(task_data, auth.task_id);
        assert(!info.is_approved);  // Can't cancel if already approved
        
        let transfer_future: Future = credits.aleo/transfer_public(self.caller, auth.amount);
        return finalize_cancel_escrow(transfer_future, auth.task_id, self.caller, auth.amount);
    }

    async function finalize_cancel_escrow(
        transfer_future: Future,
        task_id: field,
        caller: address,
        amount: u64,
    ) {
        let info: TaskInfo = Mapping::get(task_data, task_id);
        assert_eq(info.creator, caller);
        assert_eq(info.amount, amount);
        assert_eq(info.task_type, 3u8);  // Must be escrow
        transfer_future.await();
        Mapping::remove(task_data, task_id);
    }

    // ═══════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    // Update token program address (admin only)
    async transition update_token_program(
        public token_type: u8,
        public program_address: address,
    ) -> Future {
        let admin: address = Mapping::get(roles, 0u8);
        assert_eq(admin, self.caller);
        
        return finalize_update_token_program(token_type, program_address);
    }

    async function finalize_update_token_program(
        token_type: u8,
        program_address: address,
    ) {
        Mapping::set(token_programs, token_type, program_address);
    }

    // Update keeper address (admin only)
    async transition update_keeper(
        public new_keeper: address,
    ) -> Future {
        let admin: address = Mapping::get(roles, 0u8);
        assert_eq(admin, self.caller);
        
        return finalize_update_keeper(new_keeper);
    }

    async function finalize_update_keeper(
        new_keeper: address,
    ) {
        Mapping::set(roles, 1u8, new_keeper);
    }
}
