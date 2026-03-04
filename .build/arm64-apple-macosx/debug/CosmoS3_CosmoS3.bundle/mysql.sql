-- CosmoS3 schema for MySQL / MariaDB
-- Tables use the s3_ prefix (MySQL treats schemas as databases).
-- Run once against the target database.

CREATE TABLE IF NOT EXISTS s3_users (
    id         INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    guid       VARCHAR(64)  NOT NULL UNIQUE,
    name       VARCHAR(256) NOT NULL,
    email      VARCHAR(256) NOT NULL UNIQUE,
    createdutc DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS s3_credentials (
    id          INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    guid        VARCHAR(64)  NOT NULL UNIQUE,
    userguid    VARCHAR(64)  NOT NULL,
    description VARCHAR(256),
    accesskey   VARCHAR(256) NOT NULL UNIQUE,
    secretkey   VARCHAR(256) NOT NULL,
    isbase64    TINYINT      NOT NULL DEFAULT 0,
    createdutc  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS s3_buckets (
    id                INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    guid              VARCHAR(64)  NOT NULL UNIQUE,
    ownerguid         VARCHAR(64)  NOT NULL,
    name              VARCHAR(256) NOT NULL UNIQUE,
    regionstring      VARCHAR(32)  NOT NULL DEFAULT 'us-west-1',
    storagetype       VARCHAR(16)  NOT NULL DEFAULT 'Disk',
    diskdirectory     VARCHAR(512) NOT NULL,
    enableversioning  TINYINT      NOT NULL DEFAULT 0,
    enablepublicwrite TINYINT      NOT NULL DEFAULT 0,
    enablepublicread  TINYINT      NOT NULL DEFAULT 0,
    createdutc        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS s3_objects (
    id            BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    guid          VARCHAR(64)   NOT NULL UNIQUE,
    bucketguid    VARCHAR(64)   NOT NULL,
    ownerguid     VARCHAR(64)   NOT NULL,
    authorguid    VARCHAR(64)   NOT NULL,
    objectkey         VARCHAR(1024) NOT NULL,
    contenttype   VARCHAR(256),
    contentlength BIGINT        NOT NULL DEFAULT 0,
    version       BIGINT        NOT NULL DEFAULT 1,
    etag          VARCHAR(128),
    retention     VARCHAR(32)   NOT NULL DEFAULT 'NONE',
    blobfilename  VARCHAR(512)  NOT NULL,
    isfolder      TINYINT       NOT NULL DEFAULT 0,
    deletemarker  TINYINT       NOT NULL DEFAULT 0,
    md5           VARCHAR(64),
    metadata      TEXT,
    expirationutc DATETIME,
    createdutc    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    lastupdateutc DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    lastaccessutc DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS s3_buckettags (
    id         INT           NOT NULL AUTO_INCREMENT PRIMARY KEY,
    guid       VARCHAR(64)   NOT NULL UNIQUE,
    bucketguid VARCHAR(64)   NOT NULL,
    tagkey     VARCHAR(256)  NOT NULL,
    tagvalue   VARCHAR(1024),
    createdutc DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS s3_objecttags (
    id         INT           NOT NULL AUTO_INCREMENT PRIMARY KEY,
    guid       VARCHAR(64)   NOT NULL UNIQUE,
    bucketguid VARCHAR(64)   NOT NULL,
    objectguid VARCHAR(64)   NOT NULL,
    tagkey     VARCHAR(256)  NOT NULL,
    tagvalue   VARCHAR(1024),
    createdutc DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS s3_bucketacls (
    id                INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    guid              VARCHAR(64)  NOT NULL UNIQUE,
    usergroup         VARCHAR(256),
    bucketguid        VARCHAR(64)  NOT NULL,
    userguid          VARCHAR(64),
    issuedbyuserguid  VARCHAR(64),
    permitread        TINYINT      NOT NULL DEFAULT 0,
    permitwrite       TINYINT      NOT NULL DEFAULT 0,
    permitreadacp     TINYINT      NOT NULL DEFAULT 0,
    permitwriteacp    TINYINT      NOT NULL DEFAULT 0,
    permitfullcontrol TINYINT      NOT NULL DEFAULT 0,
    createdutc        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS s3_objectacls (
    id                INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    guid              VARCHAR(64)  NOT NULL UNIQUE,
    usergroup         VARCHAR(256),
    userguid          VARCHAR(64),
    issuedbyuserguid  VARCHAR(64),
    bucketguid        VARCHAR(64)  NOT NULL,
    objectguid        VARCHAR(64)  NOT NULL,
    permitread        TINYINT      NOT NULL DEFAULT 0,
    permitwrite       TINYINT      NOT NULL DEFAULT 0,
    permitreadacp     TINYINT      NOT NULL DEFAULT 0,
    permitwriteacp    TINYINT      NOT NULL DEFAULT 0,
    permitfullcontrol TINYINT      NOT NULL DEFAULT 0,
    createdutc        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS s3_uploads (
    id            BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    guid          VARCHAR(64)   NOT NULL UNIQUE,
    bucketguid    VARCHAR(64)   NOT NULL,
    ownerguid     VARCHAR(64)   NOT NULL,
    authorguid    VARCHAR(64)   NOT NULL,
    objectkey         VARCHAR(1024) NOT NULL,
    createdutc    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    lastaccessutc DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expirationutc DATETIME      NOT NULL,
    contenttype   VARCHAR(256),
    metadata      TEXT
);

CREATE TABLE IF NOT EXISTS s3_uploadparts (
    id            INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    guid          VARCHAR(64)  NOT NULL UNIQUE,
    bucketguid    VARCHAR(64)  NOT NULL,
    ownerguid     VARCHAR(64)  NOT NULL,
    uploadguid    VARCHAR(64)  NOT NULL,
    partnumber    INT          NOT NULL,
    partlength    INT          NOT NULL DEFAULT 0,
    md5hash       VARCHAR(64),
    sha1hash      VARCHAR(128),
    sha256hash    VARCHAR(128),
    lastaccessutc DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    createdutc    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Seed defaults
INSERT IGNORE INTO s3_users  (guid, name, email) VALUES ('default', 'Default User', 'default@default.com');
INSERT IGNORE INTO s3_credentials (guid, userguid, description, accesskey, secretkey, isbase64)
VALUES (UUID(), 'default', 'Default key', 'default', 'default', 0);
INSERT IGNORE INTO s3_buckets (guid, ownerguid, name, regionstring, storagetype, diskdirectory,
                        enableversioning, enablepublicwrite, enablepublicread)
VALUES ('default', 'default', 'default', 'us-west-1', 'Disk', './disk/default/Objects/', 0, 0, 1);
