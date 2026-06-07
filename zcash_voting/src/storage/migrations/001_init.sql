CREATE TABLE rounds (
    round_id            TEXT NOT NULL,
    wallet_id           TEXT NOT NULL DEFAULT '',
    snapshot_height     INTEGER NOT NULL,
    ea_pk               BLOB NOT NULL,
    nc_root             BLOB NOT NULL,
    nullifier_imt_root  BLOB NOT NULL,
    session_json        TEXT,
    phase               INTEGER NOT NULL DEFAULT 0,
    created_at          INTEGER NOT NULL,
    PRIMARY KEY (round_id, wallet_id)
);

CREATE TABLE bundles (
    round_id            TEXT NOT NULL,
    wallet_id           TEXT NOT NULL DEFAULT '',
    bundle_index        INTEGER NOT NULL,
    note_positions_blob BLOB,
    note_identity_hashes_blob BLOB,
    van_comm_rand       BLOB,
    dummy_nullifiers    BLOB,
    rho_signed          BLOB,
    padded_note_data    BLOB,
    nf_signed           BLOB,
    cmx_new             BLOB,
    alpha               BLOB,
    rseed_signed        BLOB,
    rseed_output        BLOB,
    gov_comm            BLOB,
    total_note_value    INTEGER,
    address_index       INTEGER,
    van_leaf_position   INTEGER,
    rk                  BLOB,
    gov_nullifiers_blob BLOB,
    padded_note_secrets BLOB,
    pczt_sighash        BLOB,
    delegation_tx_hash  TEXT,
    PRIMARY KEY (round_id, wallet_id, bundle_index),
    FOREIGN KEY (round_id, wallet_id) REFERENCES rounds(round_id, wallet_id) ON DELETE CASCADE
);

CREATE TABLE cached_tree_state (
    round_id        TEXT NOT NULL,
    wallet_id       TEXT NOT NULL DEFAULT '',
    snapshot_height INTEGER NOT NULL,
    tree_state      BLOB NOT NULL,
    PRIMARY KEY (round_id, wallet_id),
    FOREIGN KEY (round_id, wallet_id) REFERENCES rounds(round_id, wallet_id) ON DELETE CASCADE
);

CREATE TABLE proofs (
    round_id      TEXT NOT NULL,
    wallet_id     TEXT NOT NULL DEFAULT '',
    bundle_index  INTEGER NOT NULL,
    witness       BLOB,
    proof         BLOB,
    success       INTEGER NOT NULL DEFAULT 0,
    created_at    INTEGER NOT NULL,
    PRIMARY KEY (round_id, wallet_id, bundle_index),
    FOREIGN KEY (round_id, wallet_id, bundle_index) REFERENCES bundles(round_id, wallet_id, bundle_index) ON DELETE CASCADE
);

CREATE TABLE witnesses (
    round_id        TEXT NOT NULL,
    wallet_id       TEXT NOT NULL DEFAULT '',
    bundle_index    INTEGER NOT NULL,
    note_position   INTEGER NOT NULL,
    note_commitment BLOB NOT NULL,
    root            BLOB NOT NULL,
    auth_path       BLOB NOT NULL,
    created_at      INTEGER NOT NULL,
    PRIMARY KEY (round_id, wallet_id, bundle_index, note_position),
    FOREIGN KEY (round_id, wallet_id, bundle_index) REFERENCES bundles(round_id, wallet_id, bundle_index) ON DELETE CASCADE
);

CREATE TABLE imt_proofs (
    round_id       TEXT NOT NULL,
    wallet_id      TEXT NOT NULL DEFAULT '',
    bundle_index   INTEGER NOT NULL,
    nullifier      BLOB NOT NULL,
    root           BLOB NOT NULL,
    nf_bounds      BLOB NOT NULL,
    leaf_pos       INTEGER NOT NULL,
    path           BLOB NOT NULL,
    created_at     INTEGER NOT NULL,
    PRIMARY KEY (round_id, wallet_id, bundle_index, nullifier),
    FOREIGN KEY (round_id, wallet_id, bundle_index) REFERENCES bundles(round_id, wallet_id, bundle_index) ON DELETE CASCADE
);

CREATE TABLE votes (
    id              INTEGER PRIMARY KEY,
    round_id        TEXT NOT NULL,
    wallet_id       TEXT NOT NULL DEFAULT '',
    bundle_index    INTEGER NOT NULL,
    proposal_id     INTEGER NOT NULL,
    choice          INTEGER NOT NULL,
    commitment      BLOB,
    created_at      INTEGER NOT NULL,
    tx_hash                 TEXT,
    vc_tree_position        INTEGER,
    commitment_bundle_json  TEXT,
    UNIQUE(round_id, wallet_id, bundle_index, proposal_id),
    FOREIGN KEY (round_id, wallet_id, bundle_index) REFERENCES bundles(round_id, wallet_id, bundle_index) ON DELETE CASCADE
);

CREATE TABLE share_delegations (
    round_id        TEXT NOT NULL,
    wallet_id       TEXT NOT NULL DEFAULT '',
    bundle_index    INTEGER NOT NULL,
    proposal_id     INTEGER NOT NULL,
    share_index     INTEGER NOT NULL,
    sent_to_urls    TEXT NOT NULL,
    nullifier       BLOB NOT NULL,
    confirmed       INTEGER NOT NULL DEFAULT 0,
    submit_at       INTEGER NOT NULL DEFAULT 0,
    created_at      INTEGER NOT NULL,
    PRIMARY KEY (round_id, wallet_id, bundle_index, proposal_id, share_index),
    FOREIGN KEY (round_id, wallet_id, bundle_index)
        REFERENCES bundles(round_id, wallet_id, bundle_index) ON DELETE CASCADE
);

CREATE TABLE keystone_signatures (
    round_id        TEXT NOT NULL,
    wallet_id       TEXT NOT NULL DEFAULT '',
    bundle_index    INTEGER NOT NULL,
    sig             BLOB NOT NULL,
    sighash         BLOB NOT NULL,
    rk              BLOB NOT NULL,
    created_at      INTEGER NOT NULL,
    PRIMARY KEY (round_id, wallet_id, bundle_index),
    FOREIGN KEY (round_id, wallet_id, bundle_index)
        REFERENCES bundles(round_id, wallet_id, bundle_index) ON DELETE CASCADE
);

CREATE TABLE ballot_intent (
    round_id     TEXT NOT NULL,
    wallet_id    TEXT NOT NULL DEFAULT '',
    proposal_id  INTEGER NOT NULL,
    skipped      INTEGER NOT NULL DEFAULT 0,  -- 1 = intentionally skipped
    choice       INTEGER,                     -- 0-indexed option; NULL iff skipped
    created_at   INTEGER NOT NULL,
    updated_at   INTEGER NOT NULL,
    PRIMARY KEY (round_id, wallet_id, proposal_id),
    FOREIGN KEY (round_id, wallet_id) REFERENCES rounds(round_id, wallet_id) ON DELETE CASCADE,
    CHECK ((skipped = 1 AND choice IS NULL) OR (skipped = 0 AND choice IS NOT NULL))
);
