
---

## 🧱 Core Functional Modules

### 1. 🏗️ Group Creation & Management

#### ✅ `create_group`

* Creates a new savings group.
* Stores:

  * Group name
  * Weekly contribution amount
  * Max number of members
  * Group duration
  * Creator address
  * Payout method (manual or random)
  * Token used (ERC20 address)

#### ✅ `get_group(group_id)`

* Returns group metadata like:

  * Name, creator
  * Members
  * Contribution settings
  * Current round and payout schedule

#### ✅ `get_members(group_id)`

* Returns a list of wallet addresses of all group members.

---

### 2. 👥 Member Management

#### ✅ `join_group(group_id, amount)`

* Checks if group is not full.
* Verifies `amount == weekly_amount * N` (where N = number of weeks you want to lock).
* Transfers the required tokens from the user to the contract.
* Stores locked funds for the user.
* Adds the user to the group's member list.
* Records participation start week.

#### ✅ `lock_liquidity(user, amount)`

* Called within `join_group`.
* Transfers `amount` of ERC20 tokens from the user to the contract.
* Stores in `locked_balance[user]`.

---

### 3. 💸 Weekly Contributions

#### ✅ `contribute(group_id)`

* Allows contribution only during the current week.
* Checks if user has enough locked funds.
* Deducts `weekly_amount` from the user's locked balance.
* Marks the user as "contributed" for the current week in storage.

---

### 4. 🔁 Rotating Payout System

#### ✅ `distribute_payout(group_id)`

* Can be triggered after all members contribute for a week.
* Sends the total pot to the next eligible recipient.
* Updates internal pointer to track who gets paid next.
* Marks recipient as "paid".

#### ✅ `get_next_recipient(group_id)`

* Returns the wallet address of the member scheduled to receive the next payout.

---

### 5. 📉 Reputation System

#### ✅ `report_default(group_id, user)`

* Called by group members or contract automatically.
* If user fails to contribute during a week:

  * Marks them as defaulted.
  * Decreases their reputation score.

#### ✅ `mark_late(group_id, user)`

* Marks user as having made a **late payment**.
* Reduces reputation slightly, but not as harshly as a full default.

#### ✅ `get_reputation(user)`

* Returns the current reputation score for a user.
* Based on history of:

  * Timely payments
  * Late payments
  * Missed contributions

---

### 6. 🔓 Fund Management

#### ✅ `withdraw_locked(group_id)`

* Only allowed **after the group cycle ends**.
* Calculates remaining locked balance.
* Transfers unused funds back to the user.



fn lock_liquidity


---


