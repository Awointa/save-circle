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
    use save_circle::events::Events::{
        ContributionMade, FundsWithdrawn, GroupCreated, PayoutDistributed, UserJoinedGroup,
        UserRegistered, UsersInvited,
    };
    use save_circle::interfaces::Isavecircle::Isavecircle;
    use save_circle::structs::Structs::{GroupInfo, GroupMember, UserProfile, joined_group};
    use starknet::event::EventEmitter;
    use starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess, Vec,
    };
    use starknet::{
        ClassHash, ContractAddress, contract_address_const, get_block_timestamp, get_caller_address,
        get_contract_address,
    };
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
        >, // to help us track the next member index for each group
        group_lock: Map<
            (u256, ContractAddress), u256,
        >, // to track group lock amount per user per group
        locked_balance: Map<ContractAddress, u256>, // to track locked funds per user
        insurance_pool: Map<u256, u256>, // group_id -> pool_balance
        protocol_treasury: u256, // Accumulated protocol fees
        insurance_rate: u256, // 100 = 1%
        protocol_fee_rate: u256,
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
        FundsWithdrawn: FundsWithdrawn,
        ContributionMade: ContributionMade,
        PayoutDistributed: PayoutDistributed,
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
        self.insurance_rate.write(100);
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

        fn create_public_group(
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
            if !requires_lock {
                assert!(lock_type == LockType::None, "Lock type required when locking is enabled");
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

            // Calculate required lock amount based on lock type
            let lock_amount = match group_info.lock_type {
                LockType::Progressive => {
                    // Lock first contribution amount, rest will be locked progressively
                    group_info.contribution_amount
                },
                LockType::None => {
                    // No upfront locking required
                    0_u256
                },
            };

            // lets get member index
            let member_index = self.group_next_member_index.read(group_id);
            assert!(member_index <= group_info.member_limit, "Group is full");

            let group_member = GroupMember {
                user: caller,
                group_id,
                locked_amount: lock_amount,
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


        fn lock_liquidity(
            ref self: ContractState, token_address: ContractAddress, amount: u256, group_id: u256,
        ) -> bool {
            let caller = get_caller_address();

            // Check if contract is paused
            self.pausable.assert_not_paused();

            // validate inputs
            assert(amount > 0, 'Amount must be greater than 0');
            assert(group_id != 0, 'Group ID must be greater than 0');

            // check if group exists and is active
            let group_info = self.groups.read(group_id);
            assert(group_info.group_id != 0, 'Group does not exist');
            assert(
                group_info.state == GroupState::Active || group_info.state == GroupState::Created,
                'Group must be Active or Created',
            );

            // check if user has enough balance - this should check token balance, not locked
            // balance
            let token = IERC20Dispatcher { contract_address: token_address };
            let user_token_balance = token.balance_of(caller);
            assert(user_token_balance >= amount, 'Insufficient token balance');

            // transfer tokens from user to this contract

            let success = token.transfer_from(caller, get_contract_address(), amount);
            assert(success, 'Token transfer failed');

            // update the group lock storage using correct tuple access
            let current_group_lock = self.group_lock.read((group_id, caller));
            let new_group_lock = current_group_lock + amount;
            self.group_lock.write((group_id, caller), new_group_lock);

            // update user's total locked balance
            let current_locked = self.locked_balance.read(caller);
            self.locked_balance.write(caller, current_locked + amount);

            // Update user's total lock amount in profile
            let mut user_profile = self.user_profiles.read(caller);
            user_profile.total_lock_amount += amount;
            self.user_profiles.write(caller, user_profile);

            true
        }

        fn get_locked_balance(self: @ContractState, user: ContractAddress) -> u256 {
            self.locked_balance.read(user)
        }


        fn withdraw_locked(ref self: ContractState, group_id: u256) -> u256 {
            let caller = get_caller_address();
            let current_time = get_block_timestamp();

            // Check if contract is paused
            self.pausable.assert_not_paused();

            // Verify user is a member of this group
            assert(self._is_member(group_id, caller), 'User not member of this group');

            // Get group information
            let group_info = self.groups.read(group_id);
            assert(group_info.group_id != 0, 'Group does not exist');

            // Calculate cycle end time
            let cycle_duration_seconds = match group_info.cycle_unit {
                TimeUnit::Days => group_info.cycle_duration * 86400, // 24 * 60 * 60
                TimeUnit::Weeks => group_info.cycle_duration * 604800, // 7 * 24 * 60 * 60
                TimeUnit::Months => group_info.cycle_duration
                    * 2592000 // 30 * 24 * 60 * 60 (approximate)
            };
            let cycle_end_time = group_info.start_time + cycle_duration_seconds;

            // Ensure cycle has ended
            assert(current_time >= cycle_end_time, 'Group cycle has not ended yet');

            // Ensure group is in Completed state (all payouts distributed)
            assert(group_info.state == GroupState::Completed, 'Group cycle must be completed');

            // Get user's member information
            let member_index = self.user_joined_groups.read((caller, group_id));
            let mut group_member = self.group_members.read((group_id, member_index));

            // Check if user has locked funds to withdraw
            assert(group_member.locked_amount > 0, 'No locked funds to withdraw');

            // Check if user has already withdrawn (prevent double withdrawal)
            assert(!group_member.has_been_paid, 'Funds  already been withdrawn');

            // Calculate withdrawable amount (could include penalties for missed contributions)
            let withdrawable_amount = if self._has_completed_circle(caller, group_id) {
                // User completed all contributions - full withdrawal
                group_member.locked_amount
            } else {
                // User missed contributions - apply penalty
                let penalty = self._get_penalty_amount(caller, group_id);
                assert(group_member.locked_amount >= penalty, 'Penalty exceeds locked amount');
                group_member.locked_amount - penalty
            };

            // Transfer tokens back to user
            let payment_token = IERC20Dispatcher {
                contract_address: self.payment_token_address.read(),
            };
            let success = payment_token.transfer(caller, withdrawable_amount);
            assert(success, 'Token transfer failed');

            // Update user's locked balance
            let current_locked = self.locked_balance.read(caller);
            self.locked_balance.write(caller, current_locked - group_member.locked_amount);

            // Update user profile
            let mut user_profile = self.user_profiles.read(caller);
            user_profile.total_lock_amount -= group_member.locked_amount;
            self.user_profiles.write(caller, user_profile);

            // Update group member - mark as withdrawn
            group_member.locked_amount = 0;
            group_member.has_been_paid = true;
            self.group_members.write((group_id, member_index), group_member);

            // Update group lock storage
            self.group_lock.write((group_id, caller), 0);

            self.emit(FundsWithdrawn { group_id, user: caller, amount: withdrawable_amount });

            withdrawable_amount
        }

        fn get_penalty_locked(self: @ContractState, user: ContractAddress, group_id: u256) -> u256 {
            self._get_penalty_amount(user, group_id)
        }

        fn has_completed_circle(
            self: @ContractState, user: ContractAddress, group_id: u256,
        ) -> bool {
            self._has_completed_circle(user, group_id)
        }


        fn contribute(ref self: ContractState, group_id: u256) -> bool {
            let caller = get_caller_address();
            let current_time = get_block_timestamp();

            // Check if contract is paused
            self.pausable.assert_not_paused();

            // Verify user is a member of this group
            assert(self._is_member(group_id, caller), 'User not member of this group');

            // Get group information
            let group_info = self.groups.read(group_id);
            assert(group_info.group_id != 0, 'Group does not exist');
            assert(group_info.state == GroupState::Active, 'Group must be active');

            // Get user's member information
            let member_index = self.user_joined_groups.read((caller, group_id));
            let mut group_member = self.group_members.read((group_id, member_index));

            // Calculate total payment: contribution + 1% insurance fee
            let contribution_amount = group_info.contribution_amount;
            let insurance_rate = self.insurance_rate.read();
            let insurance_fee = (contribution_amount * insurance_rate)
                / 10000; // 1% = 100 basis points
            let total_payment = contribution_amount + insurance_fee;

            // Check if user has enough token balance
            let payment_token = IERC20Dispatcher {
                contract_address: self.payment_token_address.read(),
            };
            let user_balance = payment_token.balance_of(caller);
            assert(user_balance >= total_payment, 'Insufficient bal for contri');

            // Transfer total payment from user to contract
            let success = payment_token
                .transfer_from(caller, get_contract_address(), total_payment);
            assert(success, 'Contribution transfer failed');

            // Add insurance fee to group's insurance pool
            let current_pool = self.insurance_pool.read(group_id);
            self.insurance_pool.write(group_id, current_pool + insurance_fee);

            // Update member's contribution count
            group_member.contribution_count += 1;
            self.group_members.write((group_id, member_index), group_member);

            // Emit contribution event
            self
                .emit(
                    ContributionMade {
                        group_id,
                        user: caller,
                        contribution_amount,
                        insurance_fee,
                        total_paid: total_payment,
                    },
                );

            true
        }


        /// Get insurance pool balance for a specific group
        fn get_insurance_pool_balance(self: @ContractState, group_id: u256) -> u256 {
            self.insurance_pool.read(group_id)
        }

        /// Get protocol treasury balance
        fn get_protocol_treasury(self: @ContractState) -> u256 {
            self.protocol_treasury.read()
        }


        fn activate_group(ref self: ContractState, group_id: u256) -> bool {
            let caller = get_caller_address();

            // Check if contract is paused
            self.pausable.assert_not_paused();

            // Get group information
            let mut group_info = self.groups.read(group_id);
            assert(group_info.group_id != 0, 'Group does not exist');

            // Only group creator can activate the group
            assert(group_info.creator == caller, 'Only creator can activate group');

            // Group must be in Created state to be activated
            assert(group_info.state == GroupState::Created, 'Group must be in Created state');

            // Update group state to Active
            group_info.state = GroupState::Active;
            self.groups.write(group_id, group_info);

            true
        }


        /// Distribute payout to the next eligible member based on priority
        /// Priority: 1) Highest locked amount, 2) Earliest join time (tiebreaker)
        fn distribute_payout(ref self: ContractState, group_id: u256) -> bool {
            let caller = get_caller_address();

            // Check if contract is paused
            self.pausable.assert_not_paused();

            // Get group information
            let mut group_info = self.groups.read(group_id);
            assert(group_info.group_id != 0, 'Group does not exist');
            assert(group_info.state == GroupState::Active, 'Group must be active');

            // Only group creator or admin can distribute payouts
            assert(
                group_info.creator == caller
                    || self.accesscontrol.has_role(DEFAULT_ADMIN_ROLE, caller),
                'Only creator  can distribute',
            );

            // Check if there are contributions to distribute
            let total_contributions = self._calculate_total_contributions(group_id);
            assert(total_contributions > 0, 'No contributions to distribute');

            // Find next eligible member for payout
            let next_recipient = self._get_next_payout_recipient(group_id);
            assert(
                next_recipient.user != contract_address_const::<0>(), 'No eligible recipient found',
            );

            // Calculate payout amount (total contributions minus insurance fees already deducted)
            let payout_amount = total_contributions;

            // Transfer payout to recipient
            let payment_token = IERC20Dispatcher {
                contract_address: self.payment_token_address.read(),
            };
            let success = payment_token.transfer(next_recipient.user, payout_amount);
            assert(success, 'Payout transfer failed');

            // Update recipient's payout status
            let mut updated_member = next_recipient;
            updated_member.has_been_paid = true;
            updated_member.payout_cycle = group_info.current_cycle.try_into().unwrap() + 1;
            self.group_members.write((group_id, updated_member.member_index), updated_member);

            // Update group cycle information
            group_info.current_cycle += 1;
            group_info.payout_order += 1;

            // Check if all members have been paid (cycle complete)
            if group_info.payout_order >= group_info.members {
                group_info.state = GroupState::Completed;
            }

            self.groups.write(group_id, group_info);

            // Emit payout event
            self
                .emit(
                    PayoutDistributed {
                        group_id,
                        recipient: next_recipient.user,
                        amount: payout_amount,
                        cycle: group_info.current_cycle,
                    },
                );

            true
        }

        /// Get the next member who should receive payout based on priority
        fn get_next_payout_recipient(self: @ContractState, group_id: u256) -> GroupMember {
            self._get_next_payout_recipient(group_id)
        }

        /// Get payout order for all members in a group (simplified version)
        fn get_payout_order(self: @ContractState, group_id: u256) -> Array<ContractAddress> {
            let group_info = self.groups.read(group_id);
            assert(group_info.group_id != 0, 'Group does not exist');

            let mut payout_order = array![];

            // Simple approach: find members in priority order one by one
            let mut remaining_members = group_info.members;
            let mut processed = array![];

            while remaining_members > 0 {
                let mut best_member = GroupMember {
                    user: contract_address_const::<0>(),
                    group_id: 0,
                    locked_amount: 0,
                    joined_at: 0,
                    member_index: 0,
                    payout_cycle: 0,
                    has_been_paid: false,
                    contribution_count: 0,
                    late_contributions: 0,
                    missed_contributions: 0,
                };
                let mut found = false;

                let mut i = 0;
                while i < group_info.members {
                    let member = self.group_members.read((group_id, i));
                    if member.user != contract_address_const::<0>()
                        && !self._is_processed(@processed, member.member_index) {
                        if !found {
                            best_member = member;
                            found = true;
                        } else {
                            // Compare priority: higher locked amount wins, then earlier join time
                            if member.locked_amount > best_member.locked_amount {
                                best_member = member;
                            } else if member.locked_amount == best_member.locked_amount {
                                if member.joined_at < best_member.joined_at {
                                    best_member = member;
                                }
                            }
                        }
                    }
                    i += 1;
                }

                if found {
                    payout_order.append(best_member.user);
                    processed.append(best_member.member_index);
                    remaining_members -= 1;
                } else {
                    break;
                }
            }

            payout_order
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


        fn _has_completed_circle(
            self: @ContractState, user: ContractAddress, group_id: u256,
        ) -> bool {
            let member_index = self.user_joined_groups.read((user, group_id));
            let group_member = self.group_members.read((group_id, member_index));
            let group_info = self.groups.read(group_id);

            group_member.missed_contributions == 0
        }

        fn _get_penalty_amount(
            self: @ContractState, user: ContractAddress, group_id: u256,
        ) -> u256 {
            let member_index = self.user_joined_groups.read((user, group_id));
            let group_member = self.group_members.read((group_id, member_index));
            let group_info = self.groups.read(group_id);

            // Calculate penalty based on missed contributions
            // Penalty = missed_contributions * contribution_amount * penalty_rate
            // For simplicity, let's use a 10% penalty per missed contribution
            let penalty_rate = 10; // 10% penalty per missed contribution
            let base_penalty = group_member.missed_contributions.into()
                * group_info.contribution_amount;
            let total_penalty = (base_penalty * penalty_rate.into()) / 100_u256;

            // Ensure penalty doesn't exceed locked amount
            let max_penalty = group_member.locked_amount;
            if total_penalty > max_penalty {
                max_penalty
            } else {
                total_penalty
            }
        }


        fn _get_next_payout_recipient(self: @ContractState, group_id: u256) -> GroupMember {
            let group_info = self.groups.read(group_id);
            let mut best_member = GroupMember {
                user: contract_address_const::<0>(),
                group_id: 0,
                locked_amount: 0,
                joined_at: 0,
                member_index: 0,
                payout_cycle: 0,
                has_been_paid: false,
                contribution_count: 0,
                late_contributions: 0,
                missed_contributions: 0,
            };
            let mut found_eligible = false;

            let mut i = 0;
            while i < group_info.members {
                let member = self.group_members.read((group_id, i));
                if member.user != contract_address_const::<0>() && !member.has_been_paid {
                    if !found_eligible {
                        best_member = member;
                        found_eligible = true;
                    } else {
                        // Compare priority: higher locked amount wins, then earlier join time
                        if member.locked_amount > best_member.locked_amount {
                            best_member = member;
                        } else if member.locked_amount == best_member.locked_amount {
                            if member.joined_at < best_member.joined_at {
                                best_member = member;
                            }
                        }
                    }
                }
                i += 1;
            }

            assert(found_eligible, 'No eligible member found');
            best_member
        }

        fn _sort_members_by_priority(
            self: @ContractState, mut members: Array<GroupMember>,
        ) -> Array<GroupMember> {
            let len = members.len();
            if len <= 1 {
                return members;
            }

            // Simple bubble sort implementation for Cairo arrays
            let mut i = 0;
            while i < len {
                let mut j = 0;
                while j < len - 1 - i {
                    let member_j = *members.at(j);
                    let member_j_plus_1 = *members.at(j + 1);

                    // Compare: higher locked amount first, then earlier join time
                    let should_swap = if member_j.locked_amount < member_j_plus_1.locked_amount {
                        true
                    } else if member_j.locked_amount == member_j_plus_1.locked_amount {
                        member_j.joined_at > member_j_plus_1.joined_at
                    } else {
                        false
                    };

                    if should_swap {
                        // Swap elements by creating new array
                        let mut new_members = array![];
                        let mut k = 0;
                        while k < len {
                            if k == j {
                                new_members.append(member_j_plus_1);
                            } else if k == j + 1 {
                                new_members.append(member_j);
                            } else {
                                new_members.append(*members.at(k));
                            }
                            k += 1;
                        }
                        members = new_members;
                    }
                    j += 1;
                }
                i += 1;
            }

            members
        }


        fn _calculate_total_contributions(self: @ContractState, group_id: u256) -> u256 {
            let group_info = self.groups.read(group_id);
            assert(group_info.group_id != 0, 'Group does not exist');

            let mut total_contributions = 0_u256;
            let mut member_index = 0_u32;

            // Iterate through all members in the group
            loop {
                if member_index >= group_info.members {
                    break;
                }

                let group_member = self.group_members.read((group_id, member_index));

                // Calculate this member's total contributions
                // contribution_count * contribution_amount per cycle
                let member_contributions = group_member.contribution_count.into()
                    * group_info.contribution_amount;
                total_contributions += member_contributions;

                member_index += 1;
            }

            total_contributions
        }


        fn _is_processed(self: @ContractState, processed: @Array<u32>, member_index: u32) -> bool {
            let mut i = 0;
            let len = processed.len();
            while i < len {
                if *processed.at(i) == member_index {
                    return true;
                }
                i += 1;
            }
            false
        }
    }
}

