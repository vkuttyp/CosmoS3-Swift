-- CosmoS3 schema for SQLite
-- Tables use the s3_ prefix (SQLite has no schema/namespace support).
-- Run once against the target database file.

CREATE TABLE IF NOT EXISTS s3_users (
    id         INTEGER      PRIMARY KEY AUTOINCREMENT,
    guid       TEXT         NOT NULL UNIQUE,
    name       TEXT         NOT NULL,
    email      TEXT         NOT NULL UNIQUE,
    createdutc TEXT         NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS s3_credentials (
    id          INTEGER  PRIMARY KEY AUTOINCREMENT,
    guid        TEXT     NOT NULL UNIQUE,
    userguid    TEXT     NOT NULL,
    description TEXT,
    accesskey   TEXT     NOT NULL UNIQUE,
    secretkey   TEXT     NOT NULL,
    isbase64    INTEGER  NOT NULL DEFAULT 0,
    createdutc  TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS s3_buckets (
    id                INTEGER  PRIMARY KEY AUTOINCREMENT,
    guid              TEXT     NOT NULL UNIQUE,
    ownerguid         TEXT     NOT NULL,
    name              TEXT     NOT NULL UNIQUE,
    regionstring      TEXT     NOT NULL DEFAULT 'us-west-1',
    storagetype       TEXT     NOT NULL DEFAULT 'Disk',
    diskdirectory     TEXT     NOT NULL,
    enableversioning  INTEGER  NOT NULL DEFAULT 0,
    enablepublicwrite INTEGER  NOT NULL DEFAULT 0,
    enablepublicread  INTEGER  NOT NULL DEFAULT 0,
    createdutc        TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS s3_objects (
    id            INTEGER  PRIMARY KEY AUTOINCREMENT,
    guid          TEXT     NOT NULL UNIQUE,
    bucketguid    TEXT     NOT NULL,
    ownerguid     TEXT     NOT NULL,
    authorguid    TEXT     NOT NULL,
    objectkey           TEXT     NOT NULL,
    contenttype   TEXT,
    contentlength INTEGER  NOT NULL DEFAULT 0,
    version       INTEGER  NOT NULL DEFAULT 1,
    etag          TEXT,
    retention     TEXT     NOT NULL DEFAULT 'NONE',
    blobfilename  TEXT     NOT NULL,
    isfolder      INTEGER  NOT NULL DEFAULT 0,
    deletemarker  INTEGER  NOT NULL DEFAULT 0,
    md5           TEXT,
    metadata      TEXT,
    expirationutc TEXT,
    createdutc    TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    lastupdateutc TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    lastaccessutc TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS s3_buckettags (
    id         INTEGER  PRIMARY KEY AUTOINCREMENT,
    guid       TEXT     NOT NULL UNIQUE,
    bucketguid TEXT     NOT NULL,
    tagkey     TEXT     NOT NULL,
    tagvalue   TEXT,
    createdutc TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS s3_objecttags (
    id         INTEGER  PRIMARY KEY AUTOINCREMENT,
    guid       TEXT     NOT NULL UNIQUE,
    bucketguid TEXT     NOT NULL,
    objectguid TEXT     NOT NULL,
    tagkey     TEXT     NOT NULL,
    tagvalue   TEXT,
    createdutc TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS s3_bucketacls (
    id                INTEGER  PRIMARY KEY AUTOINCREMENT,
    guid              TEXT     NOT NULL UNIQUE,
    usergroup         TEXT,
    bucketguid        TEXT     NOT NULL,
    userguid          TEXT,
    issuedbyuserguid  TEXT,
    permitread        INTEGER  NOT NULL DEFAULT 0,
    permitwrite       INTEGER  NOT NULL DEFAULT 0,
    permitreadacp     INTEGER  NOT NULL DEFAULT 0,
    permitwriteacp    INTEGER  NOT NULL DEFAULT 0,
    permitfullcontrol INTEGER  NOT NULL DEFAULT 0,
    createdutc        TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS s3_objectacls (
    id                INTEGER  PRIMARY KEY AUTOINCREMENT,
    guid              TEXT     NOT NULL UNIQUE,
    usergroup         TEXT,
    userguid          TEXT,
    issuedbyuserguid  TEXT,
    bucketguid        TEXT     NOT NULL,
    objectguid        TEXT     NOT NULL,
    permitread        INTEGER  NOT NULL DEFAULT 0,
    permitwrite       INTEGER  NOT NULL DEFAULT 0,
    permitreadacp     INTEGER  NOT NULL DEFAULT 0,
    permitwriteacp    INTEGER  NOT NULL DEFAULT 0,
    permitfullcontrol INTEGER  NOT NULL DEFAULT 0,
    createdutc        TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS s3_uploads (
    id            INTEGER  PRIMARY KEY AUTOINCREMENT,
    guid          TEXT     NOT NULL UNIQUE,
    bucketguid    TEXT     NOT NULL,
    ownerguid     TEXT     NOT NULL,
    authorguid    TEXT     NOT NULL,
    objectkey           TEXT     NOT NULL,
    createdutc    TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    lastaccessutc TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    expirationutc TEXT     NOT NULL,
    contenttype   TEXT,
    metadata      TEXT
);

CREATE TABLE IF NOT EXISTS s3_uploadparts (
    id            INTEGER  PRIMARY KEY AUTOINCREMENT,
    guid          TEXT     NOT NULL UNIQUE,
    bucketguid    TEXT     NOT NULL,
    ownerguid     TEXT     NOT NULL,
    uploadguid    TEXT     NOT NULL,
    partnumber    INTEGER  NOT NULL,
    partlength    INTEGER  NOT NULL DEFAULT 0,
    md5hash       TEXT,
    sha1hash      TEXT,
    sha256hash    TEXT,
    lastaccessutc TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    createdutc    TEXT     NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

-- Seed defaults
INSERT OR IGNORE INTO s3_users  (guid, name, email)
VALUES ('default', 'Default User', 'default@default.com');

INSERT OR IGNORE INTO s3_credentials (guid, userguid, description, accesskey, secretkey, isbase64)
VALUES (lower(hex(randomblob(16))), 'default', 'Default key', 'default', 'default', 0);

INSERT OR IGNORE INTO s3_buckets (guid, ownerguid, name, regionstring, storagetype, diskdirectory,
                                   enableversioning, enablepublicwrite, enablepublicread)
VALUES ('default', 'default', 'default', 'us-west-1', 'Disk', './disk/default/Objects/', 0, 0, 1);
