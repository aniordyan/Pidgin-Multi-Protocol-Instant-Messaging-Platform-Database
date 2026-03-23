# Pidgin-Multi-Protocol-Instant-Messaging-Platform-Database
(possible) Project for Database course

## Project Aim

Pidgin is a multi-protocol IM client that connects to multiple messaging networks (IRC, Jabber, AIM, MSN, etc.) simultaneously. Our database unifies user accounts, messages, contacts, and groups across all protocols in a single system. It supports messaging, group chats, file attachments, blocking, and activity analytics.

---

## Core Database Capabilities

| Capability | Description |
|-----------|-------------|
| **Multi-Protocol Accounts** | Users manage multiple protocol accounts (Jabber, AIM, IRC, Barev) |
| **Message Storage** | Store message history across all protocols |
| **Group Chats** | Create groups, manage members, store group messages |
| **Contacts** | Organize contacts into groups |
| **File Attachments** | Store files with messages |
| **User Presence** | Track online/away/idle/offline status |
| **Activity Tracking** | Log all user actions for compliance |
| **Statistics** | User engagement and group analytics |

---

## System Users

| User Type | What They Do |
|-----------|------------|
| **Regular Users** | Send/receive messages, manage contacts, create groups, set status |
| **Group Admins** | Create groups, invite members, manage permissions, remove members |
| **System Admins** | Monitor activity, manage database, troubleshoot issues |
| **Compliance Officers** | Review activity logs, investigate incidents, handle data requests |
| **Analysts** | Study messaging patterns, group engagement, user retention trends |

---

## Basic Operations

| Operation | Example |
|-----------|---------|
| Send 1:1 message | Alice sends "Hello Bob" via Jabber to Bob |
| Send group message | Post message to "Project Team" group chat |
| Create group | Create new group with 5 invited members |
| Add contact | Add Bob to contact list and "Friends" group |
| Block user | Block Dave from sending messages |
| Set status | Change status to "away - in meeting" |
| Upload file | Attach image to message |
| Search messages | Find all messages from Bob about "project" |
| Mark as read | Mark received message as read |
| Remove group member | Admin removes inactive member from group |

---

## Operation 1: Send 1:1 Message

**What happens**:
```
User sends message → Validate (recipient exists? not blocked?) 
→ Insert into database → Triggers fire (update stats, log activity) 
→ Message indexed and stored
```

**Consistency enforced**:
- Trigger prevents messaging if blocked
- Statistics auto-update (no manual count needed)
- Activity logged for audit trail
- Message indexed for search

---

## Operation 2: Create Group & Manage Members

**What happens**:
```
Admin creates group → System initializes with admin permissions 
→ Members invited → Members can post messages → Admin can remove members
```

**Process steps**:
1. Create group record (name, creator, type: public/private)
2. Add member records for each invited user
3. Automatically generate "group created" system message
4. Update group statistics (member count)
5. Log action in activity log

**Consistency enforced**:
- Only admin can remove members (permission check)
- Removed members can't post new messages
- Group members notified of changes
- All actions logged

---

## Operation 3: Block User

**What happens**:
```
User blocks → Insert block record → Trigger prevents future messaging 
→ Old messages hidden in UI (kept in database) → Action logged
```

**Process steps**:
1. Create block record (blocker, blocked user, date)
2. Trigger activates: any message from blocked user → REJECTED
3. Hide blocked user from contact list
4. Archive previous messages (not deleted)
5. Log blocking action

**Consistency enforced**:
- Blocked user's messages rejected before insert
- Block is reversible (not permanent)
- Evidence preserved (old messages kept)
- All blocking attempts logged

---

## Operation 4: Auto-Update Statistics

**What happens automatically**:
```
Message inserted → Triggers fire → Stats updated atomically 
→ User/group counts always accurate without slow queries
```

**What gets updated**:
- User's messages_sent count (+1)
- Recipient's messages_received count (+1)
- Group's total_messages count (+1)
- Last_activity timestamp
- Contact interaction count

**Consistency enforced**:
- Stats updated same moment as message insert
- If message fails, stats not updated
- Never out of sync with actual messages
- Queries run fast (read pre-calculated numbers)
---

## System Architecture

```
APPLICATION LAYER
↓ SQL Queries ↓
QUERY LAYER (SELECT, INSERT, UPDATE, DELETE)
↓ Validation ↓
CONSISTENCY LAYER (Triggers, Constraints, Foreign Keys)
↓ Storage ↓
DATA LAYER
├─ USERS (accounts)
├─ PROTOCOL_ACCOUNTS (Jabber, AIM, IRC credentials)
├─ MESSAGES (1:1 messages)
├─ GROUPS (group chats)
├─ GROUP_MEMBERS (group membership)
├─ CONTACTS (contact relationships)
├─ ATTACHMENTS (files)
├─ BLOCKED_USERS (blocks)
├─ USER_STATISTICS (aggregated stats)
├─ GROUP_STATISTICS (group stats)
├─ ACTIVITY_LOG (audit trail)
├─ READ_RECEIPTS (delivery tracking)
├─ MESSAGE_REACTIONS (emoji reactions)
├─ USER_STATUS (current presence)
└─ MESSAGE_EDITS (edit history)
↓
INDEXES (Fast lookups)
↓
PERSISTENCE (PostgreSQL Storage)
```

---

## Message Flow Diagram

```
Alice sends message to Bob:

[Validation]
├─ Does Bob exist? YES
├─ Is Bob blocked? NO
└─ Message text empty? NO

[Insert Message]
├─ sender_user_id = alice
├─ receiver_user_id = bob
├─ message_text = "Hello Bob"
├─ sent_timestamp = NOW()
└─ is_read = FALSE

[Triggers Fire]
├─ Trigger 1: Check blocking → Passed
├─ Trigger 2: Update stats (alice.sent+1, bob.received+1)
├─ Trigger 3: Log activity → "alice sent message to bob"
└─ Trigger 4: Create read_receipt entry

[Index & Commit]
├─ Add to full-text search index
├─ Add to sender/receiver index
└─ Save transaction

[Result]
└─ Message stored, indexed, stats updated, activity logged
```

---

## Data Consistency Features

| Feature | How It Works | Effect |
|---------|------------|--------|
| **Block Trigger** | Check: is receiver blocking sender? If YES → REJECT insert | Blocked users can't message |
| **Stats Trigger** | AUTO increment message counts on insert | Stats always accurate |
| **Activity Log Trigger** | AUTO insert into activity_log on every action | Complete audit trail |
| **FK Constraints** | Recipient must be existing user | Can't send to non-existent user |
| **Unique Constraints** | Each user has unique email | No duplicate accounts |
| **Check Constraints** | Status must be in ('online','away','offline','idle') | Only valid values allowed |

---

## Multi-Protocol Support

```
One User (alice@company.com):

Protocol Account 1: Jabber
└─ Username: alice@company.jabber.org
   Status: Connected

Protocol Account 2: AIM
└─ Username: AliceSM
   Status: Connected

Protocol Account 3: IRC
└─ Username: alice_dev
   Status: Disconnected

All messages stored in ONE database:
├─ Alice (Jabber) → Bob (Jabber)
├─ Alice (AIM) → Charlie (AIM)
└─ Alice (IRC) → #developers (Freenode)

Database stores all with: sender, receiver, protocol_type, message
```

---

## Entity Overview (Simplified)

```
USERS
  ↓ has many
  PROTOCOL_ACCOUNTS (Jabber, AIM, IRC...)
  
USERS
  ↓ sends/receives
  MESSAGES (1:1 chats)
  
USERS
  ↓ creates
  GROUPS
  ↓ has many
  GROUP_MEMBERS (M:N relationship)
  ↓
  USERS
  
USERS
  ↓ creates
  CONTACTS (friend relationships)
  ↓
  USERS

USERS
  ↓ blocks
  BLOCKED_USERS
  ↓
  USERS
```


---
<img width="4024" height="1916" alt="visual-0-1774254240125" src="https://github.com/user-attachments/assets/341e77e4-b1ec-46ce-a72e-f95c8f7f4d4f" />

<img width="2336" height="1004" alt="visual-0-1774254257475" src="https://github.com/user-attachments/assets/50b3fd31-3f04-43d3-bf9d-7de98b9cffb3" />

---

## ERD DIAGRAM

![User Messaging Protocol-2026-03-23-110620](https://github.com/user-attachments/assets/9f395709-292e-44c5-9a86-bfcdb0a8d965)


## Some links
https://pidgin.im/

https://github.com/norayr/barev-purple
