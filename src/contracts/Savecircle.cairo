// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^2.0.0

const PAUSER_ROLE: felt252 = selector!("PAUSER_ROLE");
const UPGRADER_ROLE: felt252 = selector!("UPGRADER_ROLE");

#[starknet::contract]
pub mod SaveCircle {
    use starknet::event::EventEmitter;
use openzeppelin::access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use save_circle::interfaces::Isavecircle::Isavecircle;
    use save_circle::structs::Structs::UserProfile;
    use starknet::storage::{
        Map, StorageMapReadAccess, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess, Vec,
    };
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use super::{PAUSER_ROLE, UPGRADER_ROLE};
    use save_circle::events::Events::UserRegistered;

    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    // External
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    #[abi(embed_v0)]
    impl AccessControlMixinImpl =
        AccessControlComponent::AccessControlMixinImpl<ContractState>;

    // Internal
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        // payment token address
        payment_token_address: ContractAddress,
        //user profiles
        user_profiles: Map<ContractAddress, UserProfile>,
        total_users: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        // Add Events after importing it above
        UserRegistered: UserRegistered,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, default_admin: ContractAddress, token_address: ContractAddress,
    ) {
        self.accesscontrol.initializer();

        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, default_admin);
        self.accesscontrol._grant_role(PAUSER_ROLE, default_admin);
        self.accesscontrol._grant_role(UPGRADER_ROLE, default_admin);

        self.payment_token_address.write(token_address);
    }

    #[generate_trait]
    #[abi(per_item)]
    impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn pause(ref self: ContractState) {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);
            self.pausable.pause();
        }

        #[external(v0)]
        fn unpause(ref self: ContractState) {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);
            self.pausable.unpause();
        }
    }

    //
    // Upgradeable
    //

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(UPGRADER_ROLE);
            self.upgradeable.upgrade(new_class_hash);
        }
    }


    #[abi(embed_v0)]
    impl SavecircleImpl of Isavecircle<ContractState> {
        fn register_user(ref self: ContractState, name: felt252, avatar: felt252) -> bool {
            let caller = get_caller_address();

            let user_entry = self.user_profiles.entry(caller);
            let existing_profile = user_entry.read();
            assert(!existing_profile.is_registered, ' User already registered');

            assert(name != 0, ' Name cannot be empty');

            let new_profile = UserProfile {
                user_address: caller, name, avatar, is_registered: true, total_lock_amount: 0,
            };

            user_entry.write(new_profile);

            self.total_users.write(self.total_users.read() + 1);


            self.emit(UserRegistered {
                user: caller,
                name,
            });

            true
        }


        fn get_user_profile(self: @ContractState, user_address: ContractAddress) -> UserProfile {
            self.user_profiles.entry(user_address).read()
        }
    }
}

