use starknet::ContractAddress;

#[derive(Drop, starknet::Event)]
pub struct UserRegistered {
    pub user: ContractAddress,
    pub name: felt252,
}
