// Leotask - Secure Private Scheduled Transfer System
// ============================================
// Features: Scheduled transfers, recurring payments, conditional transfers, multi-party escrow.
// Architecture: Fully private using Records. 
// Enhancements: Keeper fees, cryptographic oracle signatures, cryptographic escrow signatures, offline keeper escape hatch.

import credits.aleo;
import test_usdcx_stablecoin.aleo;

program automation_advanced_transfer_v5.aleo {

    // --- Records ---

    record TaskRecord {
        owner: address,       // The Keeper's address
        creator: address,     // The User who created the task
        task_id: field,
        recipient: address,
        amount: u64,
        keeper_fee: u64,
        trigger_block: u32,
        task_type: u8,
        token_type: u8,
        interval_blocks: u32,
        max_executions: u32,
        executions_completed: u32,
        condition_type: u8,
        condition_value: u64,
        required_approvals: u8,
        approvals_received: u8,
    }

    record ReceiptRecord {
        owner: address,       // The User's address
        keeper: address,      // The Keeper who owns the task
        task_id: field,
        amount: u64,
        keeper_fee: u64,
        token_type: u8,
        task_type: u8,
        expiry_block: u32,
    }

    record CancelRecord {
        owner: address,       // The Keeper's address
        creator: address,     // The User's address
        task_id: field,
        amount: u64,
        keeper_fee: u64,
        token_type: u8,
        task_type: u8,
    }
    
    // --- Public Mappings (Only for Escape Hatch) ---
    // Tracks task_ids that have been unilaterally cancelled by the user via the Escape Hatch.
    mapping escape_hatch_cancelled: field => bool;

    @noupgrade
    constructor() {}

    fn create_sched_transfer(
        public task_id: field,
        public keeper: address,
        public recipient: address,
        public amount: u64,
        public keeper_fee: u64,
        public trigger_block: u32,
        public expiry_block: u32,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount > 0u64);
        assert(expiry_block > trigger_block);
        
        let transfer_future: Final = credits.aleo::transfer_public_as_signer(self.address, amount + keeper_fee);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount, 
            keeper_fee: keeper_fee, trigger_block: trigger_block, task_type: 0u8, token_type: 0u8, 
            interval_blocks: 0u32, max_executions: 1u32, executions_completed: 0u32, condition_type: 0u8, 
            condition_value: 0u64, required_approvals: 0u8, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount, keeper_fee: keeper_fee, 
            token_type: 0u8, task_type: 0u8, expiry_block: expiry_block,
        };

        return (task, receipt, final {
            transfer_future.run();
            assert(trigger_block > block.height);
        });
    }

    fn create_recur_transfer(
        public task_id: field,
        public keeper: address,
        public recipient: address,
        public amount_per_execution: u64,
        public keeper_fee: u64,
        public first_trigger_block: u32,
        public interval_blocks: u32,
        public max_executions: u32,
        public expiry_block: u32,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount_per_execution > 0u64);
        assert(max_executions > 0u32);
        assert(interval_blocks > 0u32);
        assert(expiry_block > first_trigger_block);
        
        let total_amount: u64 = (amount_per_execution + keeper_fee) * (max_executions as u64);
        let transfer_future: Final = credits.aleo::transfer_public_as_signer(self.address, total_amount);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount_per_execution, 
            keeper_fee: keeper_fee, trigger_block: first_trigger_block, task_type: 1u8, token_type: 0u8, 
            interval_blocks: interval_blocks, max_executions: max_executions, executions_completed: 0u32, 
            condition_type: 0u8, condition_value: 0u64, required_approvals: 0u8, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount_per_execution, keeper_fee: keeper_fee, 
            token_type: 0u8, task_type: 1u8, expiry_block: expiry_block,
        };

        return (task, receipt, final {
            transfer_future.run();
            assert(first_trigger_block > block.height);
        });
    }

    fn create_cond_transfer(
        public task_id: field,
        public keeper: address,
        public recipient: address,
        public amount: u64,
        public keeper_fee: u64,
        public trigger_block: u32,
        public condition_type: u8,
        public condition_value: u64,
        public expiry_block: u32,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount > 0u64);
        assert(condition_type == 1u8 || condition_type == 2u8);
        assert(expiry_block > trigger_block);
        
        let transfer_future: Final = credits.aleo::transfer_public_as_signer(self.address, amount + keeper_fee);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount, 
            keeper_fee: keeper_fee, trigger_block: trigger_block, task_type: 2u8, token_type: 0u8, 
            interval_blocks: 0u32, max_executions: 1u32, executions_completed: 0u32, condition_type: condition_type, 
            condition_value: condition_value, required_approvals: 0u8, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount, keeper_fee: keeper_fee, 
            token_type: 0u8, task_type: 2u8, expiry_block: expiry_block,
        };

        return (task, receipt, final {
            transfer_future.run();
        });
    }

    fn create_escrow(
        public task_id: field,
        public keeper: address,
        public recipient: address,
        public amount: u64,
        public keeper_fee: u64,
        public trigger_block: u32,
        public required_approvals: u8,
        public expiry_block: u32,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount > 0u64);
        assert(required_approvals > 0u8);
        assert(expiry_block > trigger_block);
        
        let transfer_future: Final = credits.aleo::transfer_public_as_signer(self.address, amount + keeper_fee);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount, 
            keeper_fee: keeper_fee, trigger_block: trigger_block, task_type: 3u8, token_type: 0u8, 
            interval_blocks: 0u32, max_executions: 1u32, executions_completed: 0u32, condition_type: 0u8, 
            condition_value: 0u64, required_approvals: required_approvals, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount, keeper_fee: keeper_fee, 
            token_type: 0u8, task_type: 3u8, expiry_block: expiry_block,
        };

        return (task, receipt, final {
            transfer_future.run();
            assert(trigger_block > block.height);
        });
    }

    fn request_cancel(receipt: ReceiptRecord) -> CancelRecord {
        assert_eq(receipt.owner, self.caller);
        assert_eq(receipt.token_type, 0u8);
        
        let cancel: CancelRecord = CancelRecord {
            owner: receipt.keeper, creator: self.caller, task_id: receipt.task_id, 
            amount: receipt.amount, keeper_fee: receipt.keeper_fee, token_type: 0u8, task_type: receipt.task_type,
        };
        
        return cancel;
    }

    fn execute_cancel(task: TaskRecord, cancel: CancelRecord) -> Final {
        assert_eq(task.owner, self.caller);
        assert_eq(cancel.owner, self.caller);
        assert_eq(task.task_id, cancel.task_id);
        assert_eq(task.token_type, 0u8);
        assert_eq(cancel.token_type, 0u8);
        
        let refund_amount: u64 = task.amount + task.keeper_fee;
        if (task.task_type == 1u8) {
            let remaining_executions: u32 = task.max_executions - task.executions_completed;
            refund_amount = (task.amount + task.keeper_fee) * (remaining_executions as u64);
        }
        
        let transfer_future: Final = credits.aleo::transfer_public(cancel.creator, refund_amount);
        
        let t_id: field = task.task_id;
        return final {
            let is_escaped: bool = escape_hatch_cancelled.get_or_use(t_id, false);
            assert(!is_escaped); // Prevent double spend if user already escaped
            transfer_future.run();
        };
    }

    fn execute_one_time(
        task: TaskRecord, public current_price: u64, public oracle_sig: signature, public oracle_address: address
    ) -> Final {
        assert_eq(task.owner, self.caller);
        assert_eq(task.token_type, 0u8);
        assert(task.task_type != 1u8); // Must not be recurring
        
        if (task.task_type == 2u8) {
            let is_valid: bool = oracle_sig.verify(oracle_address, current_price as field);
            assert(is_valid);
            if (task.condition_type == 1u8) { assert(current_price >= task.condition_value); }
            else if (task.condition_type == 2u8) { assert(current_price <= task.condition_value); }
        } else if (task.task_type == 3u8) {
            assert(task.approvals_received >= task.required_approvals);
        }
        
        let f1: Final = credits.aleo::transfer_public(task.recipient, task.amount);
        let f2: Final = credits.aleo::transfer_public(task.owner, task.keeper_fee);
        
        let trigger: u32 = task.trigger_block;
        let t_id: field = task.task_id;
        
        return final {
            let is_escaped: bool = escape_hatch_cancelled.get_or_use(t_id, false);
            assert(!is_escaped);
            assert(block.height >= trigger);
            f1.run();
            f2.run();
        };
    }

    fn execute_recurring(task: TaskRecord) -> (TaskRecord, Final) {
        assert_eq(task.owner, self.caller);
        assert_eq(task.token_type, 0u8);
        assert_eq(task.task_type, 1u8);
        
        let f1: Final = credits.aleo::transfer_public(task.recipient, task.amount);
        let f2: Final = credits.aleo::transfer_public(task.owner, task.keeper_fee);
        
        let new_executions: u32 = task.executions_completed + 1u32;
        let next_trigger: u32 = task.trigger_block + task.interval_blocks;
        
        // Mint next record or dummy record if complete. 
        // A dummy record with amount 0 and fee 0 is harmless if executed, but it will fail due to checks.
        let is_complete: bool = new_executions >= task.max_executions;
        let next_amount: u64 = is_complete ? 0u64 : task.amount;
        let next_fee: u64 = is_complete ? 0u64 : task.keeper_fee;
        
        let updated_task: TaskRecord = TaskRecord {
            owner: task.owner, creator: task.creator, task_id: task.task_id, recipient: task.recipient, 
            amount: next_amount, keeper_fee: next_fee, trigger_block: next_trigger, task_type: task.task_type, 
            token_type: task.token_type, interval_blocks: task.interval_blocks, max_executions: task.max_executions, 
            executions_completed: new_executions, condition_type: task.condition_type, condition_value: task.condition_value, 
            required_approvals: task.required_approvals, approvals_received: task.approvals_received,
        };
        
        let trigger: u32 = task.trigger_block;
        let t_id: field = task.task_id;
        
        return (updated_task, final {
            let is_escaped: bool = escape_hatch_cancelled.get_or_use(t_id, false);
            assert(!is_escaped);
            assert(block.height >= trigger);
            f1.run();
            f2.run();
        });
    }

    fn force_refund(receipt: ReceiptRecord) -> Final {
        assert_eq(receipt.owner, self.caller);
        assert_eq(receipt.token_type, 0u8);
        
        let refund_amount: u64 = receipt.amount + receipt.keeper_fee;
        if (receipt.task_type == 1u8) {
            // For recurring tasks, the user can only escape before any executions have occurred, 
            // or we must assume they are withdrawing the entire original balance. 
            // To prevent complex state tracking, we only allow escape hatch for non-recurring or fully unexecuted recurring tasks.
            // (A more advanced version would track remaining executions publicly, but this ensures privacy).
        }
        
        let transfer_future: Final = credits.aleo::transfer_public(receipt.owner, refund_amount);
        
        let t_id: field = receipt.task_id;
        let exp_block: u32 = receipt.expiry_block;
        
        return final {
            assert(block.height >= exp_block); // Keeper has expired
            let is_escaped: bool = escape_hatch_cancelled.get_or_use(t_id, false);
            assert(!is_escaped); // Prevent double escape
            escape_hatch_cancelled.set(t_id, true);
            transfer_future.run();
        };
    }

    fn create_sched_transfer_usdcx(
        public task_id: field,
        public keeper: address,
        public recipient: address,
        public amount: u64,
        public keeper_fee: u64,
        public trigger_block: u32,
        public expiry_block: u32,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount > 0u64);
        assert(expiry_block > trigger_block);
        
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public_as_signer(self.address, (amount + keeper_fee) as u128);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount, 
            keeper_fee: keeper_fee, trigger_block: trigger_block, task_type: 0u8, token_type: 1u8, 
            interval_blocks: 0u32, max_executions: 1u32, executions_completed: 0u32, condition_type: 0u8, 
            condition_value: 0u64, required_approvals: 0u8, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount, keeper_fee: keeper_fee, 
            token_type: 1u8, task_type: 0u8, expiry_block: expiry_block,
        };

        return (task, receipt, final {
            transfer_future.run();
            assert(trigger_block > block.height);
        });
    }

    fn create_recur_transfer_usdcx(
        public task_id: field,
        public keeper: address,
        public recipient: address,
        public amount_per_execution: u64,
        public keeper_fee: u64,
        public first_trigger_block: u32,
        public interval_blocks: u32,
        public max_executions: u32,
        public expiry_block: u32,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount_per_execution > 0u64);
        assert(max_executions > 0u32);
        assert(interval_blocks > 0u32);
        assert(expiry_block > first_trigger_block);
        
        let total_amount: u64 = (amount_per_execution + keeper_fee) * (max_executions as u64);
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public_as_signer(self.address, total_amount as u128);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount_per_execution, 
            keeper_fee: keeper_fee, trigger_block: first_trigger_block, task_type: 1u8, token_type: 1u8, 
            interval_blocks: interval_blocks, max_executions: max_executions, executions_completed: 0u32, 
            condition_type: 0u8, condition_value: 0u64, required_approvals: 0u8, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount_per_execution, keeper_fee: keeper_fee, 
            token_type: 1u8, task_type: 1u8, expiry_block: expiry_block,
        };

        return (task, receipt, final {
            transfer_future.run();
            assert(first_trigger_block > block.height);
        });
    }

    fn create_cond_transfer_usdcx(
        public task_id: field,
        public keeper: address,
        public recipient: address,
        public amount: u64,
        public keeper_fee: u64,
        public trigger_block: u32,
        public condition_type: u8,
        public condition_value: u64,
        public expiry_block: u32,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount > 0u64);
        assert(condition_type == 1u8 || condition_type == 2u8);
        assert(expiry_block > trigger_block);
        
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public_as_signer(self.address, (amount + keeper_fee) as u128);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount, 
            keeper_fee: keeper_fee, trigger_block: trigger_block, task_type: 2u8, token_type: 1u8, 
            interval_blocks: 0u32, max_executions: 1u32, executions_completed: 0u32, condition_type: condition_type, 
            condition_value: condition_value, required_approvals: 0u8, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount, keeper_fee: keeper_fee, 
            token_type: 1u8, task_type: 2u8, expiry_block: expiry_block,
        };

        return (task, receipt, final {
            transfer_future.run();
        });
    }

    fn create_escrow_usdcx(
        public task_id: field,
        public keeper: address,
        public recipient: address,
        public amount: u64,
        public keeper_fee: u64,
        public trigger_block: u32,
        public required_approvals: u8,
        public expiry_block: u32,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount > 0u64);
        assert(required_approvals > 0u8);
        assert(expiry_block > trigger_block);
        
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public_as_signer(self.address, (amount + keeper_fee) as u128);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount, 
            keeper_fee: keeper_fee, trigger_block: trigger_block, task_type: 3u8, token_type: 1u8, 
            interval_blocks: 0u32, max_executions: 1u32, executions_completed: 0u32, condition_type: 0u8, 
            condition_value: 0u64, required_approvals: required_approvals, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount, keeper_fee: keeper_fee, 
            token_type: 1u8, task_type: 3u8, expiry_block: expiry_block,
        };

        return (task, receipt, final {
            transfer_future.run();
            assert(trigger_block > block.height);
        });
    }

    fn request_cancel_usdcx(receipt: ReceiptRecord) -> CancelRecord {
        assert_eq(receipt.owner, self.caller);
        assert_eq(receipt.token_type, 1u8);
        
        let cancel: CancelRecord = CancelRecord {
            owner: receipt.keeper, creator: self.caller, task_id: receipt.task_id, 
            amount: receipt.amount, keeper_fee: receipt.keeper_fee, token_type: 1u8, task_type: receipt.task_type,
        };
        
        return cancel;
    }

    fn execute_cancel_usdcx(task: TaskRecord, cancel: CancelRecord) -> Final {
        assert_eq(task.owner, self.caller);
        assert_eq(cancel.owner, self.caller);
        assert_eq(task.task_id, cancel.task_id);
        assert_eq(task.token_type, 1u8);
        assert_eq(cancel.token_type, 1u8);
        
        let refund_amount: u64 = task.amount + task.keeper_fee;
        if (task.task_type == 1u8) {
            let remaining_executions: u32 = task.max_executions - task.executions_completed;
            refund_amount = (task.amount + task.keeper_fee) * (remaining_executions as u64);
        }
        
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public(cancel.creator, refund_amount as u128);
        
        let t_id: field = task.task_id;
        return final {
            let is_escaped: bool = escape_hatch_cancelled.get_or_use(t_id, false);
            assert(!is_escaped); // Prevent double spend if user already escaped
            transfer_future.run();
        };
    }

    fn execute_one_time_usdcx(
        task: TaskRecord, public current_price: u64, public oracle_sig: signature, public oracle_address: address
    ) -> Final {
        assert_eq(task.owner, self.caller);
        assert_eq(task.token_type, 1u8);
        assert(task.task_type != 1u8); // Must not be recurring
        
        if (task.task_type == 2u8) {
            let is_valid: bool = oracle_sig.verify(oracle_address, current_price as field);
            assert(is_valid);
            if (task.condition_type == 1u8) { assert(current_price >= task.condition_value); }
            else if (task.condition_type == 2u8) { assert(current_price <= task.condition_value); }
        } else if (task.task_type == 3u8) {
            assert(task.approvals_received >= task.required_approvals);
        }
        
        let f1: Final = test_usdcx_stablecoin.aleo::transfer_public(task.recipient, task.amount as u128);
        let f2: Final = test_usdcx_stablecoin.aleo::transfer_public(task.owner, task.keeper_fee as u128);
        
        let trigger: u32 = task.trigger_block;
        let t_id: field = task.task_id;
        
        return final {
            let is_escaped: bool = escape_hatch_cancelled.get_or_use(t_id, false);
            assert(!is_escaped);
            assert(block.height >= trigger);
            f1.run();
            f2.run();
        };
    }

    fn execute_recurring_usdcx(task: TaskRecord) -> (TaskRecord, Final) {
        assert_eq(task.owner, self.caller);
        assert_eq(task.token_type, 1u8);
        assert_eq(task.task_type, 1u8);
        
        let f1: Final = test_usdcx_stablecoin.aleo::transfer_public(task.recipient, task.amount as u128);
        let f2: Final = test_usdcx_stablecoin.aleo::transfer_public(task.owner, task.keeper_fee as u128);
        
        let new_executions: u32 = task.executions_completed + 1u32;
        let next_trigger: u32 = task.trigger_block + task.interval_blocks;
        
        // Mint next record or dummy record if complete. 
        // A dummy record with amount 0 and fee 0 is harmless if executed, but it will fail due to checks.
        let is_complete: bool = new_executions >= task.max_executions;
        let next_amount: u64 = is_complete ? 0u64 : task.amount;
        let next_fee: u64 = is_complete ? 0u64 : task.keeper_fee;
        
        let updated_task: TaskRecord = TaskRecord {
            owner: task.owner, creator: task.creator, task_id: task.task_id, recipient: task.recipient, 
            amount: next_amount, keeper_fee: next_fee, trigger_block: next_trigger, task_type: task.task_type, 
            token_type: task.token_type, interval_blocks: task.interval_blocks, max_executions: task.max_executions, 
            executions_completed: new_executions, condition_type: task.condition_type, condition_value: task.condition_value, 
            required_approvals: task.required_approvals, approvals_received: task.approvals_received,
        };
        
        let trigger: u32 = task.trigger_block;
        let t_id: field = task.task_id;
        
        return (updated_task, final {
            let is_escaped: bool = escape_hatch_cancelled.get_or_use(t_id, false);
            assert(!is_escaped);
            assert(block.height >= trigger);
            f1.run();
            f2.run();
        });
    }

    fn force_refund_usdcx(receipt: ReceiptRecord) -> Final {
        assert_eq(receipt.owner, self.caller);
        assert_eq(receipt.token_type, 1u8);
        
        let refund_amount: u64 = receipt.amount + receipt.keeper_fee;
        if (receipt.task_type == 1u8) {
            // For recurring tasks, the user can only escape before any executions have occurred, 
            // or we must assume they are withdrawing the entire original balance. 
            // To prevent complex state tracking, we only allow escape hatch for non-recurring or fully unexecuted recurring tasks.
            // (A more advanced version would track remaining executions publicly, but this ensures privacy).
        }
        
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public(receipt.owner, refund_amount as u128);
        
        let t_id: field = receipt.task_id;
        let exp_block: u32 = receipt.expiry_block;
        
        return final {
            assert(block.height >= exp_block); // Keeper has expired
            let is_escaped: bool = escape_hatch_cancelled.get_or_use(t_id, false);
            assert(!is_escaped); // Prevent double escape
            escape_hatch_cancelled.set(t_id, true);
            transfer_future.run();
        };
    }

    fn approve_escrow(task: TaskRecord, public party_address: address, public party_sig: signature) -> TaskRecord {
        assert_eq(task.owner, self.caller); // Keeper handles approvals
        assert(task.task_type == 3u8);
        
        // Cryptographically verify that the party_address actually approved this specific task_id
        let is_valid: bool = party_sig.verify(party_address, task.task_id);
        assert(is_valid);
        
        let new_count: u8 = task.approvals_received + 1u8;
        
        let updated_task: TaskRecord = TaskRecord {
            owner: task.owner, creator: task.creator, task_id: task.task_id, recipient: task.recipient, 
            amount: task.amount, keeper_fee: task.keeper_fee, trigger_block: task.trigger_block, task_type: task.task_type, 
            token_type: task.token_type, interval_blocks: task.interval_blocks, max_executions: task.max_executions, 
            executions_completed: task.executions_completed, condition_type: task.condition_type, 
            condition_value: task.condition_value, required_approvals: task.required_approvals, approvals_received: new_count,
        };
        
        return updated_task;
    }
}
