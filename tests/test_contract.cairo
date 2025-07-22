use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use save_circle::contracts::Savecircle::SaveCircle;
use save_circle::contracts::Savecircle::SaveCircle::Event;
use save_circle::events::Events::UserRegistered;
use save_circle::interfaces::Isavecircle::{IsavecircleDispatcher, IsavecircleDispatcherTrait};
use save_circle::structs::Structs::UserProfile;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};


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
    let (contract_address, owner, _token_address) = setup();
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
