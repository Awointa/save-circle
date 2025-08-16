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
    use save_circle::enums::Enums::{GroupState, GroupVisibility, LockType, TimeUnit, ActivityType};
    use save_circle::events::Events::{GroupCreated, UserJoinedGroup, UserRegistered, UsersInvited, ContributionMade, PayoutSent};
    use save_circle::interfaces::Isavecircle::Isavecircle;
    use save_circle::structs::Structs::{
        GroupInfo, GroupMember, UserProfile, UserActivity, UserStatistics, 
        ProfileViewData, UserGroupDetails, PayoutRecord
    };
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
        
        // Core storage
        payment_token_address: ContractAddress,
        user_profiles: Map<ContractAddress, UserProfile>,
        groups: Map<u256, GroupInfo>,
        group_members: Map<(u256, u32), GroupMember>,
        public_groups: Vec<u256>,
        group_invitations: Map<(u256, ContractAddress), bool>,
        next_group_id: u256,
        total_users: u256,
        
        // Enhanced tracking for profile features
        user_joined_groups: Map<(ContractAddress, u256), u32>, // (user, group_id) -> member_index
        user_joined_groups_list: Map<(ContractAddress, u32), u256>, // (user, index) -> group_id
        user_joined_groups_count: Map<ContractAddress, u32>,
        group_next_member_index: Map<u256, u32>,
        
        // Activity tracking
        user_activities: Map<(ContractAddress, u256), UserActivity>, // (user, activity_id) -> activity
        user_activity_count: Map<ContractAddress, u256>,
        next_activity_id: u256,
        
        // Statistics
        user_statistics: Map<ContractAddress, UserStatistics>,
        
        // Payout tracking
        payout_records: Map<u256, PayoutRecord>, // payout_id -> record
        next_payout_id: u256,
        group_payout_queue: Map<(u256, u32), ContractAddress>, // (group_id, position) -> user
        group_exists: Map<u256, bool>,
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
        
        // Custom events
        UserRegistered: UserRegistered,
        GroupCreated: GroupCreated,
        UsersInvited: UsersInvited,
        UserJoinedGroup: UserJoinedGroup,
        ContributionMade: ContributionMade,
        PayoutSent: PayoutSent,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, 
        default_admin: ContractAddress, 
        token_address: ContractAddress,
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, default_admin);
        self.accesscontrol._grant_role(PAUSER_ROLE, default_admin);
        self.accesscontrol._grant_role(UPGRADER_ROLE, default_admin);
        
        self.payment_token_address.write(token_address);
        self.next_group_id.write(1);
        self.next_activity_id.write(1);
        self.next_payout_id.write(1);
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
            let current_time = get_block_timestamp();

            let user_entry = self.user_profiles.entry(caller);
            let existing_profile = user_entry.read();
            assert!(!existing_profile.is_registered, "User already registered");
            assert!(name != 0, "Name cannot be empty");

            let new_profile = UserProfile {
                user_address: caller,
                name,
                avatar,
                is_registered: true,
                total_lock_amount: 0,
                profile_created_at: current_time,
                reputation_score: 0, // Starting reputation
                total_contribution: 0,
                total_joined_groups: 0,
                total_created_groups: 0,
                total_earned: 0,
                completed_cycles: 0,
                active_groups: 0,
                on_time_payments: 0,
                total_payments: 0,
                average_contribution: 0,
                payment_rate: 0,
            };

            user_entry.write(new_profile);
            
            // Initialize user statistics
            let user_stats = UserStatistics {
                user_address: caller,
                total_saved: 0,
                total_earned: 0,
                success_rate: 100,
                average_cycle_duration: 0,
                favorite_contribution_amount: 0,
                longest_active_streak: 0,
                current_active_streak: 0,
                groups_completed_successfully: 0,
                groups_left_early: 0,
                total_penalties_paid: 0,
                updated_at: current_time,
            };
            self.user_statistics.write(caller, user_stats);

            // Record registration activity
            self._record_activity(
                caller,
                ActivityType::UserRegistered,
                selector!("User registered on SaveCircle"),
                0,
                Option::None,
                false
            );

            self.user_joined_groups_count.write(caller, 0);
            self.user_activity_count.write(caller, 1);
            self.total_users.write(self.total_users.read() + 1);

            self.emit(UserRegistered { user: caller, name });
            true
        }

        // Enhanced get_user_profile that returns comprehensive data
        fn get_user_profile_view_data(self: @ContractState, user_address: ContractAddress) -> ProfileViewData {
            let profile = self.user_profiles.read(user_address);
            let statistics = self.user_statistics.read(user_address);
            
            // Get recent activities (last 10)
            let activity_count = self.user_activity_count.read(user_address);
            let mut recent_activities = ArrayTrait::new();
            let start_index = if activity_count > 10 { activity_count - 10 } else { 0 };
            
            let mut i = start_index;
            while i < activity_count {
                let activity = self.user_activities.read((user_address, i));
                recent_activities.append(activity);
                i += 1;
            };

            // Get joined groups
            let joined_groups_count = self.user_joined_groups_count.read(user_address);
            let mut joined_groups = ArrayTrait::new();
            
            let mut i = 0;
            while i < joined_groups_count {
                let group_id = self.user_joined_groups_list.read((user_address, i));
                let group_info = self.groups.read(group_id);
                joined_groups.append(group_info);
                i += 1;
            };

            ProfileViewData {
                profile,
                recent_activities,
                joined_groups,
                statistics,
            }
        }

        fn create_public_group(
            ref self: ContractState,
            name: ByteArray,
            description: ByteArray,
            member_limit: u32,
            contribution_amount: u256,
            lock_type: LockType,
            cycle_duration: u64,
            cycle_unit: TimeUnit,
            requires_lock: bool,
            min_reputation_score: u32,
        ) -> u256 {
            let caller = get_caller_address();
            let group_id = self.next_group_id.read();
            let current_time = get_block_timestamp();

            let user_entry = self.user_profiles.entry(caller);
            let mut existing_profile = user_entry.read();
            assert!(existing_profile.is_registered, "Only registered users can create groups");

            let group_info = GroupInfo {
                group_id,
                group_name: name,
                description,
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
                total_cycles: member_limit,
                completed_cycles: 0,
                start_time: current_time,
                last_payout_time: 0,
                visibility: GroupVisibility::Public,
                requires_lock,
                requires_reputation_score: min_reputation_score,
                total_pool_amount: 0,
                remaining_pool_amount: 0,
                next_payout_recipient: starknet::contract_address_const::<0>(),
                is_active: true,
            };

            self.groups.write(group_id, group_info);
            self.group_next_member_index.write(group_id, 0);
            self.public_groups.push(group_id);
            self.group_exists.write(group_id, true);

            // Update user profile
            existing_profile.total_created_groups += 1;
            user_entry.write(existing_profile);

            // Record activity
            self._record_activity(
                caller,
                ActivityType::GroupCreated,
                selector!("Created new public group"),
                0,
                Option::Some(group_id),
                false
            );

            self.next_group_id.write(group_id + 1);

            self.emit(GroupCreated {
                group_id,
                creator: caller,
                member_limit,
                contribution_amount,
                cycle_duration,
                cycle_unit,
                visibility: GroupVisibility::Public,
                requires_lock,
            });

            group_id
        }

        fn create_private_group(
            ref self: ContractState,
            name: ByteArray,
            description: ByteArray,
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

            let user_entry = self.user_profiles.entry(caller);
            let mut existing_profile = user_entry.read();
            assert!(existing_profile.is_registered, "Only registered users can create groups");

            // Validate lock_type if lock is required
            if !requires_lock {
                assert!(lock_type == LockType::None, "Lock type should be None when locking is disabled");
            }

            // Create private group
            let group_info = GroupInfo {
                group_id,
                group_name: name,
                description,
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
                total_cycles: member_limit,
                completed_cycles: 0,
                start_time: current_time,
                last_payout_time: 0,
                visibility: GroupVisibility::Private,
                requires_lock,
                requires_reputation_score: min_reputation_score,
                total_pool_amount: 0,
                remaining_pool_amount: 0,
                next_payout_recipient: starknet::contract_address_const::<0>(),
                is_active: true,
            };

            self.groups.write(group_id, group_info);
            self.group_next_member_index.write(group_id, 0);
            self.group_exists.write(group_id, true);

            // Send invitations to all specified members
            assert!(invited_members.len() <= 1000, "Exceeded max invite limit");
            let mut i = 0;
            while i < invited_members.len() {
                let invitee = invited_members[i];
                self.group_invitations.write((group_id, *invitee), true);
                i += 1;
            };

            // Update user profile
            existing_profile.total_created_groups += 1;
            user_entry.write(existing_profile);

            // Record activity
            self._record_activity(
                caller,
                ActivityType::GroupCreated,
                selector!("Created new private group"),
                0,
                Option::Some(group_id),
                false
            );

            self.emit(UsersInvited { 
                group_id, 
                inviter: caller, 
                invitees: invited_members.clone() 
            });

            self.next_group_id.write(group_id + 1);

            self.emit(GroupCreated {
                group_id,
                creator: caller,
                member_limit,
                contribution_amount,
                cycle_duration,
                cycle_unit,
                visibility: GroupVisibility::Private,
                requires_lock,
            });

            group_id
        }

        fn join_group(ref self: ContractState, group_id: u256) -> u32 {
            let caller = get_caller_address();
            let current_time = get_block_timestamp();
        
            let user_entry = self.user_profiles.entry(caller);
            let mut user_profile = user_entry.read();
            assert!(user_profile.is_registered, "Only registered users can join groups");
        
            // Check if group exists using the dedicated boolean storage
            let group_exists = self.group_exists.read(group_id);
            assert!(group_exists, "Group does not exist");
            
            let mut group_info = self.groups.read(group_id);
            assert!(group_info.members < group_info.member_limit, "Group is full");
        
            let existing_member_index = self.user_joined_groups.read((caller, group_id));
            // Check if a group member exists at the stored index for this user
            let existing_member = self.group_members.read((group_id, existing_member_index));
            assert!(existing_member.user != caller || !existing_member.is_active, "User is already a member");
        
            if group_info.visibility == GroupVisibility::Private {
                let invitation = self.group_invitations.read((group_id, caller));
                assert!(invitation, "User is not invited to join group");
            }
        
            let member_index = self.group_next_member_index.read(group_id);
        
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
                total_contributed: 0,
                total_recieved: 0,
                is_active: true
            };
        
            self.group_members.write((group_id, member_index), group_member);
            self.user_joined_groups.write((caller, group_id), member_index);
            
            // Add to user's joined groups list
            let joined_count = self.user_joined_groups_count.read(caller);
            self.user_joined_groups_list.write((caller, joined_count), group_id);
            self.user_joined_groups_count.write(caller, joined_count + 1);
        
            // Update group info
            group_info.members += 1;
            self.groups.write(group_id, group_info.clone());
            self.group_next_member_index.write(group_id, member_index + 1);
        
            // Update user profile
            user_profile.total_joined_groups += 1;
            user_profile.active_groups += 1;
            user_entry.write(user_profile);
        
            // Record activity
            self._record_activity(
                caller,
                ActivityType::GroupJoined,
                selector!("Joined new group"),
                0,
                Option::Some(group_id),
                false
            );
        
            if group_info.visibility == GroupVisibility::Private {
                self.group_invitations.write((group_id, caller), false);
            }
        
            self.emit(UserJoinedGroup {
                group_id,
                user: caller,
                member_index,
                joined_at: current_time,
            });
        
            member_index
        }

        // New functions for profile page support
        fn get_user_joined_groups(
            self: @ContractState, 
            user_address: ContractAddress
        ) -> Array<UserGroupDetails> {
            let joined_count = self.user_joined_groups_count.read(user_address);
            let mut groups = ArrayTrait::new();
            
            let mut i = 0;
            while i < joined_count {
                let group_id = self.user_joined_groups_list.read((user_address, i));
                let group_info = self.groups.read(group_id);
                let member_index = self.user_joined_groups.read((user_address, group_id));
                let member_data = self.group_members.read((group_id, member_index));
                let group_info_val = group_info.clone();
                let member_data_val = member_data.clone();

                let group_details = UserGroupDetails {
                    group_info,
                    member_data,
                    next_payout_date: self._calculate_next_payout_date(group_id),
                    position_in_queue: self._get_position_in_payout_queue(group_id, user_address),
                    total_contributed_so_far: member_data_val.total_contributed,
                    expected_payout_amount: group_info_val.contribution_amount * group_info_val.member_limit.into(),
                };

                groups.append(group_details);
                i += 1;
            };
            
            groups
        }

        fn get_user_activities(
            self: @ContractState, 
            user_address: ContractAddress, 
            limit: u32
        ) -> Array<UserActivity> {
            let activity_count = self.user_activity_count.read(user_address);
            let mut activities = ArrayTrait::new();
            
            let start_index = if activity_count > limit.into() { 
                activity_count - limit.into() 
            } else { 
                0 
            };
            
            let mut i = start_index;
            while i < activity_count {
                let activity = self.user_activities.read((user_address, i));
                activities.append(activity);
                i += 1;
            };
            
            activities
        }

        fn get_user_statistics(
            self: @ContractState, 
            user_address: ContractAddress
        ) -> UserStatistics {
            self.user_statistics.read(user_address)
        }

        // Existing functions (keeping your current implementation)
        fn get_group_info(self: @ContractState, group_id: u256) -> GroupInfo {
            self.groups.read(group_id)
        }

        fn get_group_member(
            self: @ContractState, 
            group_id: u256, 
            member_index: u32,
        ) -> GroupMember {
            self.group_members.read((group_id, member_index))
        }

        fn get_user_member_index(
            self: @ContractState, 
            user: ContractAddress, 
            group_id: u256,
        ) -> u32 {
            self.user_joined_groups.read((user, group_id))
        }

        fn is_group_member(
            self: @ContractState, 
            group_id: u256, 
            user: ContractAddress
        ) -> bool {
            self._is_member(group_id, user)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _is_member(self: @ContractState, group_id: u256, user: ContractAddress) -> bool {
            let member_index = self.user_joined_groups.read((user, group_id));
            if member_index == 0 {
                let member_at_zero = self.group_members.read((group_id, 0));
                member_at_zero.user == user
            } else {
                true
            }
        }

        fn _record_activity(
            ref self: ContractState,
            user: ContractAddress,
            activity_type: ActivityType,
            description: felt252,
            amount: u256,
            group_id: Option<u256>,
            is_positive: bool,
        ) {
            let activity_id = self.next_activity_id.read();
            let user_activity_count = self.user_activity_count.read(user);
            
            let activity = UserActivity {
                activity_id,
                user_address: user,
                activity_type,
                description,
                amount,
                group_id,
                timestamp: get_block_timestamp(),
                is_positive_amount: is_positive,
            };
            
            self.user_activities.write((user, user_activity_count), activity);
            self.user_activity_count.write(user, user_activity_count + 1);
            self.next_activity_id.write(activity_id + 1);
        }

        fn _calculate_next_payout_date(self: @ContractState, group_id: u256) -> u64 {
            let group_info = self.groups.read(group_id);
            // Simple calculation - add cycle_duration to last_payout_time or start_time
            if group_info.last_payout_time > 0 {
                group_info.last_payout_time + group_info.cycle_duration
            } else {
                group_info.start_time + group_info.cycle_duration
            }
        }

        fn _get_position_in_payout_queue(
            self: @ContractState, 
            group_id: u256, 
            user: ContractAddress
        ) -> u32 {
            let member_index = self.user_joined_groups.read((user, group_id));
            let group_info = self.groups.read(group_id);
            
            // Simple queue position based on join order and current cycle
            if member_index >= group_info.current_cycle.try_into().unwrap() {
                member_index - group_info.current_cycle.try_into().unwrap()
            } else {
                (group_info.member_limit - group_info.current_cycle.try_into().unwrap()) + member_index
            }
        }
    }
}