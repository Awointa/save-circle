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
fn test_create_public_group() {
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
        .create_public_group(
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
fn test_create_public_group_event() {
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
        .create_public_group(
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
    dispatcher
        .create_private_group(1, 200, 1, TimeUnit::Days, invited_members, false, LockType::None, 0);

    let created_group = dispatcher.get_group_info(1);

    assert!(created_group.group_id == 1, "group_id mismatch");
    assert!(created_group.creator == user, "creator mismatch");
    assert!(created_group.member_limit == 1, "member_limit mismatch");
    assert!(created_group.contribution_amount == 200, "contribution_amount mismatch");
    assert!(created_group.lock_type == LockType::None, "lock_type mismatch");
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
fn test_create_private_group_with_lock() {
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

    let now = get_block_timestamp();
    // create group
    dispatcher
        .create_private_group(
            1, 200, 1, TimeUnit::Days, invited_members, true, LockType::Upfront, 0,
        );

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
    assert!(created_group.requires_lock == true, "requires_lock mismatch");
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
    dispatcher
        .create_private_group(
            1, 200, 1, TimeUnit::Days, invited_members.clone(), false, LockType::None, 0,
        );

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
    dispatcher
        .create_private_group(
            2, 1000, 4, TimeUnit::Weeks, invited_members.clone(), false, LockType::None, 0,
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


#[test]
fn test_join_group() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    // Create users
    let creator: ContractAddress = contract_address_const::<'1'>();
    let joiner: ContractAddress = contract_address_const::<'2'>();

    // Register creator
    start_cheat_caller_address(contract_address, creator);
    dispatcher.register_user('Creator', 'https://example.com/creator.png');
    stop_cheat_caller_address(contract_address);

    // Register joiner
    start_cheat_caller_address(contract_address, joiner);
    dispatcher.register_user('Joiner', 'https://example.com/joiner.png');
    stop_cheat_caller_address(contract_address);

    // create group
    start_cheat_caller_address(contract_address, creator);
    let now = get_block_timestamp();
    dispatcher
        .create_public_group(
            1, 100, LockType::Progressive, 1, TimeUnit::Days, GroupVisibility::Public, false, 0,
        );

    let created_group = dispatcher.get_group_info(1);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, joiner);
    // join group

    let member_index = dispatcher.join_group(1);

    stop_cheat_caller_address(contract_address);

    // Check that the user is a member of the group

    assert(member_index == 0, 'member_index should be 1');

    //verify group member
    let group_member = dispatcher.get_group_member(1, member_index);
    assert(group_member.user == joiner, 'user mismatch');
    assert(group_member.group_id == 1, 'group_id mismatch');
    assert(group_member.member_index == 0, 'member_index mismatch');
    assert(group_member.locked_amount == 0, 'locked_amount should be 0');
    assert(group_member.has_been_paid == false, 'has_been_paid should be false');
    assert(group_member.contribution_count == 0, 'contribution_count should be 0');
    assert(group_member.late_contributions == 0, 'late_contributions should be 0');
    assert(group_member.missed_contributions == 0, 'missed_contr should be 0');

    // Verify user's member index
    let user_member_index = dispatcher.get_user_member_index(joiner, 1);
    assert(user_member_index == 0, 'user_member_index should be 0');

    // Verify membership status
    let is_member = dispatcher.is_group_member(1, joiner);
    assert(is_member == true, 'should be a member');

    // Verify group member count increased
    let updated_group = dispatcher.get_group_info(1);
    assert(updated_group.members == 1, 'group members should be 1');
}


#[test]
fn test_group_member_with_multiple_members() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    // Create users
    let creator: ContractAddress = contract_address_const::<'1'>();
    let joiner1: ContractAddress = contract_address_const::<'2'>();
    let joiner2: ContractAddress = contract_address_const::<'3'>();
    let joiner3: ContractAddress = contract_address_const::<'4'>();

    // Register users
    start_cheat_caller_address(contract_address, creator);
    dispatcher.register_user('creator', 'https://example.com/creator.png');
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, joiner1);
    dispatcher.register_user('joiner1', 'https://example.com/joiner1.png');
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, joiner2);
    dispatcher.register_user('joiner2', 'https://example.com/joiner2.png');
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, joiner3);
    dispatcher.register_user('joiner3', 'https://example.com/joiner3.png');
    stop_cheat_caller_address(contract_address);

    // Creator creates a public group
    start_cheat_caller_address(contract_address, creator);
    let group_id = dispatcher
        .create_public_group(
            10, 100, LockType::Progressive, 1, TimeUnit::Days, GroupVisibility::Public, false, 0,
        );

    stop_cheat_caller_address(contract_address);

    // First joiner joins
    start_cheat_caller_address(contract_address, joiner1);
    let member_index1 = dispatcher.join_group(group_id);
    stop_cheat_caller_address(contract_address);

    // Second joiner joins
    start_cheat_caller_address(contract_address, joiner2);
    let member_index2 = dispatcher.join_group(group_id);
    stop_cheat_caller_address(contract_address);

    // Third joiner joins
    start_cheat_caller_address(contract_address, joiner3);
    let member_index3 = dispatcher.join_group(group_id);
    stop_cheat_caller_address(contract_address);

    // Verify sequential member indices
    assert(member_index1 == 0, 'first memb should have index 0');
    assert(member_index2 == 1, 'second memb should have index 1');
    assert(member_index3 == 2, 'third memb should have index 2');

    // Verify all members can be retrieved
    let member1 = dispatcher.get_group_member(group_id, 0);
    let member2 = dispatcher.get_group_member(group_id, 1);
    let member3 = dispatcher.get_group_member(group_id, 2);

    assert(member1.user == joiner1, 'member1 user mismatch');
    assert(member2.user == joiner2, 'member2 user mismatch');
    assert(member3.user == joiner3, 'member3 user mismatch');

    // Verify group member count
    let updated_group = dispatcher.get_group_info(group_id);
    assert(updated_group.members == 3, 'group members should be 3');
}


#[test]
fn test_user_joins_multiple_groups() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    // Create users
    let creator1: ContractAddress = contract_address_const::<'1'>();
    let creator2: ContractAddress = contract_address_const::<'2'>();
    let joiner: ContractAddress = contract_address_const::<'3'>();

    // Register users
    start_cheat_caller_address(contract_address, creator1);
    dispatcher.register_user('Creator1', 'https://example.com/creor1.png');
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, creator2);
    dispatcher.register_user('Creator2', 'https://example.com/creor2.png');
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, joiner);
    dispatcher.register_user('Joiner', 'https://example.com/joiner.png');
    stop_cheat_caller_address(contract_address);

    // Creator1 creates first group
    start_cheat_caller_address(contract_address, creator1);
    let group1_id = dispatcher
        .create_public_group(
            5, 100, LockType::Progressive, 1, TimeUnit::Days, GroupVisibility::Public, false, 0,
        );
    stop_cheat_caller_address(contract_address);

    // Creator2 creates second group
    start_cheat_caller_address(contract_address, creator2);
    let group2_id = dispatcher
        .create_public_group(
            5, 200, LockType::Progressive, 1, TimeUnit::Weeks, GroupVisibility::Public, false, 0,
        );
    stop_cheat_caller_address(contract_address);

    // Joiner joins first group
    start_cheat_caller_address(contract_address, joiner);
    let group1_member_index = dispatcher.join_group(group1_id);
    stop_cheat_caller_address(contract_address);

    // Verify first group membership
    assert(dispatcher.is_group_member(group1_id, joiner), 'should be member of group1');
    assert(group1_member_index == 0, 'should be member of group1');

    let group1_member = dispatcher.get_group_member(group1_id, group1_member_index);
    assert(group1_member.user == joiner, 'user mismatch in group1');
    assert(group1_member.group_id == group1_id, 'group1_id mismatch');

    // Joiner joins second group
    start_cheat_caller_address(contract_address, joiner);
    let group2_member_index = dispatcher.join_group(group2_id);
    stop_cheat_caller_address(contract_address);

    // Verify second group membership
    assert(dispatcher.is_group_member(group2_id, joiner), 'should be member of group2');
    assert(group2_member_index == 0, 'should be  member of group2');

    let group2_member = dispatcher.get_group_member(group2_id, group2_member_index);
    assert(group2_member.user == joiner, 'user mismatch in group2');
    assert(group2_member.group_id == group2_id, 'group2_id mismatch');

    // Verify user's member index in each group
    let user_group1_index = dispatcher.get_user_member_index(joiner, group1_id);
    let user_group2_index = dispatcher.get_user_member_index(joiner, group2_id);

    assert(user_group1_index == group1_member_index, 'group1 member index mismatch');
    assert(user_group2_index == group2_member_index, 'group2 member index mismatch');

    // Verify both groups show the user as a member
    assert(dispatcher.is_group_member(group1_id, joiner), 'should be member of group1');
    assert(dispatcher.is_group_member(group2_id, joiner), 'should be member of group2');

    // Verify group member counts
    let group1_info = dispatcher.get_group_info(group1_id);
    let group2_info = dispatcher.get_group_info(group2_id);

    assert(group1_info.members == 1, 'group1 should have 1 member');
    assert(group2_info.members == 1, 'group2 should have 1 member');
}

