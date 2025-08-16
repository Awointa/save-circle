use save_circle::enums::Enums::{GroupState, GroupVisibility, LockType, TimeUnit, ActivityType};
use starknet::ContractAddress;

#[derive(Drop, Serde, Copy, starknet::Store)]
pub struct UserProfile {
    pub user_address: ContractAddress,
    pub name: felt252,
    pub avatar: felt252,
    pub is_registered: bool,
    pub total_lock_amount: u256,
    pub profile_created_at: u64,
    pub reputation_score: u32,

    pub total_contribution: u256,
    pub total_joined_groups: u32,
    pub total_created_groups: u32,
    pub total_earned: u256,
    pub completed_cycles: u32,
    pub active_groups: u32,
    pub on_time_payments: u32,
    pub total_payments: u32,
    pub payment_rate: u256,
    pub average_contribution: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct UserActivity {
    pub activity_id: u256,
    pub user_address: ContractAddress,
    pub activity_type: ActivityType,
    pub description:  felt252,
    pub amount: u256,
    pub group_id: Option<u256>,
    pub timestamp: u64,
    pub is_positive_amount: bool
}

#[derive(Drop, Serde, starknet::Store)]
pub struct joined_group {
    pub group_id: u256,
    pub user_address: ContractAddress,
    pub joined_at: u64,
    pub contribution_amount: u256,
    pub member_index: u32,
}

#[derive(Drop, Clone, Serde, starknet::Store)]
pub struct GroupInfo {
    pub group_id: u256,
    pub group_name: ByteArray,
    pub description: ByteArray,
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
    pub last_payout_time: u64,
    pub total_cycles: u32,
    pub visibility: GroupVisibility,
    pub requires_lock: bool,
    pub requires_reputation_score: u32,
    pub completed_cycles: u32,
    pub total_pool_amount: u256,
    pub remaining_pool_amount: u256,
    pub next_payout_recipient: ContractAddress,
    pub is_active: bool
}

#[derive(Drop, Serde, Clone, starknet::Store)]
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
    pub total_contributed: u256,
    pub total_recieved: u256,
    pub is_active: bool,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct PayoutRecord {
    pub payout_id: u256,
    pub group_id: u256,
    pub recipient: ContractAddress,
    pub amount: u256,
    pub cycle_number: u64,
    pub timestamp: u64,
    pub transaction_hash: felt252,
}

// Contract view functions should return these processed structs
#[derive(Drop, Serde)]
pub struct ProfileViewData {
    pub profile: UserProfile,
    pub recent_activities: Array<UserActivity>,
    pub joined_groups: Array<GroupInfo>,
    pub statistics: UserStatistics,
}

#[derive(Drop, Clone, Serde)]
pub struct UserGroupDetails {
    pub group_info: GroupInfo,
    pub member_data: GroupMember,
    pub next_payout_date: u64,
    pub position_in_queue: u32,
    pub total_contributed_so_far: u256,
    pub expected_payout_amount: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct UserStatistics {
    pub user_address: ContractAddress,
    pub total_saved: u256,
    pub total_earned: u256,
    pub success_rate: u32, // percentage of on-time payments
    pub average_cycle_duration: u64,
    pub favorite_contribution_amount: u256,
    pub longest_active_streak: u32,
    pub current_active_streak: u32,
    pub groups_completed_successfully: u32,
    pub groups_left_early: u32,
    pub total_penalties_paid: u256,
    pub updated_at: u64,
}
