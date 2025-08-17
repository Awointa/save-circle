use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use save_circle::contracts::Savecircle::SaveCircle::Event;
use save_circle::enums::Enums::{LockType, TimeUnit};
use save_circle::events::Events::{PayoutDistributed};
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

fn setup_group_with_contributions(
    contract_address: ContractAddress,
    token_address: ContractAddress,
    owner: ContractAddress,
    users: Array<ContractAddress>,
    contribution_amount: u256,
    token_amount: u256,
) -> u256 {
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    let creator = *users.at(0);

    // Register all users
    let mut i = 0;
    while i < users.len() {
        let user = *users.at(i);
        start_cheat_caller_address(contract_address, user);
        dispatcher.register_user("TestUser", "avatar.png");
        stop_cheat_caller_address(contract_address);
        i += 1;
    }

    // Create group with creator
    start_cheat_caller_address(contract_address, creator);
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

    // Activate the group
    dispatcher.activate_group(group_id);
    stop_cheat_caller_address(contract_address);

    // All users join the group
    i = 0;
    while i < users.len() {
        let user = *users.at(i);
        start_cheat_caller_address(contract_address, user);
        dispatcher.join_group(group_id);
        stop_cheat_caller_address(contract_address);
        i += 1;
    }

    // Transfer tokens to all users and make contributions
    i = 0;
    while i < users.len() {
        let user = *users.at(i);

        // Transfer tokens
        start_cheat_caller_address(token_address, owner);
        token_dispatcher.transfer(user, token_amount);
        stop_cheat_caller_address(token_address);

        // Approve and contribute
        start_cheat_caller_address(token_address, user);
        token_dispatcher.approve(contract_address, token_amount);
        stop_cheat_caller_address(token_address);

        start_cheat_caller_address(contract_address, user);
        dispatcher.contribute(group_id);
        stop_cheat_caller_address(contract_address);

        i += 1;
    }

    group_id
}

#[test]
fn test_distribute_payout_success() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Setup users
    let user1: ContractAddress = contract_address_const::<2>();
    let user2: ContractAddress = contract_address_const::<3>();
    let user3: ContractAddress = contract_address_const::<4>();
    let users = array![user1, user2, user3];

    let contribution_amount = 1000_u256;
    let token_amount = 5000_u256;

    let group_id = setup_group_with_contributions(
        contract_address, token_address, owner, users, contribution_amount, token_amount,
    );

    // Get initial balances
    let initial_balance_user1 = token_dispatcher.balance_of(user1);
    let initial_balance_user2 = token_dispatcher.balance_of(user2);
    let initial_balance_user3 = token_dispatcher.balance_of(user3);

    // Get next recipient before payout
    let next_recipient = dispatcher.get_next_payout_recipient(group_id);
    assert(next_recipient.user != contract_address_const::<0>(), 'Should have recipient');

    // Distribute payout (creator can distribute)
    start_cheat_caller_address(contract_address, user1);
    let result = dispatcher.distribute_payout(group_id);
    assert(result == true, 'Payout should succeed');
    stop_cheat_caller_address(contract_address);

    // Check that recipient received payout
    let recipient_balance = token_dispatcher.balance_of(next_recipient.user);

    if next_recipient.user == user1 {
        assert(recipient_balance > initial_balance_user1, 'User1 should receive payout');
    } else if next_recipient.user == user2 {
        assert(recipient_balance > initial_balance_user2, 'User2 should receive payout');
    } else if next_recipient.user == user3 {
        assert(recipient_balance > initial_balance_user3, 'User3 should receive payout');
    }

    // Check group state updates
    let group_info = dispatcher.get_group_info(group_id);
    assert(group_info.current_cycle == 1, 'Cycle should increment');
    assert(group_info.payout_order == 1, 'Payout order should increment');

    // Check member payout status
    let member_index = dispatcher.get_user_member_index(next_recipient.user, group_id);
    let updated_member = dispatcher.get_group_member(group_id, member_index);
    assert(updated_member.has_been_paid == true, 'Member should be marked as paid');
}

#[test]
fn test_distribute_payout_event_emission() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user1: ContractAddress = contract_address_const::<2>();
    let user2: ContractAddress = contract_address_const::<3>();
    let users = array![user1, user2];

    let contribution_amount = 1000_u256;
    let token_amount = 5000_u256;

    let group_id = setup_group_with_contributions(
        contract_address, token_address, owner, users, contribution_amount, token_amount,
    );

    let mut spy = spy_events();

    // Get next recipient
    let next_recipient = dispatcher.get_next_payout_recipient(group_id);

    // Distribute payout
    start_cheat_caller_address(contract_address, user1);
    dispatcher.distribute_payout(group_id);
    stop_cheat_caller_address(contract_address);

    // Check event emission
    let expected_payout = contribution_amount * 2; // 2 users contributed
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::PayoutDistributed(
                        PayoutDistributed {
                            group_id,
                            recipient: next_recipient.user,
                            amount: expected_payout,
                            cycle: 1,
                        },
                    ),
                ),
            ],
        );
}

// #[test]
// fn test_distribute_payout_multiple_cycles() {
//     let (contract_address, owner, token_address) = setup();
//     let dispatcher = IsavecircleDispatcher { contract_address };

//     let user1: ContractAddress = contract_address_const::<2>();
//     let user2: ContractAddress = contract_address_const::<3>();
//     let user3: ContractAddress = contract_address_const::<4>();
//     let users = array![user1, user2, user3];

//     let contribution_amount = 1000_u256;
//     let token_amount = 10000_u256;

//     let group_id = setup_group_with_contributions(
//         contract_address, token_address, owner, users, contribution_amount, token_amount
//     );

//     // First payout
//     let recipient1 = dispatcher.get_next_payout_recipient(group_id);

//     start_cheat_caller_address(contract_address, user1);
//     dispatcher.distribute_payout(group_id);
//     stop_cheat_caller_address(contract_address);

//     // Make second round of contributions
//     let mut i = 0;
//     while i < users.len() {
//         let user = *users.at(i);
//         start_cheat_caller_address(contract_address, user);
//         dispatcher.contribute(group_id);
//         stop_cheat_caller_address(contract_address);
//         i += 1;
//     }

//     // Second payout
//     let recipient2 = dispatcher.get_next_payout_recipient(group_id);

//     start_cheat_caller_address(contract_address, user1);
//     dispatcher.distribute_payout(group_id);
//     stop_cheat_caller_address(contract_address);

//     // Verify different recipients
//     assert(recipient1.user != recipient2.user, 'Recipients should be different');

//     // Check group state
//     let group_info = dispatcher.get_group_info(group_id);
//     assert(group_info.current_cycle == 2, 'Should be cycle 2');
//     assert(group_info.payout_order == 2, 'Payout order should be 2');
// }

// #[test]
// fn test_distribute_payout_group_completion() {
//     let (contract_address, owner, token_address) = setup();
//     let dispatcher = IsavecircleDispatcher { contract_address };
//     let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

//     let user1: ContractAddress = contract_address_const::<2>();
//     let user2: ContractAddress = contract_address_const::<3>();
//     let users = array![user1, user2];

//     let contribution_amount = 1000_u256;
//     let token_amount = 20000_u256; // Increased token amount for multiple contributions

//     let group_id = setup_group_with_contributions(
//         contract_address, token_address, owner, users, contribution_amount, token_amount
//     );

//     // First payout
//     start_cheat_caller_address(contract_address, user1);
//     dispatcher.distribute_payout(group_id);
//     stop_cheat_caller_address(contract_address);

//     // Transfer more tokens for second round of contributions
//     start_cheat_caller_address(token_address, owner);
//     token_dispatcher.transfer(user1, token_amount);
//     token_dispatcher.transfer(user2, token_amount);
//     stop_cheat_caller_address(token_address);

//     // Approve more tokens for second round
//     start_cheat_caller_address(token_address, user1);
//     token_dispatcher.approve(contract_address, token_amount);
//     stop_cheat_caller_address(token_address);

//     start_cheat_caller_address(token_address, user2);
//     token_dispatcher.approve(contract_address, token_amount);
//     stop_cheat_caller_address(token_address);

//     // Make contributions for second cycle
//     start_cheat_caller_address(contract_address, user1);
//     dispatcher.contribute(group_id);
//     stop_cheat_caller_address(contract_address);

//     start_cheat_caller_address(contract_address, user2);
//     dispatcher.contribute(group_id);
//     stop_cheat_caller_address(contract_address);

//     // Second payout (should complete the group)
//     start_cheat_caller_address(contract_address, user1);
//     dispatcher.distribute_payout(group_id);
//     stop_cheat_caller_address(contract_address);

//     // Check group is completed
//     let group_info = dispatcher.get_group_info(group_id);
//     assert(group_info.state == GroupState::Completed, 'Group should be completed');
//     assert(group_info.payout_order == 2, 'All members should be paid');
// }

#[test]
#[should_panic(expected: ('Group must be active',))]
fn test_distribute_payout_inactive_group() {
    let (contract_address, _owner, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<2>();
    start_cheat_caller_address(contract_address, user);

    // Register user and create group but don't activate
    dispatcher.register_user("TestUser", "avatar.png");
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

    // Try to distribute payout on inactive group
    dispatcher.distribute_payout(group_id);
}

#[test]
#[should_panic(expected: "Only creator  can distribute")]
fn test_distribute_payout_unauthorized_caller() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user1: ContractAddress = contract_address_const::<2>();
    let user2: ContractAddress = contract_address_const::<3>();
    let users = array![user1, user2];

    let contribution_amount = 1000_u256;
    let token_amount = 5000_u256;

    let group_id = setup_group_with_contributions(
        contract_address, token_address, owner, users, contribution_amount, token_amount,
    );

    // Try to distribute payout as non-creator
    let unauthorized_user: ContractAddress = contract_address_const::<5>();
    start_cheat_caller_address(contract_address, unauthorized_user);
    dispatcher.distribute_payout(group_id);
}

#[test]
#[should_panic(expected: "No contributions to distribute")]
fn test_distribute_payout_no_contributions() {
    let (contract_address, _owner, _token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user: ContractAddress = contract_address_const::<2>();
    start_cheat_caller_address(contract_address, user);

    // Register user and create/activate group
    dispatcher.register_user("TestUser", "avatar.png");
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
    dispatcher.activate_group(group_id);
    dispatcher.join_group(group_id);

    // Try to distribute payout without contributions
    dispatcher.distribute_payout(group_id);
}

#[test]
fn test_get_payout_order() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user1: ContractAddress = contract_address_const::<2>();
    let user2: ContractAddress = contract_address_const::<3>();
    let user3: ContractAddress = contract_address_const::<4>();
    let users = array![user1, user2, user3];

    let contribution_amount = 1000_u256;
    let token_amount = 5000_u256;

    let group_id = setup_group_with_contributions(
        contract_address, token_address, owner, users, contribution_amount, token_amount,
    );

    // Get payout order
    let payout_order = dispatcher.get_payout_order(group_id);

    // Should have all 3 users in the order
    assert(payout_order.len() == 3, 'Should have 3 users in order');

    // Verify all users are included
    let mut found_user1 = false;
    let mut found_user2 = false;
    let mut found_user3 = false;

    let mut i = 0;
    while i < payout_order.len() {
        let user = *payout_order.at(i);
        if user == user1 {
            found_user1 = true;
        } else if user == user2 {
            found_user2 = true;
        } else if user == user3 {
            found_user3 = true;
        }
        i += 1;
    }

    assert(found_user1 && found_user2 && found_user3, 'All users should be in order');
}

#[test]
fn test_get_next_payout_recipient() {
    let (contract_address, owner, token_address) = setup();
    let dispatcher = IsavecircleDispatcher { contract_address };

    let user1: ContractAddress = contract_address_const::<2>();
    let user2: ContractAddress = contract_address_const::<3>();
    let users = array![user1, user2];

    let contribution_amount = 1000_u256;
    let token_amount = 5000_u256;

    let group_id = setup_group_with_contributions(
        contract_address, token_address, owner, users, contribution_amount, token_amount,
    );

    // Get next recipient
    let next_recipient = dispatcher.get_next_payout_recipient(group_id);
    assert(next_recipient.user != contract_address_const::<0>(), 'Should have recipient');
    assert(next_recipient.has_been_paid == false, 'Reci should not be paid yet');
    assert(next_recipient.group_id == group_id, 'Should be from correct group');
}
