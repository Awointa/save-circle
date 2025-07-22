#[derive(Drop, starknet::Event)]
struct UserRegistered {
    user: ContractAddress,
    name: felt252,
}
