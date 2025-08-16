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
    pub member_limit: u32,
    pub contribution_amount: u256,
    pub cycle_duration: u64,
    pub cycle_unit: TimeUnit,
    pub visibility: GroupVisibility,
    pub requires_lock: bool,
}

#[derive(Drop, starknet::Event)]
pub struct UsersInvited {
    pub group_id: u256,
    pub inviter: ContractAddress,
    pub invitees: Array<ContractAddress>,
}

#[derive(Drop, starknet::Event)]
pub struct UserJoinedGroup {
    pub group_id: u256,
    pub user: ContractAddress,
    pub member_index: u32,
    pub joined_at: u64,
}

#[derive(Drop, starknet::Event)]
pub struct ContributionMade {
    pub group_id: u256,
    pub user: ContractAddress,
    pub amount: u256,
    pub cycle_number: u64,
    pub timestamp: u64,
}

#[derive(Drop, starknet::Event)]
pub struct PayoutSent {
    pub group_id: u256,
    pub recipient: ContractAddress,
    pub amount: u256,
    pub cycle_number: u64,
    pub timestamp: u64,
}
