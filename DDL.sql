-- =============================================================================
-- Pidgin Multi-Protocol Instant Messaging Platform
-- DDL Script - Database Schema
-- =============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; -- generating IDs
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- for full-text search on messages

-- =============================================================================
-- 1. PROTOCOLS
-- =============================================================================
CREATE TABLE protocols (
    protocol_id   SERIAL       PRIMARY KEY,
    name          VARCHAR(50)  NOT NULL UNIQUE,
    default_port  INT,
    is_custom     BOOLEAN      NOT NULL DEFAULT FALSE,
    supports_public_groups BOOLEAN NOT NULL DEFAULT FALSE
);

-- =============================================================================
-- 2. STATUS_TYPES
-- =============================================================================
CREATE TABLE status_types (
    status_type_id  SERIAL       PRIMARY KEY,
    name            VARCHAR(30)  NOT NULL UNIQUE,
    icon            VARCHAR(100)
);

-- =============================================================================
-- 3. USERS
-- =============================================================================
CREATE TABLE users (
    user_id       UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_date  TIMESTAMP    NOT NULL DEFAULT NOW(),
    last_login    TIMESTAMP,
    is_deleted    BOOLEAN      NOT NULL DEFAULT FALSE
);

-- =============================================================================
-- 4. PROTOCOL_ACCOUNTS
-- =============================================================================
CREATE TABLE protocol_accounts (
    account_id                   UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                      UUID         NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    protocol_id                  INT          NOT NULL REFERENCES protocols(protocol_id),
    status_type_id               INT          REFERENCES status_types(status_type_id),
    protocol_username            VARCHAR(150) NOT NULL,
    protocol_password_encrypted  VARCHAR(512),
    protocol_server              VARCHAR(255),
    protocol_port                INT,
    status_message               TEXT,
    avatar_path                  VARCHAR(500),
    last_connected               TIMESTAMP,
    connection_error             VARCHAR(500),
    created_date                 TIMESTAMP    NOT NULL DEFAULT NOW(),
    UNIQUE (protocol_id, protocol_username, protocol_server)
);

-- =============================================================================
-- 5. CONTACTS
-- =============================================================================
CREATE TABLE contacts (
    contact_id                UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id                UUID         NOT NULL REFERENCES protocol_accounts(account_id) ON DELETE CASCADE,
    contact_protocol_username VARCHAR(150) NOT NULL
);

-- =============================================================================
-- 6. CONTACT_GROUPS
-- =============================================================================
CREATE TABLE contact_groups (
    cg_id          UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    contact_id     UUID         NOT NULL REFERENCES contacts(contact_id) ON DELETE CASCADE,
    group_name     VARCHAR(100) NOT NULL,
    created_date   TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 7. BLOCKED_USERS
-- =============================================================================
CREATE TABLE blocked_users (
    block_id            UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id          UUID         NOT NULL REFERENCES protocol_accounts(account_id) ON DELETE CASCADE, -- blocker
    blocked_account_id  UUID         NOT NULL REFERENCES protocol_accounts(account_id) ON DELETE CASCADE, -- blocked
    blocked_username    VARCHAR(150) NOT NULL,
    block_date          TIMESTAMP    NOT NULL DEFAULT NOW(),
    UNIQUE (account_id, blocked_account_id)
);

-- =============================================================================
-- 8. MESSAGES  (1:1 direct messages)
-- =============================================================================
CREATE TABLE messages (
    message_id          BIGSERIAL    PRIMARY KEY,
    sender_account_id   UUID         NOT NULL REFERENCES protocol_accounts(account_id),
    receiver_account_id UUID         NOT NULL REFERENCES protocol_accounts(account_id),
    message_text        TEXT,
    protocol_type       VARCHAR(50),
    is_read             BOOLEAN      NOT NULL DEFAULT FALSE,
    read_timestamp      TIMESTAMP,
    is_edited           BOOLEAN      NOT NULL DEFAULT FALSE,
    edited_timestamp    TIMESTAMP,
    is_deleted          BOOLEAN      NOT NULL DEFAULT FALSE,
    sent_timestamp      TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT no_self_message CHECK (sender_account_id <> receiver_account_id)
);

-- =============================================================================
-- 9. READ_RECEIPTS
-- =============================================================================
CREATE TABLE read_receipts (
    receipt_id      UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id      BIGINT    NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE,
    read_by_account_id UUID      NOT NULL REFERENCES protocol_accounts(account_id) ON DELETE CASCADE,
    read_timestamp  TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (message_id, read_by_account_id)
);

-- =============================================================================
-- 10. ATTACHMENTS
-- Metadata-only (no BLOBs). Files are stored on disk; path recorded here.
-- =============================================================================
CREATE TABLE attachments (
    attachment_id    UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id       BIGINT       NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE,
    filename         VARCHAR(300) NOT NULL,
    file_size_bytes  BIGINT,
    file_type        VARCHAR(100),
    storage_path     VARCHAR(500) NOT NULL,
    download_count   INT          NOT NULL DEFAULT 0,
    upload_date      TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 11. MESSAGE_REACTIONS
-- =============================================================================
CREATE TABLE message_reactions (
    reaction_id    UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id     BIGINT    NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE,
    user_id        UUID      NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    emoji          VARCHAR(20) NOT NULL,
    reaction_date  TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (message_id, user_id, emoji)
);

-- =============================================================================
-- 12. GROUPS  (group chats / chatrooms)
-- =============================================================================
CREATE TABLE groups (
    group_id       UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    creator_user_id UUID        NOT NULL REFERENCES users(user_id),
    protocol_id    INT          NOT NULL REFERENCES protocols(protocol_id),
    group_name     VARCHAR(150) NOT NULL,
    group_type     VARCHAR(20)  NOT NULL DEFAULT 'public'
                   CHECK (group_type IN ('public', 'private')),
    group_topic    TEXT,
    max_members    INT,
    is_invite_only BOOLEAN      NOT NULL DEFAULT FALSE,
    icon_url       VARCHAR(500),
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    is_archived    BOOLEAN      NOT NULL DEFAULT FALSE,
    created_date   TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION enforce_public_group_protocol_support()
RETURNS TRIGGER AS $$
DECLARE
    protocol_allows_public BOOLEAN;
BEGIN
    SELECT supports_public_groups
    INTO protocol_allows_public
    FROM protocols
    WHERE protocol_id = NEW.protocol_id;

    IF NEW.group_type = 'public' AND COALESCE(protocol_allows_public, FALSE) = FALSE THEN
        RAISE EXCEPTION 'Protocol % does not support public groups', NEW.protocol_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_enforce_public_group_protocol_support
BEFORE INSERT OR UPDATE OF group_type, protocol_id ON groups
FOR EACH ROW
EXECUTE FUNCTION enforce_public_group_protocol_support();

-- =============================================================================
-- 13. GROUP_MEMBERS
-- =============================================================================
CREATE TABLE group_members (
    member_id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id            UUID        NOT NULL REFERENCES groups(group_id) ON DELETE CASCADE,
    account_id          UUID        NOT NULL REFERENCES protocol_accounts(account_id) ON DELETE CASCADE,
    member_role         VARCHAR(20) NOT NULL DEFAULT 'member'
                        CHECK (member_role IN ('admin', 'moderator', 'member')),
    can_invite          BOOLEAN     NOT NULL DEFAULT FALSE,
    can_post            BOOLEAN     NOT NULL DEFAULT TRUE,
    can_delete_messages BOOLEAN     NOT NULL DEFAULT FALSE,
    join_date           TIMESTAMP   NOT NULL DEFAULT NOW(),
    member_since        TIMESTAMP   NOT NULL DEFAULT NOW(),
    UNIQUE (group_id, account_id)
);

-- =============================================================================
-- 14. GROUP_MESSAGES
-- =============================================================================
CREATE TABLE group_messages (
    msg_id             BIGSERIAL    PRIMARY KEY,
    group_id           UUID         NOT NULL REFERENCES groups(group_id) ON DELETE CASCADE,
    sender_account_id  UUID         NOT NULL REFERENCES protocol_accounts(account_id),
    message_text       TEXT,
    message_type       VARCHAR(30)  NOT NULL DEFAULT 'text'
                       CHECK (message_type IN ('text', 'file')),
    is_edited          BOOLEAN      NOT NULL DEFAULT FALSE,
    edited_by_user_id  UUID         REFERENCES users(user_id),
    edited_timestamp   TIMESTAMP,
    sent_timestamp     TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 15. USER_STATISTICS
-- =============================================================================
CREATE TABLE user_statistics (
    stat_id                        UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                        UUID      NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    protocol_accounts_count        INT       NOT NULL DEFAULT 0,
    messages_sent_count            INT       NOT NULL DEFAULT 0,
    messages_received_count        INT       NOT NULL DEFAULT 0,
    group_messages_sent_count      INT       NOT NULL DEFAULT 0,
    contacts_count                 INT       NOT NULL DEFAULT 0,
    groups_joined_count            INT       NOT NULL DEFAULT 0,
    blocked_count                  INT       NOT NULL DEFAULT 0,
    blocked_by_count               INT       NOT NULL DEFAULT 0,
    total_attachments_uploaded     INT       NOT NULL DEFAULT 0,
    total_attachments_size_bytes   BIGINT    NOT NULL DEFAULT 0,
    total_online_seconds           BIGINT    NOT NULL DEFAULT 0,
    last_message_sent_timestamp    TIMESTAMP,
    last_message_received_timestamp TIMESTAMP,
    last_updated                   TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 16. GROUP_STATISTICS
-- =============================================================================
CREATE TABLE group_statistics (
    gstat_id                    UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id                    UUID      NOT NULL UNIQUE REFERENCES groups(group_id) ON DELETE CASCADE,
    total_messages_count        INT       NOT NULL DEFAULT 0,
    member_count                INT       NOT NULL DEFAULT 0,
    total_attachments_uploaded  INT       NOT NULL DEFAULT 0,
    total_attachments_size_bytes BIGINT   NOT NULL DEFAULT 0,
    average_messages_per_day    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    most_active_member_user_id  UUID      REFERENCES users(user_id),
    last_message_timestamp      TIMESTAMP,
    last_updated                TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 17. ACTIVITY_LOG
-- =============================================================================
CREATE TABLE activity_log (
    log_id             BIGSERIAL    PRIMARY KEY,
    account_id         UUID         NOT NULL REFERENCES protocol_accounts(account_id),
    target_account_id  UUID         REFERENCES protocol_accounts(account_id),
    target_group_id    UUID         REFERENCES groups(group_id),
    target_message_id  BIGINT       REFERENCES messages(message_id),
    action_type        VARCHAR(60)  NOT NULL,
    device_type        VARCHAR(50),
    user_agent         VARCHAR(300),
    status             VARCHAR(20)  NOT NULL DEFAULT 'success'
                       CHECK (status IN ('success', 'failed')),
    error_message      VARCHAR(500),
    details            JSONB,
    action_timestamp   TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT activity_log_has_target CHECK (
        target_account_id IS NOT NULL OR
        target_group_id IS NOT NULL OR
        target_message_id IS NOT NULL
    )
);

-- =============================================================================
-- Protocols and status types
-- =============================================================================
INSERT INTO protocols (name, default_port, is_custom, supports_public_groups) VALUES
    ('XMPP/Jabber', 5222, FALSE, TRUE),
    ('IRC',         6667, FALSE, TRUE),
    ('AIM',         5190, FALSE, FALSE),
    ('MSN',         1863, FALSE, FALSE),
    ('ICQ',         5190, FALSE, FALSE),
    ('Barev',       7000, TRUE, FALSE);

INSERT INTO status_types (name, icon) VALUES
    ('online',       'green_dot'),
    ('away',         'yellow_dot'),
    ('idle',         'orange_dot'),
    ('do_not_disturb','red_dot'),
    ('offline',      'grey_dot'),
    ('invisible',    'hollow_dot');
