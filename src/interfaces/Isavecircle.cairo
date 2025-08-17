use save_circle::enums::Enums::{LockType, TimeUnit};
use save_circle::structs::Structs::{GroupInfo, GroupMember, UserActivity, UserStatistics, UserGroupDetails, ProfileViewData, UserProfile};
use starknet::ContractAddress;

#[starknet::interface]
pub trait Isavecircle<TContractState> {
    fn register_user(ref self: TContractState, name: ByteArray, avatar: ByteArray) -> bool;

    fn get_user_profile_view_data(self: @TContractState, user_address: ContractAddress) -> ProfileViewData;

    fn create_public_group(
        ref self: TContractState,
        name: ByteArray,
        description: ByteArray,
        member_limit: u32,
        contribution_amount: u256,
        lock_type: LockType,
        cycle_duration: u64,
        cycle_unit: TimeUnit,
        requires_lock: bool,
        min_reputation_score: u32,
    ) -> u256;

    fn get_group_info(self: @TContractState, group_id: u256) -> GroupInfo;

    fn create_private_group(
        ref self: TContractState,
        name: ByteArray,
        description: ByteArray,
        member_limit: u32,
        contribution_amount: u256,
        cycle_duration: u64,
        cycle_unit: TimeUnit,
        invited_members: Array<ContractAddress>,
        requires_lock: bool,
        lock_type: LockType,
        min_reputation_score: u32,
    ) -> u256;
 
    fn get_user_profile(self: @TContractState, user_address: ContractAddress) -> UserProfile;

    fn join_group(ref self: TContractState, group_id: u256) -> u32;

    fn get_group_member(self: @TContractState, group_id: u256, member_index: u32) -> GroupMember;

    fn get_user_member_index(self: @TContractState, user: ContractAddress, group_id: u256) -> u32;

    fn get_user_joined_groups(self: @TContractState, user_address: ContractAddress) -> Array<UserGroupDetails>;

    fn get_user_activities(self: @TContractState, user_address: ContractAddress, limit: u32) -> Array<UserActivity>;
    
    fn get_user_statistics(self: @TContractState, user_address: ContractAddress) -> UserStatistics;
    
    fn is_group_member(self: @TContractState, group_id: u256, user: ContractAddress) -> bool;

    fn lock_liquidity(
        ref self: TContractState, token_address: ContractAddress, amount: u256, group_id: u256,
    ) -> bool;
    fn get_locked_balance(self: @TContractState, user: ContractAddress) -> u256;
    // Withdrawal functions - only callable at end of cycle
    fn withdraw_locked(ref self: TContractState, group_id: u256) -> u256;
    fn get_penalty_locked(self: @TContractState, user: ContractAddress, group_id: u256) -> u256;
    fn has_completed_circle(self: @TContractState, user: ContractAddress, group_id: u256) -> bool;
    fn contribute(ref self: TContractState, group_id: u256) -> bool;

    fn get_insurance_pool_balance(self: @TContractState, group_id: u256) -> u256;
    fn get_protocol_treasury(self: @TContractState) -> u256;
    fn activate_group(ref self: TContractState, group_id: u256) -> bool;
    fn distribute_payout(ref self: TContractState, group_id: u256) -> bool;
    fn get_next_payout_recipient(self: @TContractState, group_id: u256) -> GroupMember;
    fn get_payout_order(self: @TContractState, group_id: u256) -> Array<ContractAddress>;
}
