use save_circle::enums::Enums::{GroupVisibility, LockType, TimeUnit};
use save_circle::structs::Structs::{GroupInfo, GroupMember, UserProfile, UserActivity, UserStatistics, UserGroupDetails, ProfileViewData};
use starknet::ContractAddress;

#[starknet::interface]
pub trait Isavecircle<TContractState> {
    fn register_user(ref self: TContractState, name: felt252, avatar: felt252) -> bool;

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


    fn join_group(ref self: TContractState, group_id: u256) -> u32;

    fn get_group_member(self: @TContractState, group_id: u256, member_index: u32) -> GroupMember;

    fn get_user_member_index(self: @TContractState, user: ContractAddress, group_id: u256) -> u32;

    fn get_user_joined_groups(self: @TContractState, user_address: ContractAddress) -> Array<UserGroupDetails>;

    fn get_user_activities(self: @TContractState, user_address: ContractAddress, limit: u32) -> Array<UserActivity>;
    
    fn get_user_statistics(self: @TContractState, user_address: ContractAddress) -> UserStatistics;
    
    fn is_group_member(self: @TContractState, group_id: u256, user: ContractAddress) -> bool;
}
