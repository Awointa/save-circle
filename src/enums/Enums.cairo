#[allow(starknet::store_no_default_variant)]
#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
pub enum LockType {
    Progressive,
    None,
}

#[allow(starknet::store_no_default_variant)]
#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
pub enum TimeUnit {
    Minutes,
    Hours,
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

#[allow(starknet::store_no_default_variant)]
#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
pub enum ActivityType {
    Contribution,
    PayoutReceived,
    GroupJoined,
    GroupCreated,
    GroupCompleted,
    GroupLeft,
    LockDeposited,
    LockWithdrawn,
    PenaltyPaid,
    ReputationGained,
    ReputationLost,
    UserRegistered,
}

#[allow(starknet::store_no_default_variant)]
#[derive(Drop, Copy, Serde, starknet::Store)]
pub enum GroupMemberStatus {
    Active,
    Completed,
    Left,
    Kicked,
    Pending,
}

