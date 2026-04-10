// Advanced Pay - Recurring, Conditional, Escrow
// ============================================

import credits.aleo;
import test_usdcx_stablecoin.aleo;

program advanced_pay.aleo {

    struct TaskInfo {
        creator: address,
        recipient: address,
        amount: u64,
        trigger_block: u32,
        task_type: u8, // 1=Recurring, 2=Conditional, 3=Escrow
        token_type: u8, // 0=Credits, 1=USDCx
        interval_blocks: u32,
        max_executions: u32,
        executions_completed: u32,
        condition_type: u8,
        condition_value: u64,
        required_approvals: u8,
        approvals_received: u8,
        is_approved: bool,
    }

    mapping task_data: field => TaskInfo;
    mapping escrow_parties: field => bool;
    mapping escrow_approvals: field => bool;

    record RecurringAuth { owner: address, task_id: field, total_amount: u64, amount_per_execution: u64, max_executions: u32, token_type: u8 }
    record ConditionalAuth { owner: address, task_id: field, amount: u64, token_type: u8 }
    record EscrowAuth { owner: address, task_id: field, party_address: address, amount: u64, has_approved: bool, token_type: u8 }

    @noupgrade
    constructor() {}

    fn create_recur_transfer(
        public task_id: field,
        public recipient: address,
        public amount_per_execution: u64,
        public first_trigger_block: u32,
        public interval_blocks: u32,
        public max_executions: u32,
    ) -> (RecurringAuth, Final) {
        assert(amount_per_execution > 0u64);
        assert(max_executions > 0u32);
        assert(interval_blocks > 0u32);
        let total_amount: u64 = amount_per_execution * (max_executions as u64);
        let transfer_future: Final = credits.aleo::transfer_public_as_signer(self.address, total_amount);
        let auth: RecurringAuth = RecurringAuth {
            owner: self.caller, task_id: task_id, total_amount: total_amount, amount_per_execution: amount_per_execution, 
            max_executions: max_executions, token_type: 0u8,
        };
        let creator: address = self.caller;
        return (auth, final {
            transfer_future.run();
            assert(first_trigger_block > block.height);
            assert(!task_data.contains(task_id));
            let new_info: TaskInfo = TaskInfo {
                creator: creator, recipient: recipient, amount: amount_per_execution, trigger_block: first_trigger_block, 
                task_type: 1u8, token_type: 0u8, interval_blocks: interval_blocks, max_executions: max_executions, 
                executions_completed: 0u32, condition_type: 0u8, condition_value: 0u64, required_approvals: 0u8,
                approvals_received: 0u8, is_approved: false,
            };
            task_data.set(task_id, new_info);
        });
    }

    fn create_cond_transfer(
        public task_id: field,
        public recipient: address,
        public amount: u64,
        public trigger_block: u32,
        public condition_type: u8,
        public condition_value: u64,
    ) -> (ConditionalAuth, Final) {
        assert(amount > 0u64);
        assert(condition_type == 1u8 || condition_type == 2u8);
        let transfer_future: Final = credits.aleo::transfer_public_as_signer(self.address, amount);
        let auth: ConditionalAuth = ConditionalAuth { 
            owner: self.caller, task_id: task_id, amount: amount, token_type: 0u8 
        };
        let creator: address = self.caller;
        return (auth, final {
            transfer_future.run();
            assert(!task_data.contains(task_id));
            let new_info: TaskInfo = TaskInfo {
                creator: creator, recipient: recipient, amount: amount, trigger_block: trigger_block, task_type: 2u8, 
                token_type: 0u8, interval_blocks: 0u32, max_executions: 1u32, executions_completed: 0u32,
                condition_type: condition_type, condition_value: condition_value, required_approvals: 0u8,
                approvals_received: 0u8, is_approved: false,
            };
            task_data.set(task_id, new_info);
        });
    }

    fn create_escrow(
        public task_id: field,
        public recipient: address,
        public amount: u64,
        public trigger_block: u32,
        public required_approvals: u8,
    ) -> (EscrowAuth, Final) {
        assert(amount > 0u64);
        assert(required_approvals > 0u8);
        let transfer_future: Final = credits.aleo::transfer_public_as_signer(self.address, amount);
        let auth: EscrowAuth = EscrowAuth {
            owner: self.caller, task_id: task_id, party_address: self.caller, amount: amount, has_approved: false, token_type: 0u8,
        };
        let creator: address = self.caller;
        return (auth, final {
            transfer_future.run();
            assert(trigger_block > block.height);
            assert(!task_data.contains(task_id));
            let new_info: TaskInfo = TaskInfo {
                creator: creator, recipient: recipient, amount: amount, trigger_block: trigger_block, task_type: 3u8, 
                token_type: 0u8, interval_blocks: 0u32, max_executions: 1u32, executions_completed: 0u32,
                condition_type: 0u8, condition_value: 0u64, required_approvals: required_approvals,
                approvals_received: 0u8, is_approved: false,
            };
            task_data.set(task_id, new_info);
            let creator_field: field = creator as field;
            let key: field = task_id + creator_field;
            escrow_parties.set(key, true);
        });
    }

    fn execute_transfer(
        public task_id: field, public recipient: address, public amount: u64, public current_price: u64,
    ) -> Final {
        let transfer_future: Final = credits.aleo::transfer_public(recipient, amount);
        return final {
            let info: TaskInfo = task_data.get(task_id);
            assert_eq(info.token_type, 0u8);
            assert(block.height >= info.trigger_block);
            assert_eq(info.recipient, recipient);
            assert_eq(info.amount, amount);
            if (info.task_type == 2u8) {
                if (info.condition_type == 1u8) { assert(current_price >= info.condition_value); }
                else if (info.condition_type == 2u8) { assert(current_price <= info.condition_value); }
            } else if (info.task_type == 3u8) {
                assert(info.is_approved);
            }
            transfer_future.run();
            if (info.task_type == 1u8) {
                let new_executions: u32 = info.executions_completed + 1u32;
                if (new_executions < info.max_executions) {
                    let next_trigger: u32 = info.trigger_block + info.interval_blocks;
                    let updated_info: TaskInfo = TaskInfo {
                        creator: info.creator, recipient: info.recipient, amount: info.amount, trigger_block: next_trigger, 
                        task_type: info.task_type, token_type: info.token_type, interval_blocks: info.interval_blocks, 
                        max_executions: info.max_executions, executions_completed: new_executions, condition_type: info.condition_type,
                        condition_value: info.condition_value, required_approvals: info.required_approvals,
                        approvals_received: info.approvals_received, is_approved: info.is_approved,
                    };
                    task_data.set(task_id, updated_info);
                } else { task_data.remove(task_id); }
            } else {
                task_data.remove(task_id);
            }
        };
    }

    fn cancel_recur_transfer(auth: RecurringAuth) -> Final {
        assert_eq(auth.owner, self.caller);
        assert_eq(auth.token_type, 0u8);
        let transfer_future: Final = credits.aleo::transfer_public(self.caller, auth.total_amount);
        let c_task_id: field = auth.task_id;
        let c_amount: u64 = auth.amount_per_execution;
        let c_max_exec: u32 = auth.max_executions;
        let caller: address = self.caller;
        return final {
            let info: TaskInfo = task_data.get(c_task_id);
            assert_eq(info.creator, caller);
            assert_eq(info.task_type, 1u8);
            assert_eq(info.amount, c_amount);
            assert_eq(info.max_executions, c_max_exec);
            assert_eq(info.token_type, 0u8);
            transfer_future.run();
            task_data.remove(c_task_id);
        };
    }

    fn cancel_cond_transfer(auth: ConditionalAuth) -> Final {
        assert_eq(auth.owner, self.caller);
        assert_eq(auth.token_type, 0u8);
        let transfer_future: Final = credits.aleo::transfer_public(self.caller, auth.amount);
        let c_task_id: field = auth.task_id;
        let c_amount: u64 = auth.amount;
        let caller: address = self.caller;
        return final {
            let info: TaskInfo = task_data.get(c_task_id);
            assert_eq(info.creator, caller);
            assert_eq(info.amount, c_amount);
            assert_eq(info.token_type, 0u8);
            assert_eq(info.task_type, 2u8);
            transfer_future.run();
            task_data.remove(c_task_id);
        };
    }

    fn cancel_escrow(auth: EscrowAuth) -> Final {
        assert_eq(auth.owner, self.caller);
        assert_eq(auth.party_address, self.caller);
        assert_eq(auth.token_type, 0u8);
        let transfer_future: Final = credits.aleo::transfer_public(self.caller, auth.amount);
        let c_task_id: field = auth.task_id;
        let c_amount: u64 = auth.amount;
        let caller: address = self.caller;
        return final {
            let info: TaskInfo = task_data.get(c_task_id);
            assert_eq(info.creator, caller);
            assert_eq(info.amount, c_amount);
            assert_eq(info.token_type, 0u8);
            assert_eq(info.task_type, 3u8);
            assert(!info.is_approved);
            transfer_future.run();
            task_data.remove(c_task_id);
        };
    }

    fn create_recur_transfer_usdcx(
        public task_id: field,
        public recipient: address,
        public amount_per_execution: u64,
        public first_trigger_block: u32,
        public interval_blocks: u32,
        public max_executions: u32,
    ) -> (RecurringAuth, Final) {
        assert(amount_per_execution > 0u64);
        assert(max_executions > 0u32);
        assert(interval_blocks > 0u32);
        let total_amount: u64 = amount_per_execution * (max_executions as u64);
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public_as_signer(self.address, total_amount as u128);
        let auth: RecurringAuth = RecurringAuth {
            owner: self.caller, task_id: task_id, total_amount: total_amount, amount_per_execution: amount_per_execution, 
            max_executions: max_executions, token_type: 1u8,
        };
        let creator: address = self.caller;
        return (auth, final {
            transfer_future.run();
            assert(first_trigger_block > block.height);
            assert(!task_data.contains(task_id));
            let new_info: TaskInfo = TaskInfo {
                creator: creator, recipient: recipient, amount: amount_per_execution, trigger_block: first_trigger_block, 
                task_type: 1u8, token_type: 1u8, interval_blocks: interval_blocks, max_executions: max_executions, 
                executions_completed: 0u32, condition_type: 0u8, condition_value: 0u64, required_approvals: 0u8,
                approvals_received: 0u8, is_approved: false,
            };
            task_data.set(task_id, new_info);
        });
    }

    fn create_cond_transfer_usdcx(
        public task_id: field,
        public recipient: address,
        public amount: u64,
        public trigger_block: u32,
        public condition_type: u8,
        public condition_value: u64,
    ) -> (ConditionalAuth, Final) {
        assert(amount > 0u64);
        assert(condition_type == 1u8 || condition_type == 2u8);
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public_as_signer(self.address, amount as u128);
        let auth: ConditionalAuth = ConditionalAuth { 
            owner: self.caller, task_id: task_id, amount: amount, token_type: 1u8 
        };
        let creator: address = self.caller;
        return (auth, final {
            transfer_future.run();
            assert(!task_data.contains(task_id));
            let new_info: TaskInfo = TaskInfo {
                creator: creator, recipient: recipient, amount: amount, trigger_block: trigger_block, task_type: 2u8, 
                token_type: 1u8, interval_blocks: 0u32, max_executions: 1u32, executions_completed: 0u32,
                condition_type: condition_type, condition_value: condition_value, required_approvals: 0u8,
                approvals_received: 0u8, is_approved: false,
            };
            task_data.set(task_id, new_info);
        });
    }

    fn create_escrow_usdcx(
        public task_id: field,
        public recipient: address,
        public amount: u64,
        public trigger_block: u32,
        public required_approvals: u8,
    ) -> (EscrowAuth, Final) {
        assert(amount > 0u64);
        assert(required_approvals > 0u8);
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public_as_signer(self.address, amount as u128);
        let auth: EscrowAuth = EscrowAuth {
            owner: self.caller, task_id: task_id, party_address: self.caller, amount: amount, has_approved: false, token_type: 1u8,
        };
        let creator: address = self.caller;
        return (auth, final {
            transfer_future.run();
            assert(trigger_block > block.height);
            assert(!task_data.contains(task_id));
            let new_info: TaskInfo = TaskInfo {
                creator: creator, recipient: recipient, amount: amount, trigger_block: trigger_block, task_type: 3u8, 
                token_type: 1u8, interval_blocks: 0u32, max_executions: 1u32, executions_completed: 0u32,
                condition_type: 0u8, condition_value: 0u64, required_approvals: required_approvals,
                approvals_received: 0u8, is_approved: false,
            };
            task_data.set(task_id, new_info);
            let creator_field: field = creator as field;
            let key: field = task_id + creator_field;
            escrow_parties.set(key, true);
        });
    }

    fn execute_transfer_usdcx(
        public task_id: field, public recipient: address, public amount: u64, public current_price: u64,
    ) -> Final {
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public(recipient, amount as u128);
        return final {
            let info: TaskInfo = task_data.get(task_id);
            assert_eq(info.token_type, 1u8);
            assert(block.height >= info.trigger_block);
            assert_eq(info.recipient, recipient);
            assert_eq(info.amount, amount);
            if (info.task_type == 2u8) {
                if (info.condition_type == 1u8) { assert(current_price >= info.condition_value); }
                else if (info.condition_type == 2u8) { assert(current_price <= info.condition_value); }
            } else if (info.task_type == 3u8) {
                assert(info.is_approved);
            }
            transfer_future.run();
            if (info.task_type == 1u8) {
                let new_executions: u32 = info.executions_completed + 1u32;
                if (new_executions < info.max_executions) {
                    let next_trigger: u32 = info.trigger_block + info.interval_blocks;
                    let updated_info: TaskInfo = TaskInfo {
                        creator: info.creator, recipient: info.recipient, amount: info.amount, trigger_block: next_trigger, 
                        task_type: info.task_type, token_type: info.token_type, interval_blocks: info.interval_blocks, 
                        max_executions: info.max_executions, executions_completed: new_executions, condition_type: info.condition_type,
                        condition_value: info.condition_value, required_approvals: info.required_approvals,
                        approvals_received: info.approvals_received, is_approved: info.is_approved,
                    };
                    task_data.set(task_id, updated_info);
                } else { task_data.remove(task_id); }
            } else {
                task_data.remove(task_id);
            }
        };
    }

    fn cancel_recur_transfer_usdcx(auth: RecurringAuth) -> Final {
        assert_eq(auth.owner, self.caller);
        assert_eq(auth.token_type, 1u8);
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public(self.caller, auth.total_amount as u128);
        let c_task_id: field = auth.task_id;
        let c_amount: u64 = auth.amount_per_execution;
        let c_max_exec: u32 = auth.max_executions;
        let caller: address = self.caller;
        return final {
            let info: TaskInfo = task_data.get(c_task_id);
            assert_eq(info.creator, caller);
            assert_eq(info.task_type, 1u8);
            assert_eq(info.amount, c_amount);
            assert_eq(info.max_executions, c_max_exec);
            assert_eq(info.token_type, 1u8);
            transfer_future.run();
            task_data.remove(c_task_id);
        };
    }

    fn cancel_cond_transfer_usdcx(auth: ConditionalAuth) -> Final {
        assert_eq(auth.owner, self.caller);
        assert_eq(auth.token_type, 1u8);
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public(self.caller, auth.amount as u128);
        let c_task_id: field = auth.task_id;
        let c_amount: u64 = auth.amount;
        let caller: address = self.caller;
        return final {
            let info: TaskInfo = task_data.get(c_task_id);
            assert_eq(info.creator, caller);
            assert_eq(info.amount, c_amount);
            assert_eq(info.token_type, 1u8);
            assert_eq(info.task_type, 2u8);
            transfer_future.run();
            task_data.remove(c_task_id);
        };
    }

    fn cancel_escrow_usdcx(auth: EscrowAuth) -> Final {
        assert_eq(auth.owner, self.caller);
        assert_eq(auth.party_address, self.caller);
        assert_eq(auth.token_type, 1u8);
        let transfer_future: Final = test_usdcx_stablecoin.aleo::transfer_public(self.caller, auth.amount as u128);
        let c_task_id: field = auth.task_id;
        let c_amount: u64 = auth.amount;
        let caller: address = self.caller;
        return final {
            let info: TaskInfo = task_data.get(c_task_id);
            assert_eq(info.creator, caller);
            assert_eq(info.amount, c_amount);
            assert_eq(info.token_type, 1u8);
            assert_eq(info.task_type, 3u8);
            assert(!info.is_approved);
            transfer_future.run();
            task_data.remove(c_task_id);
        };
    }

    fn approve_escrow(public task_id: field, auth: EscrowAuth) -> (EscrowAuth, Final) {
        assert_eq(auth.owner, self.caller);
        assert_eq(auth.task_id, task_id);
        assert(!auth.has_approved);
        let updated_auth: EscrowAuth = EscrowAuth {
            owner: auth.owner, task_id: auth.task_id, party_address: auth.party_address, amount: auth.amount, 
            has_approved: true, token_type: auth.token_type,
        };
        let caller: address = self.caller;
        return (updated_auth, final {
            let info: TaskInfo = task_data.get(task_id);
            assert_eq(info.task_type, 3u8);
            assert(!info.is_approved);
            let caller_field: field = caller as field;
            let key: field = task_id + caller_field;
            let is_party: bool = escrow_parties.get_or_use(key, false);
            assert(is_party);
            let already_approved: bool = escrow_approvals.get_or_use(key, false);
            assert(!already_approved);
            escrow_approvals.set(key, true);
            let new_count: u8 = info.approvals_received + 1u8;
            let fully_approved: bool = new_count >= info.required_approvals;
            let updated_info: TaskInfo = TaskInfo {
                creator: info.creator, recipient: info.recipient, amount: info.amount, trigger_block: info.trigger_block, 
                task_type: info.task_type, token_type: info.token_type, interval_blocks: info.interval_blocks, 
                max_executions: info.max_executions, executions_completed: info.executions_completed, 
                condition_type: info.condition_type, condition_value: info.condition_value, required_approvals: info.required_approvals,
                approvals_received: new_count, is_approved: fully_approved,
            };
            task_data.set(task_id, updated_info);
        });
    }

    fn add_escrow_party(
        public task_id: field, public party_address: address, creator_auth: EscrowAuth,
    ) -> (EscrowAuth, EscrowAuth, Final) {
        assert_eq(creator_auth.owner, self.caller);
        assert_eq(creator_auth.task_id, task_id);
        assert_eq(creator_auth.party_address, self.caller);
        let new_party_auth: EscrowAuth = EscrowAuth {
            owner: party_address, task_id: task_id, party_address: party_address, amount: creator_auth.amount, 
            has_approved: false, token_type: creator_auth.token_type,
        };
        let caller: address = self.caller;
        return (creator_auth, new_party_auth, final {
            let info: TaskInfo = task_data.get(task_id);
            assert_eq(info.creator, caller);
            assert_eq(info.task_type, 3u8);
            let party_field: field = party_address as field;
            let key: field = task_id + party_field;
            escrow_parties.set(key, true);
        });
    }
}
