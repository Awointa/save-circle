use starknet::ContractAddress;
use save_circle::enums::Enums::{TimeUnit, GroupVisibility};

#[derive(Drop, starknet::Event)]
pub struct UserRegistered {
    pub user: ContractAddress,
    pub name: felt252,
}

#[derive(Drop, starknet::Event)]
pub struct GroupCreated{
   pub group_id: u256,
   pub creator: ContractAddress,
   pub member_limit: u8,
   pub contribution_amount: u256,
   pub cycle_duration: u64,
   pub cycle_unit: TimeUnit,
   pub visibility: GroupVisibility,
   pub requires_lock: bool,
}