use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use save_circle::contracts::Savecircle::SaveCircle::Event;
use save_circle::enums::Enums::{GroupState, GroupVisibility, LockType, TimeUnit};
use save_circle::events::Events::{GroupCreated, UserRegistered, UsersInvited, UserJoinedGroup};
use save_circle::interfaces::Isavecircle::{IsavecircleDispatcher, IsavecircleDispatcherTrait};
use save_circle::structs::Structs::{ProfileViewData};
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

    // Check that the user profile is stored correctly using the new method
    let profile_data: ProfileViewData = dispatcher.get_user_profile_view_data(user);
    let profile = profile_data.profile;

    assert(profile.user_address == user, 'user_address mismatch');
    assert(profile.name == name, 'name mismatch');
    assert(profile.avatar == avatar, 'avatar mismatch');
    assert(profile.is_registered == true, 'is_registered should be true');
    assert(profile.total_lock_amount == 0, 'total_lock_amount should be 0');
    assert(profile.reputation_score == 0, 'reputation should be 0');
    assert(profile.total_joined_groups == 0, 'joined groups should be 0');
    assert(profile.total_created_groups == 0, 'created groups should be 0');

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
    let profile_data: ProfileViewData = dispatcher.get_user_profile_view_data(user);
    let profile = profile_data.profile;

    // create group - using the corrected parameter order from your contract
    let now = get_block_timestamp();
    let group_id = dispatcher
        .create_public_group(
            "Test Group",      // name: ByteArray
            "A test group",    // description: ByteArray
            3,                 // member_limit: u32
            100,               // contribution_amount: u256
            LockType::Progressive, // lock_type: LockType
            1,                 // cycle_duration: u64
            TimeUnit::Days,    // cycle_unit: TimeUnit
            false,             // requires_lock: bool
            0,                 // min_reputation_score: u32
        );

    let created_group = dispatcher.get_group_info(group_id);

    assert!(profile.is_registered == true, "Only registered user can create group");
    assert(created_group.group_id == 1, 'group_id mismatch');
    assert(created_group.creator == user, 'creator mismatch');
    assert(created_group.member_limit == 3, 'member_limit mismatch');
    assert(created_group.contribution_amount == 100, 'contribution_amount mismatch');
    assert(created_group.lock_type == LockType::Progressive, 'lock_type mismatch');
    assert(created_group.cycle_duration == 1, 'cycle_duration mismatch');
    assert(created_group.cycle_unit == TimeUnit::Days, 'cycle_unit mismatch');
    assert(created_group.members == 0, 'members mismatch');
    assert(created_group.state == GroupState::Created, 'state mismatch');
    assert(created_group.current_cycle == 0, 'current_cycle mismatch');
    assert(created_group.payout_order == 0, 'payout_order mismatch');
    assert(created_group.start_time == now, 'start_time mismatch');
    assert(created_group.total_cycles == 3, 'total_cycles mismatch');
    assert(created_group.visibility == GroupVisibility::Public, 'visibility mismatch');
    assert(created_group.requires_lock == false, 'requires_lock mismatch');
    assert!(created_group.requires_reputation_score == 0, "requires_reputation_score mismatch");

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
            "Test Group",
            "A test group",
            3,
            100,
            LockType::Progressive,
            1,
            TimeUnit::Days,
            false,
            0,
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
                            member_limit: 3,
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
    // create group - using correct parameter order
    let group_id = dispatcher
        .create_private_group(
            "Private Test Group",  // name: ByteArray
            "A private test group", // description: ByteArray
            2,                     // member_limit: u32
            200,                   // contribution_amount: u256
            1,                     // cycle_duration: u64
            TimeUnit::Days,        // cycle_unit: TimeUnit
            invited_members,       // invited_members: Array<ContractAddress>
            false,                 // requires_lock: bool
            LockType::None,        // lock_type: LockType
            0,                     // min_reputation_score: u32
        );

    let created_group = dispatcher.get_group_info(group_id);

    assert!(created_group.group_id == 1, "group_id mismatch");
    assert!(created_group.creator == user, "creator mismatch");
    assert!(created_group.member_limit == 2, "member_limit mismatch");
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
    let group_id = dispatcher
        .create_private_group(
            "Private Lock Group",
            "A private group with locking",
            2,
            200,
            1,
            TimeUnit::Days,
            invited_members,
            true,
            LockType::Upfront,
            0,
        );

    let created_group = dispatcher.get_group_info(group_id);

    assert!(created_group.group_id == 1, "group_id mismatch");
    assert!(created_group.creator == user, "creator mismatch");
    assert!(created_group.member_limit == 2, "member_limit mismatch");
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
            "Private Event Test",
            "Testing private group events",
            2,
            200,
            1,
            TimeUnit::Days,
            invited_members.clone(),
            false,
            LockType::None,
            0,
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
            "Private Group Event",
            "Testing group creation event",
            2,
            1000,
            4,
            TimeUnit::Weeks,
            invited_members.clone(),
            false,
            LockType::None,
            0,
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
    let group_id = dispatcher
        .create_public_group(
            "Join Test Group",
            "A group for testing joins",
            3,
            100,
            LockType::Progressive,
            1,
            TimeUnit::Days,
            false,
            0,
        );

    let created_group = dispatcher.get_group_info(group_id);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, joiner);
    // join group

    let member_index = dispatcher.join_group(group_id);

    stop_cheat_caller_address(contract_address);

    // Check that the user is a member of the group

    assert(member_index == 0, 'member_index should be 0');

    //verify group member
    let group_member = dispatcher.get_group_member(group_id, member_index);
    assert(group_member.user == joiner, 'user mismatch');
    assert(group_member.group_id == group_id, 'group_id mismatch');
    assert(group_member.member_index == 0, 'member_index mismatch');
    assert(group_member.locked_amount == 0, 'locked_amount should be 0');
    assert(group_member.has_been_paid == false, 'has_been_paid should be false');
    assert(group_member.contribution_count == 0, 'contribution_count should be 0');
    assert(group_member.late_contributions == 0, 'late_contributions should be 0');
    assert(group_member.missed_contributions == 0, 'missed_contr should be 0');
    assert(group_member.is_active == true, 'should be active');

    // Verify user's member index
    let user_member_index = dispatcher.get_user_member_index(joiner, group_id);
    assert(user_member_index == 0, 'user_member_index should be 0');

    // Verify membership status
    let is_member = dispatcher.is_group_member(group_id, joiner);
    assert(is_member == true, 'should be a member');

    // Verify group member count increased
    let updated_group = dispatcher.get_group_info(group_id);
    assert(updated_group.members == 1, 'group members should be 1');
}


#[test]
fn test_join_group_event() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let mut spy = spy_events();

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
    let group_id = dispatcher
        .create_public_group(
            "Event Test Group",
            "Testing join events",
            3,
            100,
            LockType::Progressive,
            1,
            TimeUnit::Days,
            false,
            0,
        );
    stop_cheat_caller_address(contract_address);

    // Clear previous events
    spy = spy_events();

    start_cheat_caller_address(contract_address, joiner);
    let current_time = get_block_timestamp();
    let member_index = dispatcher.join_group(group_id);
    stop_cheat_caller_address(contract_address);

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::UserJoinedGroup(
                        UserJoinedGroup {
                            group_id,
                            user: joiner,
                            member_index,
                            joined_at: current_time,
                        },
                    ),
                ),
            ],
        );
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
            "Multi Member Group",
            "A group for multiple members",
            10,
            100,
            LockType::Progressive,
            1,
            TimeUnit::Days,
            false,
            0,
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
            "First Group",
            "The first group",
            5,
            100,
            LockType::Progressive,
            1,
            TimeUnit::Days,
            false,
            0,
        );
    stop_cheat_caller_address(contract_address);

    // Creator2 creates second group
    start_cheat_caller_address(contract_address, creator2);
    let group2_id = dispatcher
        .create_public_group(
            "Second Group",
            "The second group",
            5,
            200,
            LockType::Progressive,
            1,
            TimeUnit::Weeks,
            false,
            0,
        );
    stop_cheat_caller_address(contract_address);

    // Joiner joins first group
    start_cheat_caller_address(contract_address, joiner);
    let group1_member_index = dispatcher.join_group(group1_id);
    stop_cheat_caller_address(contract_address);

    // Verify first group membership
    assert(dispatcher.is_group_member(group1_id, joiner), 'should be member of group1');
    assert(group1_member_index == 0, 'should be member 0 of group1');

    let group1_member = dispatcher.get_group_member(group1_id, group1_member_index);
    assert(group1_member.user == joiner, 'user mismatch in group1');
    assert(group1_member.group_id == group1_id, 'group1_id mismatch');

    // Joiner joins second group
    start_cheat_caller_address(contract_address, joiner);
    let group2_member_index = dispatcher.join_group(group2_id);
    stop_cheat_caller_address(contract_address);

    // Verify second group membership
    assert(dispatcher.is_group_member(group2_id, joiner), 'should be member of group2');
    assert(group2_member_index == 0, 'should be member 0 of group2');

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

#[test]
fn test_get_user_joined_groups() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>();
    let creator: ContractAddress = contract_address_const::<'3'>();

    // Register users
    start_cheat_caller_address(contract_address, user);
    dispatcher.register_user('TestUser', 'https://example.com/user.png');
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, creator);
    dispatcher.register_user('Creator', 'https://example.com/creator.png');
    stop_cheat_caller_address(contract_address);

    // Creator creates multiple groups
    start_cheat_caller_address(contract_address, creator);
    let group1_id = dispatcher
        .create_public_group(
            "Group 1",
            "First test group",
            5,
            100,
            LockType::Progressive,
            1,
            TimeUnit::Days,
            false,
            0,
        );

    let group2_id = dispatcher
        .create_public_group(
            "Group 2",
            "Second test group",
            3,
            200,
            LockType::None,
            2,
            TimeUnit::Weeks,
            false,
            0,
        );
    stop_cheat_caller_address(contract_address);

    // User joins both groups
    start_cheat_caller_address(contract_address, user);
    dispatcher.join_group(group1_id);
    dispatcher.join_group(group2_id);
    stop_cheat_caller_address(contract_address);

    // Test get_user_joined_groups
    let joined_groups = dispatcher.get_user_joined_groups(user);
    assert(joined_groups.len() == 2, 'should have 2 joined groups');

    // Verify the groups are correct
    let group_details_1 = joined_groups[0];
    let group_details_2 = joined_groups[1];

    assert(*group_details_1.group_info.group_id == group1_id, 'first group id mismatch');
    assert(*group_details_2.group_info.group_id == group2_id, 'second group id mismatch');
    
    assert(*group_details_1.member_data.user == user, 'first group member mismatch');
    assert(*group_details_2.member_data.user == user, 'second group member mismatch');
}

#[test]
fn test_get_user_activities() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>();

    // Register user (this creates an activity)
    start_cheat_caller_address(contract_address, user);
    dispatcher.register_user('TestUser', 'https://example.com/user.png');

    // Create a group (this creates another activity)
    dispatcher
        .create_public_group(
            "Activity Test Group",
            "Testing user activities",
            5,
            100,
            LockType::Progressive,
            1,
            TimeUnit::Days,
            false,
            0,
        );
    stop_cheat_caller_address(contract_address);

    // Test get_user_activities
    let activities = dispatcher.get_user_activities(user, 10);
    assert(activities.len() == 2, 'should have 2 activities');

    // Verify activities
    let first_activity = activities[0]; // Registration activity
    let second_activity = activities[1]; // Group creation activity

    assert!(*first_activity.user_address == user, "first activity user mismatch");
    assert!(*second_activity.user_address == user, "second activity user mismatch");
}

#[test]
fn test_get_user_statistics() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>();

    // Register user
    start_cheat_caller_address(contract_address, user);
    dispatcher.register_user('TestUser', 'https://example.com/user.png');
    stop_cheat_caller_address(contract_address);

    // Get user statistics
    let statistics = dispatcher.get_user_statistics(user);

    assert(statistics.user_address == user, 'statistics user mismatch');
    assert(statistics.total_saved == 0, 'initial saved should be 0');
    assert(statistics.total_earned == 0, 'initial earned should be 0');
    assert!(statistics.success_rate == 100, "initial success rate should be 100");
    assert(statistics.groups_completed_successfully == 0, 'completed groups should be 0');
    assert(statistics.groups_left_early == 0, 'left early should be 0');
    assert(statistics.current_active_streak == 0, 'active streak should be 0');
}

#[test]
fn test_get_user_profile_view_data() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>();
    let creator: ContractAddress = contract_address_const::<'3'>();

    // Register users
    start_cheat_caller_address(contract_address, user);
    dispatcher.register_user('TestUser', 'https://example.com/user.png');
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, creator);
    dispatcher.register_user('Creator', 'https://example.com/creator.png');

    // Create a group
    let group_id = dispatcher
        .create_public_group(
            "Profile Test Group",
            "Testing profile view data",
            5,
            100,
            LockType::Progressive,
            1,
            TimeUnit::Days,
            false,
            0,
        );
    stop_cheat_caller_address(contract_address);

    // User joins the group
    start_cheat_caller_address(contract_address, user);
    dispatcher.join_group(group_id);
    stop_cheat_caller_address(contract_address);

    // Get comprehensive profile data
    let profile_data = dispatcher.get_user_profile_view_data(user);

    // Verify profile
    assert(profile_data.profile.user_address == user, 'profile user mismatch');
    assert(profile_data.profile.name == 'TestUser', 'profile name mismatch');
    assert(profile_data.profile.is_registered == true, 'should be registered');
    assert(profile_data.profile.reputation_score == 0, 'reputation should be 0');

    // Verify joined groups
    assert(profile_data.joined_groups.len() == 1, 'should have 1 joined group');
    let joined_group = profile_data.joined_groups[0];
    assert(*joined_group.group_id == group_id, 'joined group id mismatch');

    // Verify recent activities (registration + join group)
    assert(profile_data.recent_activities.len() == 2, 'should have 2 activities');

    // Verify statistics
    assert(profile_data.statistics.user_address == user, 'statistics user mismatch');
    assert(profile_data.statistics.success_rate == 100, 'success rate should be 100');
}

#[test]
#[should_panic(expected: "User already registered")]
fn test_register_user_already_registered() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>();
    start_cheat_caller_address(contract_address, user);

    // Register user first time
    dispatcher.register_user('TestUser', 'https://example.com/user.png');

    // Try to register again - should panic
    dispatcher.register_user('TestUser2', 'https://example.com/user2.png');
}

#[test]
#[should_panic(expected: "Name cannot be empty")]
fn test_register_user_empty_name() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>();
    start_cheat_caller_address(contract_address, user);

    // Try to register with empty name - should panic
    dispatcher.register_user(0, 'https://example.com/user.png');
}

#[test]
#[should_panic(expected: "Only registered users can create groups")]
fn test_create_group_unregistered_user() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>();
    start_cheat_caller_address(contract_address, user);

    // Try to create group without registering - should panic
    dispatcher
        .create_public_group(
            "Test Group",
            "Should fail",
            3,
            100,
            LockType::Progressive,
            1,
            TimeUnit::Days,
            false,
            0,
        );
}

#[test]
#[should_panic(expected: "Only registered users can join groups")]
fn test_join_group_unregistered_user() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let creator: ContractAddress = contract_address_const::<'1'>();
    let unregistered_user: ContractAddress = contract_address_const::<'2'>();

    // Register creator and create group
    start_cheat_caller_address(contract_address, creator);
    dispatcher.register_user('Creator', 'https://example.com/creator.png');
    let group_id = dispatcher
        .create_public_group(
            "Test Group",
            "A test group",
            3,
            100,
            LockType::Progressive,
            1,
            TimeUnit::Days,
            false,
            0,
        );
    stop_cheat_caller_address(contract_address);

    // Try to join with unregistered user - should panic
    start_cheat_caller_address(contract_address, unregistered_user);
    dispatcher.join_group(group_id);
}

#[test]
#[should_panic(expected: "Group does not exist")]
fn test_join_nonexistent_group() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<'2'>();

    // Register user
    start_cheat_caller_address(contract_address, user);
    dispatcher.register_user('TestUser', 'https://example.com/user.png');

    // Try to join non-existent group - should panic
    dispatcher.join_group(999);
}

#[test]
#[should_panic(expected: "User is already a member")]
fn test_join_group_already_member() {
    let (contract_address, _, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let creator: ContractAddress = contract_address_const::<'1'>();
    let user: ContractAddress = contract_address_const::<'2'>();

    // Register users
    start_cheat_caller_address(contract_address, creator);
    dispatcher.register_user('Creator', 'https://example.com/creator.png');
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, user);
    dispatcher.register_user('TestUser', 'https://example.com/user.png');
    stop_cheat_caller_address(contract_address);

    // Creator creates group
    start_cheat_caller_address(contract_address, creator);
    let group_id = dispatcher
        .create_public_group(
            "Test Group",
            "A test group",
            3,
            100,
            LockType::Progressive,
            1,
            TimeUnit::Days,
            false,
            0,
        );
    stop_cheat_caller_address(contract_address);

    // User joins group
    start_cheat_caller_address(contract_address, user);
    dispatcher.join_group(group_id);

    // Try to join again - should panic
    dispatcher.join_group(group_id);
}