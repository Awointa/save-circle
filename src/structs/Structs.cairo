use save_circle::enums::Enums::{GroupState, GroupVisibility, LockType, TimeUnit};
use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store)]
pub struct UserProfile {
    pub user_address: ContractAddress,
    pub name: felt252,
    pub avatar: felt252,
    pub is_registered: bool,
    pub total_lock_amount: u256,
    pub profile_created_at: u64,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct joined_group {
    group_id: u64,
    user_address: ContractAddress,
    joined_at: u64,
    contribution_amount: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct GroupInfo {
    group_id: u64,
    creator: ContractAddress,
    member_limit: u8,
    contribution_amount: u256,
    lock_type: LockType,
    cycle_duration: u64,
    cycle_unit: TimeUnit,
    members: u32,
    state: GroupState,
    current_cycle: u64,
    payout_order: u32,
    start_time: u64,
    total_cycles: u32,
    visibility: GroupVisibility,
    requires_lock: bool,
    requires_reputation_score: u32,
    invited_members: u32,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct GroupMember {
    user: ContractAddress,
    group_id: u64,
    locked_amount: u256,
    joined_at: u64,
    member_index: u32,
    payout_cycle: u32,
    has_been_paid: bool,
    contribution_count: u32,
    late_contributions: u32,
    missed_contributions: u32,
}
