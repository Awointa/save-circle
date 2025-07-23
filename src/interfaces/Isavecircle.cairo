use save_circle::structs::Structs::UserProfile;
use save_circle::enums::Enums::{LockType, TimeUnit, GroupVisibility};
use starknet::ContractAddress;

#[starknet::interface]
pub trait Isavecircle<TContractState> {
    fn register_user(ref self: TContractState, name: felt252, avatar: felt252) -> bool;
    fn get_user_profile(self: @TContractState, user_address: ContractAddress) -> UserProfile;

    fn create_group(ref self: TContractState, member_limit: u8, contribution_amount: u256, lock_type: LockType, cycle_duration: u64, cycle_unit: TimeUnit, visibility: GroupVisibility, requires_lock:bool, min_reputation_score: u32) -> u256;

    // fn create_private_group(ref self: TContractState, member_limit: u32, contribution_amount: u256, cycle_duration: u64, cycle_unit: TimeUnit, invited_members: Array<ContractAddress>) -> u256;
}
