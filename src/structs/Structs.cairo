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
    group_id: u256,
    user_address: ContractAddress,
    joined_at: u64,
    contribution_amount: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct GroupInfo {
    pub group_id: u256,
    pub creator: ContractAddress,
    pub member_limit: u8,
    pub contribution_amount: u256,
    pub lock_type: LockType,
    pub cycle_duration: u64,
    pub cycle_unit: TimeUnit,
    pub members: u32,
    pub state: GroupState,
    pub current_cycle: u64,
    pub payout_order: u32,
    pub start_time: u64,
    pub total_cycles: u8,
    pub visibility: GroupVisibility,
    pub requires_lock: bool,
    pub requires_reputation_score: u32,
    pub invited_members: u32,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct GroupMember {
    user: ContractAddress,
    group_id: u256,
    locked_amount: u256,
    joined_at: u64,
    member_index: u32,
    payout_cycle: u32,
    has_been_paid: bool,
    contribution_count: u32,
    late_contributions: u32,
    missed_contributions: u32,
}
