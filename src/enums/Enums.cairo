#[allow(starknet::store_no_default_variant)]
#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
pub enum LockType {
    Progressive,
    None,
}

#[allow(starknet::store_no_default_variant)]
#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
pub enum TimeUnit {
    Days,
    Weeks,
    Months,
}

#[allow(starknet::store_no_default_variant)]
#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
pub enum GroupState {
    Created,
    Active,
    Completed,
    Defaulted,
}

#[allow(starknet::store_no_default_variant)]
#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
pub enum GroupVisibility {
    Public,
    Private,
}
