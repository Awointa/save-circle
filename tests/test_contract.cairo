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
    // create default admin address
    let owner: ContractAddress = contract_address_const::<'1'>();

    // Deploy mock token for payment
    let token_class = declare("MockToken").unwrap().contract_class();
    let (token_address, _) = token_class
        .deploy(@array![owner.into(), // recipient
        owner.into() // owner
        ])
        .unwrap();

    // deploy store contract
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
fn test_register_user_success() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>(); // arbitrary test address
    start_cheat_caller_address(contract_address, user);

    let name: felt252 = 'bob_the_builder';
    let avatar: felt252 = 'https://example.com/avatar.png';

    let result = dispatcher.register_user(name, avatar);

    assert(result == true, 'register_ should return true');

    // Check that the user profile is stored correctly
    let profile: UserProfile = dispatcher.get_user_profile(user);

    assert(profile.user_address == user, 'user_address mismatch');
    assert(profile.name == name, 'name mismatch');
    assert(profile.avatar == avatar, 'avatar mismatch');
    assert(profile.is_registered == true, 'is_registered should be true');
    assert(profile.total_lock_amount == 0, 'total_lock_amount should be 0');

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_register_user_event() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let mut spy = spy_events();

    let user: ContractAddress = contract_address_const::<'2'>(); // arbitrary test address
    start_cheat_caller_address(contract_address, user);

    let name: felt252 = 'bob_the_builder';
    let avatar: felt252 = 'https://example.com/avatar.png';

    dispatcher.register_user(name, avatar);

    spy
        .assert_emitted(
            @array![(contract_address, Event::UserRegistered(UserRegistered { user, name }))],
        );
}

#[test]
fn test_create_group_success() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>(); // arbitrary test address
    start_cheat_caller_address(contract_address, user);

    // register user
    let name: felt252 = 'bob_the_builder';
    let avatar: felt252 = 'https://example.com/avatar.png';

    dispatcher.register_user(name, avatar);

    // Check that the user profile is stored correctly
    let profile: UserProfile = dispatcher.get_user_profile(user);

    // create group
    let now = get_block_timestamp();
    dispatcher
        .create_group(
            1, 100, LockType::Progressive, 1, TimeUnit::Days, GroupVisibility::Public, false, 0,
        );

    let created_group = dispatcher.get_group_info(1);

    assert!(profile.is_registered == true, "Only registered user can create group");
    assert(created_group.group_id == 1, 'group_id mismatch');
    assert(created_group.creator == user, 'creator mismatch');
    assert(created_group.member_limit == 1, 'member_limit mismatch');
    assert(created_group.contribution_amount == 100, 'contribution_amount mismatch');
    assert(created_group.lock_type == LockType::Progressive, 'lock_type mismatch');
    assert(created_group.cycle_duration == 1, 'cycle_duration mismatch');
    assert(created_group.cycle_unit == TimeUnit::Days, 'cycle_unit mismatch');
    assert(created_group.members == 0, 'members mismatch');
    assert(created_group.state == GroupState::Created, 'state mismatch');
    assert(created_group.current_cycle == 0, 'current_cycle mismatch');
    assert(created_group.payout_order == 0, 'payout_order mismatch');
    assert(created_group.start_time == now, 'start_time mismatch');
    assert(created_group.total_cycles == 1, 'total_cycles mismatch');
    assert(created_group.visibility == GroupVisibility::Public, 'visibility mismatch');
    assert(created_group.requires_lock == false, 'requires_lock mismatch');
    assert!(created_group.requires_reputation_score == 0, "requires_reputation_score mismatch");
    assert(created_group.invited_members == 0, 'invited_members mismatch');

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_create_group_event() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let mut spy = spy_events();

    let user: ContractAddress = contract_address_const::<'2'>(); // arbitrary test address
    start_cheat_caller_address(contract_address, user);

    // register user
    let name: felt252 = 'bob_the_builder';
    let avatar: felt252 = 'https://example.com/avatar.png';

    dispatcher.register_user(name, avatar);

    // create group
    dispatcher
        .create_group(
            1, 100, LockType::Progressive, 1, TimeUnit::Days, GroupVisibility::Public, false, 0,
        );

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::GroupCreated(
                        GroupCreated {
                            group_id: 1,
                            creator: user,
                            member_limit: 1,
                            contribution_amount: 100,
                            cycle_duration: 1,
                            cycle_unit: TimeUnit::Days,
                            visibility: GroupVisibility::Public,
                            requires_lock: false,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_create_private_group_success() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>(); // arbitrary test address
    let user2: ContractAddress = contract_address_const::<'3'>(); // arbitrary test address
    start_cheat_caller_address(contract_address, user);

    // register user
    let name: felt252 = 'bob_the_builder';
    let avatar: felt252 = 'https://example.com/avatar.png';

    dispatcher.register_user(name, avatar);

    let invited_members = array![user2];

    let now = get_block_timestamp();
    // create group
    dispatcher.create_private_group(1, 200, 1, TimeUnit::Days, invited_members);

    let created_group = dispatcher.get_group_info(1);

    assert!(created_group.group_id == 1, "group_id mismatch");
    assert!(created_group.creator == user, "creator mismatch");
    assert!(created_group.member_limit == 1, "member_limit mismatch");
    assert!(created_group.contribution_amount == 200, "contribution_amount mismatch");
    assert!(created_group.lock_type == LockType::Upfront, "lock_type mismatch");
    assert!(created_group.cycle_duration == 1, "cycle_duration mismatch");
    assert!(created_group.cycle_unit == TimeUnit::Days, "cycle_unit mismatch");
    assert!(created_group.members == 0, "members mismatch");
    assert!(created_group.state == GroupState::Created, "state mismatch");
    assert!(created_group.current_cycle == 0, "current_cycle mismatch");
    assert!(created_group.payout_order == 0, "payout_order mismatch");
    assert!(created_group.start_time == now, "start_time mismatch");
    assert!(created_group.visibility == GroupVisibility::Private, "visibility mismatch");
    assert!(created_group.requires_lock == false, "requires_lock mismatch");
    assert!(created_group.requires_reputation_score == 0, "requires_reputation_score mismatch");
    assert!(created_group.invited_members == 1, "invited_members mismatch");
}

#[test]
fn test_users_invited_event() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>(); // arbitrary test address
    let user2: ContractAddress = contract_address_const::<'3'>(); // arbitrary test address
    start_cheat_caller_address(contract_address, user);

    let mut spy = spy_events();
    // register user
    let name: felt252 = 'bob_the_builder';
    let avatar: felt252 = 'https://example.com/avatar.png';

    dispatcher.register_user(name, avatar);

    let invited_members = array![user2];

    // create group
    dispatcher.create_private_group(1, 200, 1, TimeUnit::Days, invited_members.clone());

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::UsersInvited(
                        UsersInvited { group_id: 1, inviter: user, invitees: invited_members },
                    ),
                ),
            ],
        );
}

#[test]
fn test_create_private_group_event() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>(); // arbitrary test address
    let user2: ContractAddress = contract_address_const::<'3'>(); // arbitrary test address
    start_cheat_caller_address(contract_address, user);

    let mut spy = spy_events();

    // register user
    let name: felt252 = 'bob_the_builder';
    let avatar: felt252 = 'https://example.com/avatar.png';

    dispatcher.register_user(name, avatar);

    let invited_members = array![user2];

    // create group
    dispatcher.create_private_group(2, 1000, 4, TimeUnit::Weeks, invited_members.clone());

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::GroupCreated(
                        GroupCreated {
                            group_id: 1,
                            creator: user,
                            member_limit: 2,
                            contribution_amount: 1000,
                            cycle_duration: 4,
                            cycle_unit: TimeUnit::Weeks,
                            visibility: GroupVisibility::Private,
                            requires_lock: false,
                        },
                    ),
                ),
            ],
        );
}
