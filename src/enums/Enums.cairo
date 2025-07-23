#[allow(starknet::store_no_default_variant)]
#[derive(Drop, Serde, starknet::Store)]
pub enum LockType {
    Progressive,
    Upfront,
    Hybrid,
}

#[allow(starknet::store_no_default_variant)]
#[derive(Drop, Serde, starknet::Store)]
pub enum TimeUnit {
    Hours,
    Days,
    Weeks,
    Months,
}

#[allow(starknet::store_no_default_variant)]
#[derive(Drop, Serde, starknet::Store)]
pub enum GroupState {
    Created,
    Active,
    Completed,
    Defaulted,
}

#[allow(starknet::store_no_default_variant)]
#[derive(Drop, Serde,  starknet::Store)]
pub enum GroupVisibility {
    Public,
    Private,
}
