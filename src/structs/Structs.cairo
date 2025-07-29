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
    pub group_id: u256,
    pub user_address: ContractAddress,
    pub joined_at: u64,
    pub contribution_amount: u256,
    pub member_index: u32,
}

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct GroupInfo {
    pub group_id: u256,
    pub creator: ContractAddress,
    pub member_limit: u32,
    pub contribution_amount: u256,
    pub lock_type: LockType,
    pub cycle_duration: u64,
    pub cycle_unit: TimeUnit,
    pub members: u32,
    pub state: GroupState,
    pub current_cycle: u64,
    pub payout_order: u32,
    pub start_time: u64,
    pub total_cycles: u32,
    pub visibility: GroupVisibility,
    pub requires_lock: bool,
    pub requires_reputation_score: u32,
    pub invited_members: u32,
}

#[derive(Drop, Serde, Copy, starknet::Store)]
pub struct GroupMember {
    pub user: ContractAddress,
    pub group_id: u256,
    pub locked_amount: u256,
    pub joined_at: u64,
    pub member_index: u32,
    pub payout_cycle: u32,
    pub has_been_paid: bool,
    pub contribution_count: u32,
    pub late_contributions: u32,
    pub missed_contributions: u32,
}
