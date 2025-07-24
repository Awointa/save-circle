// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^2.0.0

const PAUSER_ROLE: felt252 = selector!("PAUSER_ROLE");
const UPGRADER_ROLE: felt252 = selector!("UPGRADER_ROLE");

#[starknet::contract]
pub mod SaveCircle {
    use openzeppelin::access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use save_circle::enums::Enums::{GroupState, GroupVisibility, LockType, TimeUnit};
    use save_circle::events::Events::{GroupCreated, UserRegistered, UsersInvited};
    use save_circle::interfaces::Isavecircle::Isavecircle;
    use save_circle::structs::Structs::{GroupInfo, GroupMember, UserProfile, joined_group};
    use starknet::event::EventEmitter;
    use starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess, Vec,
    };
    use starknet::{ClassHash, ContractAddress, get_block_timestamp, get_caller_address};
    use super::{PAUSER_ROLE, UPGRADER_ROLE};

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
        groups: Map<u256, GroupInfo>,
        joined_groups: Map<(ContractAddress, u64), joined_group>,
        group_members: Map<(u64, ContractAddress), GroupMember>,
        public_groups: Vec<u256>,
        group_invitations: Map<(u256, ContractAddress), bool>,
        next_group_id: u256,
        user_payout_index: Map<(u64, ContractAddress), u32>,
        group_invited_members: Map<(u256, u32), ContractAddress>,
        total_users: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
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
        GroupCreated: GroupCreated,
        UsersInvited: UsersInvited,
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
        self.next_group_id.write(1);
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
                user_address: caller,
                name,
                avatar,
                is_registered: true,
                total_lock_amount: 0,
                profile_created_at: starknet::get_block_timestamp(),
            };

            user_entry.write(new_profile);

            self.total_users.write(self.total_users.read() + 1);

            self.emit(UserRegistered { user: caller, name });

            true
        }


        fn get_user_profile(self: @ContractState, user_address: ContractAddress) -> UserProfile {
            self.user_profiles.entry(user_address).read()
        }

        fn create_group(
            ref self: ContractState,
            member_limit: u8,
            contribution_amount: u256,
            lock_type: LockType,
            cycle_duration: u64,
            cycle_unit: TimeUnit,
            visibility: GroupVisibility,
            requires_lock: bool,
            min_reputation_score: u32,
        ) -> u256 {
            let caller = get_caller_address();
            let group_id = self.next_group_id.read();
            let current_time = get_block_timestamp();

            let user_entry = self.user_profiles.entry(caller);
            let existing_profile = user_entry.read();
            assert!(existing_profile.is_registered, "Only registered use can create group");

            // calculate total cycles based on the member limit
            let total_cycles = member_limit;

            let group_info = GroupInfo {
                group_id,
                creator: caller,
                member_limit,
                contribution_amount,
                lock_type,
                cycle_duration,
                cycle_unit,
                members: 0,
                state: GroupState::Created,
                current_cycle: 0,
                payout_order: 0,
                start_time: current_time,
                total_cycles,
                visibility,
                requires_lock,
                requires_reputation_score: min_reputation_score,
                invited_members: 0,
            };

            self.groups.write(group_id, group_info);

            if visibility == GroupVisibility::Public {
                self.public_groups.push(group_id)
            }

            self.next_group_id.write(group_id + 1);

            self
                .emit(
                    GroupCreated {
                        group_id,
                        creator: caller,
                        member_limit,
                        contribution_amount,
                        cycle_duration,
                        cycle_unit,
                        visibility,
                        requires_lock,
                    },
                );

            group_id
        }

        fn get_group_info(self: @ContractState, group_id: u256) -> GroupInfo {
            self.groups.read(group_id)
        }

        fn create_private_group(
            ref self: ContractState,
            member_limit: u8,
            contribution_amount: u256,
            cycle_duration: u64,
            cycle_unit: TimeUnit,
            invited_members: Array<ContractAddress>,
        ) -> u256 {
            let caller = get_caller_address();
            let group_id = self.next_group_id.read();

            // create private group with no lock requirements and trust-based
            let group_info = GroupInfo {
                group_id,
                creator: caller,
                member_limit,
                contribution_amount,
                lock_type: LockType::Upfront,
                cycle_duration,
                cycle_unit,
                members: 0,
                state: GroupState::Created,
                current_cycle: 0,
                payout_order: 0,
                start_time: get_block_timestamp(),
                total_cycles: member_limit,
                visibility: GroupVisibility::Private,
                requires_lock: false,
                requires_reputation_score: 0,
                invited_members: invited_members.len(),
            };

            self.groups.write(group_id, group_info);

            // spend invitations to all specified members
            assert!(invited_members.len() <= 1000, "Exceed max invite limit");
            let mut i = 0;
            while i < invited_members.len() {
                let invitee = invited_members[i];
                self.group_invitations.write((group_id, *invitee), true);
                i += 1;
            }
            
            self
            .emit(
                UsersInvited {
                    group_id, inviter: caller, invitees: invited_members.clone(),
                },
            );

            self.next_group_id.write(group_id + 1);

            self
                .emit(
                    GroupCreated {
                        group_id,
                        creator: caller,
                        member_limit,
                        contribution_amount,
                        cycle_duration,
                        cycle_unit,
                        visibility: GroupVisibility::Private,
                        requires_lock: false,
                    },
                );

            group_id
        }
    }
}

