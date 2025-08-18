pub mod Errors {
    // User Management Errors
    pub const USER_ALREADY_REGISTERED: felt252 = 'User already registered';
    pub const NAME_CANNOT_BE_EMPTY: felt252 = 'Name cannot be empty';
    pub const ONLY_REGISTERED_CAN_CREATE: felt252 = 'Only registered can create';
    pub const ONLY_REGISTERED_CAN_JOIN: felt252 = 'Only registered can join';

    // Group Management Errors
    pub const GROUP_DOES_NOT_EXIST: felt252 = 'Group does not exist';
    pub const GROUP_IS_FULL: felt252 = 'Group is full';
    pub const USER_ALREADY_MEMBER: felt252 = 'User is already a member';
    pub const USER_NOT_INVITED: felt252 = 'User not invited to group';
    pub const EXCEEDED_MAX_INVITE_LIMIT: felt252 = 'Exceeded max invite limit';
    pub const LOCK_TYPE_SHOULD_BE_NONE: felt252 = 'Lock type should be None';
    pub const ONLY_CREATOR_CAN_ACTIVATE: felt252 = 'Only creator can activate';
    pub const GROUP_MUST_BE_CREATED_STATE: felt252 = 'Group must be Created state';
    pub const GROUP_MUST_BE_ACTIVE: felt252 = 'Group must be active';
    pub const GROUP_MUST_BE_ACTIVE_OR_CREATED: felt252 = 'Group must be Active/Created';
    pub const ONLY_CREATOR_CAN_DISTRIBUTE: felt252 = 'Only creator can distribute';
    pub const GROUP_CYCLE_MUST_BE_COMPLETED: felt252 = 'Group cycle must be complete';
    pub const GROUP_CYCLE_NOT_ENDED: felt252 = 'Group cycle not ended yet';

    // Financial Errors
    pub const AMOUNT_MUST_BE_GREATER_THAN_ZERO: felt252 = 'Amount must be greater than 0';
    pub const GROUP_ID_MUST_BE_GREATER_THAN_ZERO: felt252 = 'Group ID must be > 0';
    pub const INSUFFICIENT_TOKEN_BALANCE: felt252 = 'Insufficient token balance';
    pub const INSUFFICIENT_ALLOWANCE: felt252 = 'Insufficient allowance';
    pub const TOKEN_TRANSFER_FAILED: felt252 = 'Token transfer failed';
    pub const INSUFFICIENT_BAL_FOR_CONTRI: felt252 = 'Insufficient bal for contri';
    pub const CONTRIBUTION_TRANSFER_FAILED: felt252 = 'Contribution transfer fail';
    pub const PAYOUT_TRANSFER_FAILED: felt252 = 'Payout transfer failed';
    pub const INSUFFICIENT_POOL_BALANCE: felt252 = 'Insufficient pool balance';

    // Member & Access Errors
    pub const USER_NOT_MEMBER: felt252 = 'User not member of this group';
    pub const NO_LOCKED_FUNDS_TO_WITHDRAW: felt252 = 'No locked funds to withdraw';
    pub const FUNDS_ALREADY_WITHDRAWN: felt252 = 'Funds already withdrawn';
    pub const PENALTY_EXCEEDS_LOCKED_AMOUNT: felt252 = 'Penalty exceeds locked amt';

    // Payout & Distribution Errors
    pub const NO_CONTRIBUTIONS_TO_DISTRIBUTE: felt252 = 'No contributions to distrib';
    pub const NO_ELIGIBLE_RECIPIENT_FOUND: felt252 = 'No eligible recipient found';
    pub const NO_ELIGIBLE_MEMBER_FOUND: felt252 = 'No eligible member found';
}
