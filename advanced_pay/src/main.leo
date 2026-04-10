// Advanced Pay - Recurring, Conditional, Escrow
// ============================================
// Architecture: Fully private using Records. No structs.
//  - User creates a TaskRecord (owned by Keeper) and a ReceiptRecord (owned by User).
//  - To cancel, User creates a CancelRecord (owned by Keeper) using their ReceiptRecord.
//  - Keeper executes the TaskRecord unless a CancelRecord exists.

import credits.aleo;
import test_usdcx_stablecoin.aleo;

program advanced_pay.aleo {

    // --- Records ---

    record TaskRecord {
        owner: address,       // The Keeper's address
        creator: address,     // The User who created the task
        task_id: field,
        recipient: address,
        amount: u64,
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
        token_type: u8,
        task_type: u8,
    }

    record CancelRecord {
        owner: address,       // The Keeper's address
        creator: address,     // The User's address
        task_id: field,
        amount: u64,
        token_type: u8,
        task_type: u8,
    }
    
    // Escrow specific
    record EscrowApprovalRecord {
        owner: address,       // The Keeper's address
        task_id: field,
        party_address: address,
    }

    @noupgrade
    constructor() {}

    fn create_recur_transfer(
        public task_id: field,
        public keeper: address,
        public recipient: address,
        public amount_per_execution: u64,
        public first_trigger_block: u32,
        public interval_blocks: u32,
        public max_executions: u32,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount_per_execution > 0u64);
        assert(max_executions > 0u32);
        assert(interval_blocks > 0u32);
        let total_amount: u64 = amount_per_execution * (max_executions as u64);
        let transfer_future: Final = credits.aleo::transfer_public_as_signer(self.address, total_amount);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount_per_execution, 
            trigger_block: first_trigger_block, task_type: 1u8, token_type: 0u8, interval_blocks: interval_blocks, 
            max_executions: max_executions, executions_completed: 0u32, condition_type: 0u8, condition_value: 0u64, 
            required_approvals: 0u8, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount_per_execution, token_type: 0u8, task_type: 1u8,
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
        public trigger_block: u32,
        public condition_type: u8,
        public condition_value: u64,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount > 0u64);
        assert(condition_type == 1u8 || condition_type == 2u8);
        let transfer_future: Final = credits.aleo::transfer_public_as_signer(self.address, amount);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount, 
            trigger_block: trigger_block, task_type: 2u8, token_type: 0u8, interval_blocks: 0u32, 
            max_executions: 1u32, executions_completed: 0u32, condition_type: condition_type, condition_value: condition_value, 
            required_approvals: 0u8, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount, token_type: 0u8, task_type: 2u8,
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
        public trigger_block: u32,
        public required_approvals: u8,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount > 0u64);
        assert(required_approvals > 0u8);
        let transfer_future: Final = credits.aleo::transfer_public_as_signer(self.address, amount);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount, 
            trigger_block: trigger_block, task_type: 3u8, token_type: 0u8, interval_blocks: 0u32, 
            max_executions: 1u32, executions_completed: 0u32, condition_type: 0u8, condition_value: 0u64, 
            required_approvals: required_approvals, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount, token_type: 0u8, task_type: 3u8,
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
            amount: receipt.amount, token_type: 0u8, task_type: receipt.task_type,
        };
        
        return cancel;
    }

    fn execute_cancel(task: TaskRecord, cancel: CancelRecord) -> Final {
        assert_eq(task.owner, self.caller);
        assert_eq(cancel.owner, self.caller);
        assert_eq(task.task_id, cancel.task_id);
        assert_eq(task.token_type, 0u8);
        assert_eq(cancel.token_type, 0u8);
        
        let refund_amount: u64 = task.amount;
        if (task.task_type == 1u8) {
            let remaining_executions: u32 = task.max_executions - task.executions_completed;
            refund_amount = task.amount * (remaining_executions as u64);
        }
        
        let transfer_future: Final = credits.aleo::transfer_public(cancel.creator, refund_amount);
        
        return final {
            transfer_future.run();
        };
    }

    fn execute_transfer(
        task: TaskRecord, public current_price: u64,
    ) -> (TaskRecord, Final) {
        assert_eq(task.owner, self.caller);
        assert_eq(task.token_type, 0u8);
        
        if (task.task_type == 2u8) {
            if (task.condition_type == 1u8) { assert(current_price >= task.condition_value); }
            else if (task.condition_type == 2u8) { assert(current_price <= task.condition_value); }
        } else if (task.task_type == 3u8) {
            assert(task.approvals_received >= task.required_approvals);
        }
        
        let transfer_future: Final = credits.aleo::transfer_public(task.recipient, task.amount);
        
        // Create updated record for recurring
        let updated_task: TaskRecord = task;
        
        if (task.task_type == 1u8) {
            let new_executions: u32 = task.executions_completed + 1u32;
            if (new_executions < task.max_executions) {
                let next_trigger: u32 = task.trigger_block + task.interval_blocks;
                updated_task = TaskRecord {
                    owner: task.owner, creator: task.creator, task_id: task.task_id, recipient: task.recipient, 
                    amount: task.amount, trigger_block: next_trigger, task_type: task.task_type, 
                    token_type: task.token_type, interval_blocks: task.interval_blocks, max_executions: task.max_executions, 
                    executions_completed: new_executions, condition_type: task.condition_type, condition_value: task.condition_value, 
                    required_approvals: task.required_approvals, approvals_received: task.approvals_received,
                };
            }
        }
        
        let trigger: u32 = task.trigger_block;
        return (updated_task, final {
            assert(block.height >= trigger);
            transfer_future.run();
        });
    }

    fn create_recur_transfer_usdcx(
        public task_id: field,
        public keeper: address,
        public recipient: address,
        public amount_per_execution: u64,
        public first_trigger_block: u32,
        public interval_blocks: u32,
        public max_executions: u32,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount_per_execution > 0u64);
        assert(max_executions > 0u32);
        assert(interval_blocks > 0u32);
        let total_amount: u64 = amount_per_execution * (max_executions as u64);
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public_as_signer(self.address, total_amount as u128);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount_per_execution, 
            trigger_block: first_trigger_block, task_type: 1u8, token_type: 1u8, interval_blocks: interval_blocks, 
            max_executions: max_executions, executions_completed: 0u32, condition_type: 0u8, condition_value: 0u64, 
            required_approvals: 0u8, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount_per_execution, token_type: 1u8, task_type: 1u8,
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
        public trigger_block: u32,
        public condition_type: u8,
        public condition_value: u64,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount > 0u64);
        assert(condition_type == 1u8 || condition_type == 2u8);
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public_as_signer(self.address, amount as u128);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount, 
            trigger_block: trigger_block, task_type: 2u8, token_type: 1u8, interval_blocks: 0u32, 
            max_executions: 1u32, executions_completed: 0u32, condition_type: condition_type, condition_value: condition_value, 
            required_approvals: 0u8, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount, token_type: 1u8, task_type: 2u8,
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
        public trigger_block: u32,
        public required_approvals: u8,
    ) -> (TaskRecord, ReceiptRecord, Final) {
        assert(amount > 0u64);
        assert(required_approvals > 0u8);
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public_as_signer(self.address, amount as u128);
        
        let task: TaskRecord = TaskRecord {
            owner: keeper, creator: self.caller, task_id: task_id, recipient: recipient, amount: amount, 
            trigger_block: trigger_block, task_type: 3u8, token_type: 1u8, interval_blocks: 0u32, 
            max_executions: 1u32, executions_completed: 0u32, condition_type: 0u8, condition_value: 0u64, 
            required_approvals: required_approvals, approvals_received: 0u8,
        };
        
        let receipt: ReceiptRecord = ReceiptRecord {
            owner: self.caller, keeper: keeper, task_id: task_id, amount: amount, token_type: 1u8, task_type: 3u8,
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
            amount: receipt.amount, token_type: 1u8, task_type: receipt.task_type,
        };
        
        return cancel;
    }

    fn execute_cancel_usdcx(task: TaskRecord, cancel: CancelRecord) -> Final {
        assert_eq(task.owner, self.caller);
        assert_eq(cancel.owner, self.caller);
        assert_eq(task.task_id, cancel.task_id);
        assert_eq(task.token_type, 1u8);
        assert_eq(cancel.token_type, 1u8);
        
        let refund_amount: u64 = task.amount;
        if (task.task_type == 1u8) {
            let remaining_executions: u32 = task.max_executions - task.executions_completed;
            refund_amount = task.amount * (remaining_executions as u64);
        }
        
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public(cancel.creator, refund_amount as u128);
        
        return final {
            transfer_future.run();
        };
    }

    fn execute_transfer_usdcx(
        task: TaskRecord, public current_price: u64,
    ) -> (TaskRecord, Final) {
        assert_eq(task.owner, self.caller);
        assert_eq(task.token_type, 1u8);
        
        if (task.task_type == 2u8) {
            if (task.condition_type == 1u8) { assert(current_price >= task.condition_value); }
            else if (task.condition_type == 2u8) { assert(current_price <= task.condition_value); }
        } else if (task.task_type == 3u8) {
            assert(task.approvals_received >= task.required_approvals);
        }
        
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public(task.recipient, task.amount as u128);
        
        // Create updated record for recurring
        let updated_task: TaskRecord = task;
        
        if (task.task_type == 1u8) {
            let new_executions: u32 = task.executions_completed + 1u32;
            if (new_executions < task.max_executions) {
                let next_trigger: u32 = task.trigger_block + task.interval_blocks;
                updated_task = TaskRecord {
                    owner: task.owner, creator: task.creator, task_id: task.task_id, recipient: task.recipient, 
                    amount: task.amount, trigger_block: next_trigger, task_type: task.task_type, 
                    token_type: task.token_type, interval_blocks: task.interval_blocks, max_executions: task.max_executions, 
                    executions_completed: new_executions, condition_type: task.condition_type, condition_value: task.condition_value, 
                    required_approvals: task.required_approvals, approvals_received: task.approvals_received,
                };
            }
        }
        
        let trigger: u32 = task.trigger_block;
        return (updated_task, final {
            assert(block.height >= trigger);
            transfer_future.run();
        });
    }

    fn approve_escrow(task: TaskRecord, public party_address: address) -> (EscrowApprovalRecord, TaskRecord) {
        assert_eq(task.owner, self.caller); // Keeper handles approvals
        assert(task.task_type == 3u8);
        
        let approval: EscrowApprovalRecord = EscrowApprovalRecord {
            owner: task.owner, task_id: task.task_id, party_address: party_address,
        };
        
        let new_count: u8 = task.approvals_received + 1u8;
        
        let updated_task: TaskRecord = TaskRecord {
            owner: task.owner, creator: task.creator, task_id: task.task_id, recipient: task.recipient, 
            amount: task.amount, trigger_block: task.trigger_block, task_type: task.task_type, 
            token_type: task.token_type, interval_blocks: task.interval_blocks, max_executions: task.max_executions, 
            executions_completed: task.executions_completed, condition_type: task.condition_type, 
            condition_value: task.condition_value, required_approvals: task.required_approvals, approvals_received: new_count,
        };
        
        return (approval, updated_task);
    }
}
