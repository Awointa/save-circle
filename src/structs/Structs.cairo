use starknet::ContractAddress;


#[derive(Drop, Serde, starknet::Store)]
pub struct UserProfile {
    pub user_address: ContractAddress,
    pub name: felt252,
    pub avatar: felt252,
    pub is_registered: bool,
    pub total_lock_amount: u256,
}
