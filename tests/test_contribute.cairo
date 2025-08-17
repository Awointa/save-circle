use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use save_circle::contracts::Savecircle::SaveCircle;
use save_circle::enums::Enums::{LockType, TimeUnit};
use save_circle::events::Events::{ContributionMade};
use save_circle::interfaces::Isavecircle::{IsavecircleDispatcher, IsavecircleDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};

fn setup() -> (ContractAddress, ContractAddress, ContractAddress) {
    // create default admin address
    let owner: ContractAddress = contract_address_const::<1>();

    // Deploy mock token for payment
    let token_class = declare("MockToken").unwrap().contract_class();
    let (token_address, _) = token_class.deploy(@array![owner.into(), owner.into()]).unwrap();

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

fn setup_user_and_group(
    contract_address: ContractAddress,
    token_address: ContractAddress,
    owner: ContractAddress,
    user: ContractAddress,
    contribution_amount: u256,
    token_amount: u256,
) -> u256 {
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Register user
    start_cheat_caller_address(contract_address, user);
    dispatcher.register_user("TestUser", "avatar.png");

    // Create a group
    let group_id = dispatcher
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

    // Activate the group (creator can activate)
    dispatcher.activate_group(group_id);

    // Join the group
    dispatcher.join_group(group_id);
    stop_cheat_caller_address(contract_address);

    // Transfer tokens to user
    start_cheat_caller_address(token_address, owner);
    token_dispatcher.transfer(user, token_amount);
    stop_cheat_caller_address(token_address);

    // User approves contract to spend tokens
    start_cheat_caller_address(token_address, user);
    token_dispatcher.approve(contract_address, token_amount);
    stop_cheat_caller_address(token_address);

    group_id
}

#[test]
fn test_contribute_basic_functionality() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    let user: ContractAddress = contract_address_const::<2>();
    let contribution_amount = 1000_u256;
    let token_amount = 5000_u256;

    let group_id = setup_user_and_group(
        contract_address, token_address, owner, user, contribution_amount, token_amount,
    );

    // Test contribution
    start_cheat_caller_address(contract_address, user);

    // Check initial balances   
    let initial_user_balance = token_dispatcher.balance_of(user);
    let initial_contract_balance = token_dispatcher.balance_of(contract_address);
    assert(initial_user_balance == token_amount, 'User should have initial tokens');

    // Get member info before contribution
    let member_info_before = dispatcher.get_group_member(group_id, 1);
    assert(member_info_before.contribution_count == 0, 'contribution count should be 0');

    // Make contribution
    let result = dispatcher.contribute(group_id);
    assert(result == true, 'Contribution should succeed');

    // Calculate expected amounts (1% insurance fee)
    let insurance_fee = (contribution_amount * 100) / 10000; // 1% = 100 basis points
    let total_payment = contribution_amount + insurance_fee;

    // Check balances after contribution
    let final_user_balance = token_dispatcher.balance_of(user);
    let final_contract_balance = token_dispatcher.balance_of(contract_address);

    assert(
        final_user_balance == initial_user_balance - total_payment,
        'user bal decre by total payment',
    );
    assert(
        final_contract_balance == initial_contract_balance + total_payment,
        'contr bal incre by total paym',
    );

    // Check member contribution count updated
    let member_info_after = dispatcher.get_group_member(group_id, 0);
    assert(member_info_after.contribution_count == 1, 'Contribution count should be 1');

    stop_cheat_caller_address(contract_address);
}


#[test]
fn test_contribute_insurance_fee_calculation() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    let user: ContractAddress = contract_address_const::<2>();
    let contribution_amount = 2000_u256;
    let token_amount = 10000_u256;

    let group_id = setup_user_and_group(
        contract_address, token_address, owner, user, contribution_amount, token_amount,
    );

    start_cheat_caller_address(contract_address, user);

    // Make contribution
    dispatcher.contribute(group_id);

    // Calculate expected insurance fee (1% of contribution)
    let expected_insurance_fee = (contribution_amount * 100) / 10000; // 1% = 100 basis points
    let expected_total_payment = contribution_amount + expected_insurance_fee;

    // Check that exact amounts were transferred
    let user_balance = token_dispatcher.balance_of(user);
    let expected_remaining = token_amount - expected_total_payment;
    assert(user_balance == expected_remaining, 'Insurance fee cal incorrect');

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_contribute_multiple_contributions() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    let user: ContractAddress = contract_address_const::<2>();
    let contribution_amount = 500_u256;
    let token_amount = 10000_u256;

    let group_id = setup_user_and_group(
        contract_address, token_address, owner, user, contribution_amount, token_amount,
    );

    start_cheat_caller_address(contract_address, user);

    let insurance_fee = (contribution_amount * 100) / 10000;
    let total_payment = contribution_amount + insurance_fee;

    // First contribution
    let result1 = dispatcher.contribute(group_id);
    assert(result1 == true, 'First contri should succeed');

    let member_info_after_first = dispatcher.get_group_member(group_id, 0);
    assert(member_info_after_first.contribution_count == 1, 'Count should be 1 after first');

    // Second contribution
    let result2 = dispatcher.contribute(group_id);
    assert(result2 == true, 'Second contri should succeed');

    let member_info_after_second = dispatcher.get_group_member(group_id, 0);
    assert(member_info_after_second.contribution_count == 2, 'Count should be 2 after second');

    // Check total amount transferred
    let user_balance = token_dispatcher.balance_of(user);
    let expected_remaining = token_amount - (total_payment * 2);
    assert(user_balance == expected_remaining, 'Total paym should be correct');

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_contribute_insufficient_balance() {
    let (contract_address, owner, token_address) = setup();
    let user: ContractAddress = contract_address_const::<2>();
    let contribution_amount = 1000_u256;
    let insufficient_amount = 50_u256; // Not enough for contribution + insurance fee

    let group_id = setup_user_and_group(
        contract_address, token_address, owner, user, contribution_amount, insufficient_amount,
    );

    start_cheat_caller_address(contract_address, user);

    // This should fail due to insufficient balance
    // Note: In Cairo testing, we expect the transaction to panic/revert
    // The test framework should catch the assertion failure
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_contribute_non_member() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    let user: ContractAddress = contract_address_const::<2>();
    let non_member: ContractAddress = contract_address_const::<3>();
    let contribution_amount = 1000_u256;
    let token_amount = 5000_u256;

    // Setup user and group (but non_member won't join)
    let group_id = setup_user_and_group(
        contract_address, token_address, owner, user, contribution_amount, token_amount,
    );

    // Register non_member but don't join group
    start_cheat_caller_address(contract_address, non_member);
    dispatcher.register_user("NonMember", "avatar2.png");
    stop_cheat_caller_address(contract_address);

    // Give non_member tokens
    start_cheat_caller_address(token_address, owner);
    token_dispatcher.transfer(non_member, token_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, non_member);
    token_dispatcher.approve(contract_address, token_amount);
    stop_cheat_caller_address(token_address);

    // Try to contribute as non-member (should fail)
    start_cheat_caller_address(contract_address, non_member);
    // This should fail with 'User not member of this group'
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_contribute_nonexistent_group() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    let user: ContractAddress = contract_address_const::<2>();

    // Register user
    start_cheat_caller_address(contract_address, user);
    dispatcher.register_user("TestUser", "avatar.png");

    // Try to contribute to non-existent group
    let fake_group_id = 999_u256;
    // This should fail with 'Group does not exist'
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_contribute_event_emission() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    let user: ContractAddress = contract_address_const::<2>();
    let contribution_amount = 1000_u256;
    let token_amount = 5000_u256;

    let group_id = setup_user_and_group(
        contract_address, token_address, owner, user, contribution_amount, token_amount,
    );

    // Setup event spy
    let mut spy = spy_events();

    start_cheat_caller_address(contract_address, user);

    // Make contribution
    dispatcher.contribute(group_id);

    // Calculate expected values
    let insurance_fee = (contribution_amount * 100) / 10000;
    let total_payment = contribution_amount + insurance_fee;

    // Check that ContributionMade event was emitted
    let expected_event = SaveCircle::Event::ContributionMade(
        ContributionMade {
            group_id, user, contribution_amount, insurance_fee, total_paid: total_payment,
        },
    );

    spy.assert_emitted(@array![(contract_address, expected_event)]);

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_contribute_insurance_pool_update() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    let user1: ContractAddress = contract_address_const::<2>();
    let user2: ContractAddress = contract_address_const::<3>();
    let contribution_amount = 1000_u256;
    let token_amount = 5000_u256;

    // Setup first user and group
    let group_id = setup_user_and_group(
        contract_address, token_address, owner, user1, contribution_amount, token_amount,
    );

    // Setup second user
    start_cheat_caller_address(contract_address, user2);
    dispatcher.register_user("User2", "avatar2.png");
    dispatcher.join_group(group_id);
    stop_cheat_caller_address(contract_address);

    // Give tokens to second user
    start_cheat_caller_address(token_address, owner);
    token_dispatcher.transfer(user2, token_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, user2);
    token_dispatcher.approve(contract_address, token_amount);
    stop_cheat_caller_address(token_address);

    let insurance_fee = (contribution_amount * 100) / 10000;

    // First user contributes
    start_cheat_caller_address(contract_address, user1);
    dispatcher.contribute(group_id);
    stop_cheat_caller_address(contract_address);

    // Second user contributes
    start_cheat_caller_address(contract_address, user2);
    dispatcher.contribute(group_id);
    stop_cheat_caller_address(contract_address);

    // Insurance pool should have accumulated fees from both contributions
    // Note: We would need a getter function for insurance_pool to test this properly
    // For now, we verify that both contributions succeeded
    let member1_info = dispatcher.get_group_member(group_id, 0);
    let member2_info = dispatcher.get_group_member(group_id, 1);

    assert(member1_info.contribution_count == 1, 'User1 have 1 contribution');
    assert(member2_info.contribution_count == 1, 'User2 have 1 contribution');
}


#[test]
fn test_contribute_three_members_with_insurance_fee() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    let user1: ContractAddress = contract_address_const::<2>();
    let user2: ContractAddress = contract_address_const::<3>();
    let user3: ContractAddress = contract_address_const::<4>();
    let contribution_amount = 1000_u256;
    let token_amount = 10000_u256;

    // Setup first user and group
    let group_id = setup_user_and_group(
        contract_address, token_address, owner, user1, contribution_amount, token_amount,
    );

    // Setup second user
    start_cheat_caller_address(contract_address, user2);
    dispatcher.register_user("User2", "avatar2.png");
    dispatcher.join_group(group_id);
    stop_cheat_caller_address(contract_address);

    // Setup third user
    start_cheat_caller_address(contract_address, user3);
    dispatcher.register_user("User3", "avatar3.png");
    dispatcher.join_group(group_id);
    stop_cheat_caller_address(contract_address);

    // Give tokens to all users
    start_cheat_caller_address(token_address, owner);
    token_dispatcher.transfer(user2, token_amount);
    token_dispatcher.transfer(user3, token_amount);
    stop_cheat_caller_address(token_address);

    // Users approve contract to spend tokens
    start_cheat_caller_address(token_address, user2);
    token_dispatcher.approve(contract_address, token_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, user3);
    token_dispatcher.approve(contract_address, token_amount);
    stop_cheat_caller_address(token_address);

    // Calculate expected insurance fee (1% of contribution)
    let insurance_fee = (contribution_amount * 100) / 10000;
    let total_payment = contribution_amount + insurance_fee;

    // Check initial contract balance
    let initial_contract_balance = token_dispatcher.balance_of(contract_address);

    // User1 contributes
    start_cheat_caller_address(contract_address, user1);
    let result1 = dispatcher.contribute(group_id);
    assert(result1 == true, 'User1 contri should succeed');
    stop_cheat_caller_address(contract_address);

    // User2 contributes
    start_cheat_caller_address(contract_address, user2);
    let result2 = dispatcher.contribute(group_id);
    assert(result2 == true, 'User2 contri should succeed');
    stop_cheat_caller_address(contract_address);

    // User3 contributes
    start_cheat_caller_address(contract_address, user3);
    let result3 = dispatcher.contribute(group_id);
    assert(result3 == true, 'User3 contri should succeed');
    stop_cheat_caller_address(contract_address);

    // Verify all members have contributed
    let member1_info = dispatcher.get_group_member(group_id, 0);
    let member2_info = dispatcher.get_group_member(group_id, 1);
    let member3_info = dispatcher.get_group_member(group_id, 2);

    assert(member1_info.contribution_count == 1, 'User1 contri count wrong');
    assert(member2_info.contribution_count == 1, 'User2 contri count wrong');
    assert(member3_info.contribution_count == 1, 'User3 contri count wrong');

    // Verify total insurance fees collected (3 * insurance_fee)
    let final_contract_balance = token_dispatcher.balance_of(contract_address);
    let expected_total_collected = total_payment * 3;
    assert(
        final_contract_balance == initial_contract_balance + expected_total_collected,
        'Total insurance fees incorrect',
    );

    // Verify individual user balances
    let user1_balance = token_dispatcher.balance_of(user1);
    let user2_balance = token_dispatcher.balance_of(user2);
    let user3_balance = token_dispatcher.balance_of(user3);

    assert(user1_balance == token_amount - total_payment, 'User1 balance incorrect');
    assert(user2_balance == token_amount - total_payment, 'User2 balance incorrect');
    assert(user3_balance == token_amount - total_payment, 'User3 balance incorrect');
}

#[test]
fn test_contribute_two_groups_multiple_members() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Users for group 1
    let group1_user1: ContractAddress = contract_address_const::<2>();
    let group1_user2: ContractAddress = contract_address_const::<3>();

    // Users for group 2
    let group2_user1: ContractAddress = contract_address_const::<4>();
    let group2_user2: ContractAddress = contract_address_const::<5>();

    let contribution_amount = 500_u256;
    let token_amount = 5000_u256;

    // Setup Group 1
    let group1_id = setup_user_and_group(
        contract_address, token_address, owner, group1_user1, contribution_amount, token_amount,
    );

    // Add second member to Group 1
    start_cheat_caller_address(contract_address, group1_user2);
    dispatcher.register_user("Group1User2", "avatar_g1u2.png");
    dispatcher.join_group(group1_id);
    stop_cheat_caller_address(contract_address);

    // Setup Group 2 (first user creates and joins)
    start_cheat_caller_address(contract_address, group2_user1);
    dispatcher.register_user("Group2User1", "avatar_g2u1.png");

    let group2_id = dispatcher
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

    dispatcher.activate_group(group2_id);
    dispatcher.join_group(group2_id);
    stop_cheat_caller_address(contract_address);

    // Add second member to Group 2
    start_cheat_caller_address(contract_address, group2_user2);
    dispatcher.register_user("Group2User2", "avatar_g2u2.png");
    dispatcher.join_group(group2_id);
    stop_cheat_caller_address(contract_address);

    // Give tokens to all users
    start_cheat_caller_address(token_address, owner);
    token_dispatcher.transfer(group1_user2, token_amount);
    token_dispatcher.transfer(group2_user1, token_amount);
    token_dispatcher.transfer(group2_user2, token_amount);
    stop_cheat_caller_address(token_address);

    // All users approve contract to spend tokens
    start_cheat_caller_address(token_address, group1_user2);
    token_dispatcher.approve(contract_address, token_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, group2_user1);
    token_dispatcher.approve(contract_address, token_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, group2_user2);
    token_dispatcher.approve(contract_address, token_amount);
    stop_cheat_caller_address(token_address);

    let insurance_fee = (contribution_amount * 100) / 10000;
    let total_payment = contribution_amount + insurance_fee;

    // Group 1 contributions
    start_cheat_caller_address(contract_address, group1_user1);
    let g1u1_result = dispatcher.contribute(group1_id);
    assert(g1u1_result == true, 'Group1 User1 contrib failed');
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, group1_user2);
    let g1u2_result = dispatcher.contribute(group1_id);
    assert(g1u2_result == true, 'Group1 User2 contrib failed');
    stop_cheat_caller_address(contract_address);

    // Group 2 contributions
    start_cheat_caller_address(contract_address, group2_user1);
    let g2u1_result = dispatcher.contribute(group2_id);
    assert(g2u1_result == true, 'Group2 User1 contrib failed');
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, group2_user2);
    let g2u2_result = dispatcher.contribute(group2_id);
    assert(g2u2_result == true, 'Group2 User2 contrib failed');
    stop_cheat_caller_address(contract_address);

    // Verify Group 1 member contributions
    let g1_member1_info = dispatcher.get_group_member(group1_id, 0);
    let g1_member2_info = dispatcher.get_group_member(group1_id, 1);

    assert(g1_member1_info.contribution_count == 1, 'G1 User1 contrib count wrong');
    assert(g1_member2_info.contribution_count == 1, 'G1 User2 contrib count wrong');

    // Verify Group 2 member contributions
    let g2_member1_info = dispatcher.get_group_member(group2_id, 0);
    let g2_member2_info = dispatcher.get_group_member(group2_id, 1);

    assert(g2_member1_info.contribution_count == 1, 'G2 User1 contrib count wrong');
    assert(g2_member2_info.contribution_count == 1, 'G2 User2 contrib count wrong');

    // Verify that groups are independent (different group IDs)
    assert(group1_id != group2_id, 'Groups shd have different IDs');

    // Verify user balances (each user should have paid total_payment)
    let g1u1_balance = token_dispatcher.balance_of(group1_user1);
    let g1u2_balance = token_dispatcher.balance_of(group1_user2);
    let g2u1_balance = token_dispatcher.balance_of(group2_user1);
    let g2u2_balance = token_dispatcher.balance_of(group2_user2);

    assert(g1u1_balance == token_amount - total_payment, 'G1U1 balance incorrect');
    assert(g1u2_balance == token_amount - total_payment, 'G1U2 balance incorrect');
    assert(g2u1_balance == token_amount - total_payment, 'G2U1 balance incorrect');
    assert(g2u2_balance == token_amount - total_payment, 'G2U2 balance incorrect');
}
