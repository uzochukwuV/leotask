// Leotask - Scheduled Transfer
// ============================================
// Users create scheduled transfers stored in public mappings.
// The keeper (or anyone) executes when trigger_block is reached.
// No record ciphertext needed — keeper tracks task IDs only.
//
// USER LIFECYCLE:
//   1. create_scheduled_transfer(...) → CancelAuth record (to self) + on-chain task
//   2. Keeper calls execute_scheduled_transfer(task_id) at trigger_block
//      OR
//   2. User calls cancel_scheduled_transfer(cancel) to reclaim funds early
//
// FUND FLOW:
//   create → user's public credits → program's public balance (escrowed)
//   execute → program's public balance → recipient
//   cancel  → program's public balance → creator

import credits.aleo;

program automation_scheduled_transferv3.aleo {

    // ═══════════════════════════════════════════════════════════════
    // STRUCTS & MAPPINGS
    // ═══════════════════════════════════════════════════════════════

    struct TaskInfo {
        creator: address,
        recipient: address,
        amount: u64,
        trigger_block: u32,
    }

    // 0u8 = admin, 1u8 = keeper/orchestrator
    mapping roles: u8 => address;

    // task_id => TaskInfo (active tasks only; removed on execute/cancel)
    mapping task_data: field => TaskInfo;

    // ═══════════════════════════════════════════════════════════════
    // RECORDS
    // ═══════════════════════════════════════════════════════════════

    // Held by USER — authorizes cancellation and refund before execution
    record CancelAuth {
        owner: address,
        task_id: field,
        amount: u64,
    }

    
    @custom
    async constructor() {
        Mapping::set(roles, 0u8, self.program_owner);  // Oracle admin
        Mapping::set(roles, 1u8, self.program_owner);  // Orchestrator
    }

    // ═══════════════════════════════════════════════════════════════
    // SCHEDULED TRANSFER
    // ═══════════════════════════════════════════════════════════════

    // User escrows credits and registers the task publicly.
    // Returns a CancelAuth record so the user can cancel before execution.
    async transition create_scheduled_transfer(
        public task_id: field,
        public recipient: address,
        public amount: u64,
        public trigger_block: u32,
    ) -> (CancelAuth, Future) {
        assert(amount > 0u64);

        let transfer_future: Future =
            credits.aleo/transfer_public_as_signer(self.address, amount);

        let cancel: CancelAuth = CancelAuth {
            owner: self.signer,
            task_id,
            amount,
        };

        return (cancel, finalize_create(
            transfer_future,
            task_id,
            self.signer,
            recipient,
            amount,
            trigger_block,
        ));
    }

    async function finalize_create(
        transfer_future: Future,
        task_id: field,
        creator: address,
        recipient: address,
        amount: u64,
        trigger_block: u32,
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
        });
    }

    // Anyone can execute once trigger_block is reached.
    // Keeper reads recipient+amount from the mapping (via API) and passes them in.
    // Finalize verifies they match the stored task before paying out.
    async transition execute_scheduled_transfer(
        public task_id: field,
        public recipient: address,
        public amount: u64,
    ) -> Future {
        let transfer_future: Future = credits.aleo/transfer_public(recipient, amount);
        return finalize_execute(transfer_future, task_id, recipient, amount);
    }

    async function finalize_execute(
        transfer_future: Future,
        task_id: field,
        recipient: address,
        amount: u64,
    ) {
        let info: TaskInfo = Mapping::get(task_data, task_id);
        assert(block.height >= info.trigger_block);
        assert_eq(info.recipient, recipient);
        assert_eq(info.amount, amount);
        transfer_future.await();
        Mapping::remove(task_data, task_id);
    }

    // User cancels before execution. Refunds escrowed credits.
    // cancel.amount comes from the user's own CancelAuth record and is verified in finalize.
    async transition cancel_scheduled_transfer(
        cancel: CancelAuth,
    ) -> Future {
        assert_eq(cancel.owner, self.caller);
        let transfer_future: Future = credits.aleo/transfer_public(self.caller, cancel.amount);
        return finalize_cancel(transfer_future, cancel.task_id, self.caller, cancel.amount);
    }

    async function finalize_cancel(
        transfer_future: Future,
        task_id: field,
        caller: address,
        amount: u64,
    ) {
        let info: TaskInfo = Mapping::get(task_data, task_id);
        assert_eq(info.creator, caller);
        assert_eq(info.amount, amount);
        transfer_future.await();
        Mapping::remove(task_data, task_id);
    }
}
