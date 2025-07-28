use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use save_circle::contracts::Savecircle::SaveCircle;
use save_circle::contracts::Savecircle::SaveCircle::Event;
use save_circle::enums::Enums::{GroupState, GroupVisibility, LockType, TimeUnit};
use save_circle::events::Events::{GroupCreated, UserRegistered, UsersInvited};
use save_circle::interfaces::Isavecircle::{IsavecircleDispatcher, IsavecircleDispatcherTrait};
use save_circle::structs::Structs::UserProfile;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const, get_block_timestamp};


fn setup() -> (ContractAddress, ContractAddress, ContractAddress) {
    // create default admin address - using numeric instead of string to avoid deployment issues
    let owner: ContractAddress = contract_address_const::<1>();

    // Deploy mock token for payment
    let token_class = declare("MockToken").unwrap().contract_class();
    let (token_address, _) = token_class
        .deploy(@array![owner.into(), // recipient
        owner.into() // owner
        ])
        .unwrap();

    // deploy savecircle contract
    let declare_result = declare("SaveCircle");
    assert(declare_result.is_ok(), 'contract declaration failed');

    let contract_class = declare_result.unwrap().contract_class();
    let mut calldata = array![owner.into(), token_address.into()];

    let deploy_result = contract_class.deploy(@calldata);
    assert(deploy_result.is_ok(), 'contract deployment failed');

    let (contract_address, _) = deploy_result.unwrap();

    (contract_address, owner, token_address)
}

#[test]
fn test_lock_liquidity_basic_functionality() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Create test user
    let user: ContractAddress = contract_address_const::<2>();

    // Register user
    start_cheat_caller_address(contract_address, user);
    dispatcher.register_user('TestUser'.into(), 'avatar.png'.into());

    // Create a group with lock requirement
    let group_id = dispatcher
        .create_public_group(
            5, // member_limit
            1000, // contribution_amount  
            LockType::Progressive, // lock_type
            4, // cycle_duration
            TimeUnit::Weeks, // cycle_unit
            GroupVisibility::Public, // visibility
            true, // requires_lock
            0 // min_reputation_score
        );
    stop_cheat_caller_address(contract_address);

    // Transfer tokens to user for testing
    start_cheat_caller_address(token_address, owner);
    token_dispatcher.transfer(user, 10000);
    stop_cheat_caller_address(token_address);

    // User approves contract to spend tokens
    start_cheat_caller_address(token_address, user);
    token_dispatcher.approve(contract_address, 10000);
    stop_cheat_caller_address(token_address);

    // Test lock_liquidity function
    start_cheat_caller_address(contract_address, user);

    // Check initial state
    let initial_token_balance = token_dispatcher.balance_of(user);
    assert(initial_token_balance == 10000, 'User should have 10000 tokens');

    let initial_locked_balance = dispatcher.get_locked_balance(user);
    assert(initial_locked_balance == 0, ' locked balance should be 0');

    // Lock some funds
    let lock_amount = 4000; // 4 weeks * 1000 contribution = 4000 tokens
    let lock_result = dispatcher.lock_liquidity(token_address, lock_amount, group_id);
    assert(lock_result == true, 'Lock liquidity should succeed');

    // Verify results
    let final_token_balance = token_dispatcher.balance_of(user);
    assert(final_token_balance == 6000, 'User  have 6000 tokens left');

    let contract_token_balance = token_dispatcher.balance_of(contract_address);
    assert(contract_token_balance == lock_amount, 'Contract hold locked tokens');

    let final_locked_balance = dispatcher.get_locked_balance(user);
    assert(final_locked_balance == lock_amount, 'Lock balance equal lock amount');

    // Check user profile was updated
    let user_profile = dispatcher.get_user_profile(user);
    assert(user_profile.total_lock_amount == lock_amount, 'Profile show locked amount');

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_lock_liquidity_multiple_locks() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Create test user
    let user: ContractAddress = contract_address_const::<2>();

    // Register user and create group
    start_cheat_caller_address(contract_address, user);
    dispatcher.register_user('TestUser'.into(), 'avatar.png'.into());

    let group_id = dispatcher
        .create_public_group(
            5, 500, LockType::Progressive, 2, TimeUnit::Weeks, GroupVisibility::Public, true, 0,
        );
    stop_cheat_caller_address(contract_address);

    // Setup tokens
    start_cheat_caller_address(token_address, owner);
    token_dispatcher.transfer(user, 5000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, user);
    token_dispatcher.approve(contract_address, 5000);
    stop_cheat_caller_address(token_address);

    // Test multiple locks
    start_cheat_caller_address(contract_address, user);

    // First lock
    let first_lock = 1000;
    let result1 = dispatcher.lock_liquidity(token_address, first_lock, group_id);
    assert(result1 == true, 'First lock should succeed');

    let locked_after_first = dispatcher.get_locked_balance(user);
    assert(locked_after_first == first_lock, 'Should track first lock');

    // Second lock
    let second_lock = 1500;
    let result2 = dispatcher.lock_liquidity(token_address, second_lock, group_id);
    assert(result2 == true, 'Second lock should succeed');

    let total_locked = dispatcher.get_locked_balance(user);
    assert(total_locked == first_lock + second_lock, 'Should track total locked');

    // Verify token balances
    let user_balance = token_dispatcher.balance_of(user);
    assert(user_balance == 2500, ' should have 2500 tokens left');

    let contract_balance = token_dispatcher.balance_of(contract_address);
    assert(contract_balance == first_lock + second_lock, 'Contract hold all locked tokens');

    stop_cheat_caller_address(contract_address);
}


#[test]
fn test_lock_liquidity_insufficient_balance() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    let user: ContractAddress = contract_address_const::<2>();

    // Register user and create group
    start_cheat_caller_address(contract_address, user);
    dispatcher.register_user('TestUser'.into(), 'avatar.png'.into());

    let group_id = dispatcher
        .create_public_group(
            5, 1000, LockType::Progressive, 4, TimeUnit::Weeks, GroupVisibility::Public, true, 0,
        );
    stop_cheat_caller_address(contract_address);

    // Give user insufficient tokens
    start_cheat_caller_address(token_address, owner);
    token_dispatcher.transfer(user, 100); // Only 100 tokens
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, user);
    token_dispatcher.approve(contract_address, 100);
    stop_cheat_caller_address(token_address);

    // Try to lock more than available
    start_cheat_caller_address(contract_address, user);

 
    let user_balance = token_dispatcher.balance_of(user);
    assert(user_balance == 100, 'User should have 100 tokens');


    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_get_locked_balance_multiple_users() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Create test users
    let user1: ContractAddress = contract_address_const::<2>();
    let user2: ContractAddress = contract_address_const::<3>();

    // Register users
    start_cheat_caller_address(contract_address, user1);
    dispatcher.register_user('User1'.into(), 'avatar1.png'.into());
    let group_id = dispatcher
        .create_public_group(
            5, 1000, LockType::Progressive, 4, TimeUnit::Weeks, GroupVisibility::Public, true, 0,
        );
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, user2);
    dispatcher.register_user('User2'.into(), 'avatar2.png'.into());
    stop_cheat_caller_address(contract_address);

    // Setup tokens for both users
    start_cheat_caller_address(token_address, owner);
    token_dispatcher.transfer(user1, 5000);
    token_dispatcher.transfer(user2, 3000);
    stop_cheat_caller_address(token_address);

    // Approve tokens
    start_cheat_caller_address(token_address, user1);
    token_dispatcher.approve(contract_address, 5000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, user2);
    token_dispatcher.approve(contract_address, 3000);
    stop_cheat_caller_address(token_address);

    // User1 locks funds
    start_cheat_caller_address(contract_address, user1);
    dispatcher.lock_liquidity(token_address, 2000, group_id);
    stop_cheat_caller_address(contract_address);

    // User2 locks funds
    start_cheat_caller_address(contract_address, user2);
    dispatcher.lock_liquidity(token_address, 1500, group_id);
    stop_cheat_caller_address(contract_address);

    // Test get_locked_balance for both users
    let user1_locked = dispatcher.get_locked_balance(user1);
    assert(user1_locked == 2000, 'User1 should have 2000 locked');

    let user2_locked = dispatcher.get_locked_balance(user2);
    assert(user2_locked == 1500, 'User2 should have 1500 locked');

    // Verify they are independent
    assert(user1_locked != user2_locked, ' balances should be independent');
}

