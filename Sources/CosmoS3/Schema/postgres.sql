-- CosmoS3 schema for PostgreSQL
-- Run once against the target database.
-- Tables live in the [s3] schema.

CREATE SCHEMA IF NOT EXISTS s3;

CREATE TABLE IF NOT EXISTS s3.users (
    id         SERIAL       PRIMARY KEY,
    guid       VARCHAR(64)  NOT NULL UNIQUE,
    name       VARCHAR(256) NOT NULL,
    email      VARCHAR(256) NOT NULL UNIQUE,
    createdutc TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS s3.credentials (
    id          SERIAL       PRIMARY KEY,
    guid        VARCHAR(64)  NOT NULL UNIQUE,
    userguid    VARCHAR(64)  NOT NULL,
    description VARCHAR(256),
    accesskey   VARCHAR(256) NOT NULL UNIQUE,
    secretkey   VARCHAR(256) NOT NULL,
    isbase64    SMALLINT     NOT NULL DEFAULT 0,
    createdutc  TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS s3.buckets (
    id                SERIAL       PRIMARY KEY,
    guid              VARCHAR(64)  NOT NULL UNIQUE,
    ownerguid         VARCHAR(64)  NOT NULL,
    name              VARCHAR(256) NOT NULL UNIQUE,
    regionstring      VARCHAR(32)  NOT NULL DEFAULT 'us-west-1',
    storagetype       VARCHAR(16)  NOT NULL DEFAULT 'Disk',
    diskdirectory     VARCHAR(512) NOT NULL,
    enableversioning  SMALLINT     NOT NULL DEFAULT 0,
    enablepublicwrite SMALLINT     NOT NULL DEFAULT 0,
    enablepublicread  SMALLINT     NOT NULL DEFAULT 0,
    createdutc        TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS s3.objects (
    id            SERIAL        PRIMARY KEY,
    guid          VARCHAR(64)   NOT NULL UNIQUE,
    bucketguid    VARCHAR(64)   NOT NULL,
    ownerguid     VARCHAR(64)   NOT NULL,
    authorguid    VARCHAR(64)   NOT NULL,
    objectkey           VARCHAR(1024) NOT NULL,
    contenttype   VARCHAR(256),
    contentlength BIGINT        NOT NULL DEFAULT 0,
    version       BIGINT        NOT NULL DEFAULT 1,
    etag          VARCHAR(128),
    retention     VARCHAR(32)   NOT NULL DEFAULT 'NONE',
    blobfilename  VARCHAR(512)  NOT NULL,
    isfolder      SMALLINT      NOT NULL DEFAULT 0,
    deletemarker  SMALLINT      NOT NULL DEFAULT 0,
    md5           VARCHAR(64),
    metadata      TEXT,
    expirationutc TIMESTAMP,
    createdutc    TIMESTAMP     NOT NULL DEFAULT NOW(),
    lastupdateutc TIMESTAMP     NOT NULL DEFAULT NOW(),
    lastaccessutc TIMESTAMP     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS s3.buckettags (
    id         SERIAL        PRIMARY KEY,
    guid       VARCHAR(64)   NOT NULL UNIQUE,
    bucketguid VARCHAR(64)   NOT NULL,
    tagkey     VARCHAR(256)  NOT NULL,
    tagvalue   VARCHAR(1024),
    createdutc TIMESTAMP     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS s3.objecttags (
    id         SERIAL        PRIMARY KEY,
    guid       VARCHAR(64)   NOT NULL UNIQUE,
    bucketguid VARCHAR(64)   NOT NULL,
    objectguid VARCHAR(64)   NOT NULL,
    tagkey     VARCHAR(256)  NOT NULL,
    tagvalue   VARCHAR(1024),
    createdutc TIMESTAMP     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS s3.bucketacls (
    id                SERIAL       PRIMARY KEY,
    guid              VARCHAR(64)  NOT NULL UNIQUE,
    usergroup         VARCHAR(256),
    bucketguid        VARCHAR(64)  NOT NULL,
    userguid          VARCHAR(64),
    issuedbyuserguid  VARCHAR(64),
    permitread        SMALLINT     NOT NULL DEFAULT 0,
    permitwrite       SMALLINT     NOT NULL DEFAULT 0,
    permitreadacp     SMALLINT     NOT NULL DEFAULT 0,
    permitwriteacp    SMALLINT     NOT NULL DEFAULT 0,
    permitfullcontrol SMALLINT     NOT NULL DEFAULT 0,
    createdutc        TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS s3.objectacls (
    id                SERIAL       PRIMARY KEY,
    guid              VARCHAR(64)  NOT NULL UNIQUE,
    usergroup         VARCHAR(256),
    userguid          VARCHAR(64),
    issuedbyuserguid  VARCHAR(64),
    bucketguid        VARCHAR(64)  NOT NULL,
    objectguid        VARCHAR(64)  NOT NULL,
    permitread        SMALLINT     NOT NULL DEFAULT 0,
    permitwrite       SMALLINT     NOT NULL DEFAULT 0,
    permitreadacp     SMALLINT     NOT NULL DEFAULT 0,
    permitwriteacp    SMALLINT     NOT NULL DEFAULT 0,
    permitfullcontrol SMALLINT     NOT NULL DEFAULT 0,
    createdutc        TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS s3.uploads (
    id            SERIAL        PRIMARY KEY,
    guid          VARCHAR(64)   NOT NULL UNIQUE,
    bucketguid    VARCHAR(64)   NOT NULL,
    ownerguid     VARCHAR(64)   NOT NULL,
    authorguid    VARCHAR(64)   NOT NULL,
    objectkey           VARCHAR(1024) NOT NULL,
    createdutc    TIMESTAMP     NOT NULL DEFAULT NOW(),
    lastaccessutc TIMESTAMP     NOT NULL DEFAULT NOW(),
    expirationutc TIMESTAMP     NOT NULL,
    contenttype   VARCHAR(256),
    metadata      TEXT
);

CREATE TABLE IF NOT EXISTS s3.uploadparts (
    id            SERIAL       PRIMARY KEY,
    guid          VARCHAR(64)  NOT NULL UNIQUE,
    bucketguid    VARCHAR(64)  NOT NULL,
    ownerguid     VARCHAR(64)  NOT NULL,
    uploadguid    VARCHAR(64)  NOT NULL,
    partnumber    INT          NOT NULL,
    partlength    INT          NOT NULL DEFAULT 0,
    md5hash       VARCHAR(64),
    sha1hash      VARCHAR(128),
    sha256hash    VARCHAR(128),
    lastaccessutc TIMESTAMP    NOT NULL DEFAULT NOW(),
    createdutc    TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Seed defaults
INSERT INTO s3.users  (guid, name, email) VALUES ('default', 'Default User', 'default@default.com') ON CONFLICT DO NOTHING;
INSERT INTO s3.credentials (guid, userguid, description, accesskey, secretkey, isbase64)
VALUES (gen_random_uuid()::text, 'default', 'Default key', 'default', 'default', 0) ON CONFLICT DO NOTHING;
INSERT INTO s3.buckets (guid, ownerguid, name, regionstring, storagetype, diskdirectory,
                        enableversioning, enablepublicwrite, enablepublicread)
VALUES ('default', 'default', 'default', 'us-west-1', 'Disk', './disk/default/Objects/', 0, 0, 1) ON CONFLICT DO NOTHING;
