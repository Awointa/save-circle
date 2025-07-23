use save_circle::enums::Enums::{GroupVisibility, TimeUnit};
use starknet::ContractAddress;

#[derive(Drop, starknet::Event)]
pub struct UserRegistered {
    pub user: ContractAddress,
    pub name: felt252,
}

#[derive(Drop, starknet::Event)]
pub struct GroupCreated {
    pub group_id: u256,
    pub creator: ContractAddress,
    pub member_limit: u8,
    pub contribution_amount: u256,
    pub cycle_duration: u64,
    pub cycle_unit: TimeUnit,
    pub visibility: GroupVisibility,
    pub requires_lock: bool,
}

#[derive(Drop, starknet::Event)]
pub struct UserInvited {
    pub group_id: u256,
    pub inviter: ContractAddress,
    pub invitee: ContractAddress,
}
