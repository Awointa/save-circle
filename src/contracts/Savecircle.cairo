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
    use save_circle::events::Events::{GroupCreated, UserJoinedGroup, UserRegistered, UsersInvited};
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
        group_members: Map<(u256, u32), GroupMember>,
        public_groups: Vec<u256>,
        group_invitations: Map<(u256, ContractAddress), bool>,
        next_group_id: u256,
        user_payout_index: Map<(u64, ContractAddress), u32>,
        group_invited_members: Map<(u256, u32), ContractAddress>,
        total_users: u256,
        user_joined_groups: Map<
            (ContractAddress, u256), u32,
        >, // to help us track the user joined groups
        group_next_member_index: Map<
            u256, u32,
        > // to help us track the next member index for each group
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
        UserJoinedGroup: UserJoinedGroup,
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
            member_limit: u32,
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

            // Initialize member index counter for this group
            self.group_next_member_index.write(group_id, 0);

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
            member_limit: u32,
            contribution_amount: u256,
            cycle_duration: u64,
            cycle_unit: TimeUnit,
            invited_members: Array<ContractAddress>,
            requires_lock: bool,
            lock_type: LockType,
            min_reputation_score: u32,
        ) -> u256 {
            let caller = get_caller_address();
            let group_id = self.next_group_id.read();
            let current_time = get_block_timestamp();

            // 🔒 Validate lock_type if lock is required
            if requires_lock {
                assert!(lock_type != LockType::None, "Lock type required when locking is enabled");
            }

            // create private group with no lock requirements and trust-based
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
                total_cycles: member_limit,
                visibility: GroupVisibility::Private,
                requires_lock,
                requires_reputation_score: min_reputation_score,
                invited_members: invited_members.len(),
            };

            self.groups.write(group_id, group_info);

            // Initialize member index counter for this group
            self.group_next_member_index.write(group_id, 0);

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
                    UsersInvited { group_id, inviter: caller, invitees: invited_members.clone() },
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
                        requires_lock,
                    },
                );

            group_id
        }


        fn join_group(ref self: ContractState, group_id: u256) -> u32 {
            let caller = get_caller_address();
            let current_time = get_block_timestamp();

            // check if uers is registerd to platform
            let user_profiles = self.user_profiles.read(caller);
            assert!(user_profiles.is_registered, "Only registered use can join group");

            // check if group exists
            let mut group_info = self.groups.read(group_id);
            assert!(group_info.group_id != 0, "Group does not exist");

            // check if group is full
            assert!(group_info.members < group_info.member_limit, "Group is full");

            // check if user is a group member
            let existing_member_index = self.user_joined_groups.read((caller, group_id));
            assert!(existing_member_index == 0, "User is already a member");

            // for private groups
            if group_info.visibility == GroupVisibility::Private {
                let invitation = self.group_invitations.read((group_id, caller));
                assert!(invitation, "User is not invited to join group");
            }

            // lets get member index
            let member_index = self.group_next_member_index.read(group_id);
            assert!(member_index <= group_info.member_limit, "Group is full");

            let group_member = GroupMember {
                user: caller,
                group_id,
                locked_amount: 0,
                joined_at: current_time,
                member_index,
                payout_cycle: 0,
                has_been_paid: false,
                contribution_count: 0,
                late_contributions: 0,
                missed_contributions: 0,
            };

            self.group_members.write((group_id, member_index), group_member);

            self.user_joined_groups.write((caller, group_id), member_index);

            //lets update members count
            group_info.members += 1;
            self.groups.write(group_id, group_info);
            self.group_next_member_index.write(group_id, member_index + 1);

            // Remove invitation if it was a private group
            if group_info.visibility == GroupVisibility::Private {
                self.group_invitations.write((group_id, caller), false);
            }

            self
                .emit(
                    UserJoinedGroup {
                        group_id, user: caller, member_index, joined_at: current_time,
                    },
                );

            member_index
        }


        fn get_group_member(
            self: @ContractState, group_id: u256, member_index: u32,
        ) -> GroupMember {
            self.group_members.read((group_id, member_index))
        }


        fn get_user_member_index(
            self: @ContractState, user: ContractAddress, group_id: u256,
        ) -> u32 {
            self.user_joined_groups.read((user, group_id))
        }


        fn is_group_member(self: @ContractState, group_id: u256, user: ContractAddress) -> bool {
            self._is_member(group_id, user)
        }
    }


    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _is_member(self: @ContractState, group_id: u256, user: ContractAddress) -> bool {
            let member_index = self.user_joined_groups.read((user, group_id));
            if member_index == 0 {
                // Check if member at index 0 is actually this user
                let member_at_zero = self.group_members.read((group_id, 0));
                member_at_zero.user == user
            } else {
                true
            }
        }
    }
}

