use save_circle::structs::Structs::UserProfile;
use starknet::ContractAddress;

#[starknet::interface]
pub trait Isavecircle<TContractState> {
    fn register_user(ref self: TContractState, name: felt252, avatar: felt252) -> bool;
    fn get_user_profile(self: @TContractState, user_address: ContractAddress) -> UserProfile;
}
