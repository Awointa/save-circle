use starknet::ContractAddress;


#[derive(Drop, Serde, starknet::Store)]
pub struct UserProfile {
    pub user_address: ContractAddress,
    pub name: felt252,
    pub avatar: felt252,
    pub is_registered: bool,
    pub total_lock_amount: u256,
    pub profile_created_at: u64,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct joined_group {
    group_id: u64,
    user_address: ContractAddress,
    joined_at: u64,
    contribution_amount: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct Group {
    group_id: u64,
    creator: ContractAddress,
    member_limit: u8,
    contribution_amount: u256,
    total_members: u8,
    cycle_duration_days: u32,
    is_active: bool,
    created_at: u64,
}
