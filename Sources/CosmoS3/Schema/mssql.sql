-- CosmoS3 schema for Microsoft SQL Server
-- Idempotent: safe to run multiple times (uses IF NOT EXISTS guards).
-- Tables live in the [s3] schema.

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 's3')
    EXEC('CREATE SCHEMA [s3]');

IF OBJECT_ID('s3.users', 'U') IS NULL
CREATE TABLE s3.users (
    id          INT            IDENTITY(1,1) PRIMARY KEY,
    guid        NVARCHAR(64)   NOT NULL UNIQUE,
    name        NVARCHAR(256)  NOT NULL,
    email       NVARCHAR(256)  NOT NULL UNIQUE,
    createdutc  DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('s3.credentials', 'U') IS NULL
CREATE TABLE s3.credentials (
    id          INT            IDENTITY(1,1) PRIMARY KEY,
    guid        NVARCHAR(64)   NOT NULL UNIQUE,
    userguid    NVARCHAR(64)   NOT NULL,
    description NVARCHAR(256),
    accesskey   NVARCHAR(256)  NOT NULL UNIQUE,
    secretkey   NVARCHAR(256)  NOT NULL,
    isbase64    TINYINT        NOT NULL DEFAULT 0,
    createdutc  DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('s3.buckets', 'U') IS NULL
CREATE TABLE s3.buckets (
    id               INT            IDENTITY(1,1) PRIMARY KEY,
    guid             NVARCHAR(64)   NOT NULL UNIQUE,
    ownerguid        NVARCHAR(64)   NOT NULL,
    name             NVARCHAR(256)  NOT NULL UNIQUE,
    regionstring     NVARCHAR(32)   NOT NULL DEFAULT 'us-west-1',
    storagetype      NVARCHAR(16)   NOT NULL DEFAULT 'Disk',
    diskdirectory    NVARCHAR(512)  NOT NULL,
    enableversioning TINYINT        NOT NULL DEFAULT 0,
    enablepublicwrite TINYINT       NOT NULL DEFAULT 0,
    enablepublicread  TINYINT       NOT NULL DEFAULT 0,
    createdutc       DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('s3.objects', 'U') IS NULL
CREATE TABLE s3.objects (
    id             INT            IDENTITY(1,1) PRIMARY KEY,
    guid           NVARCHAR(64)   NOT NULL UNIQUE,
    bucketguid     NVARCHAR(64)   NOT NULL,
    ownerguid      NVARCHAR(64)   NOT NULL,
    authorguid     NVARCHAR(64)   NOT NULL,
    objectkey      NVARCHAR(1024) NOT NULL,
    contenttype    NVARCHAR(256),
    contentlength  BIGINT         NOT NULL DEFAULT 0,
    version        BIGINT         NOT NULL DEFAULT 1,
    etag           NVARCHAR(128),
    retention      NVARCHAR(32)   NOT NULL DEFAULT 'NONE',
    blobfilename   NVARCHAR(512)  NOT NULL,
    isfolder       TINYINT        NOT NULL DEFAULT 0,
    deletemarker   TINYINT        NOT NULL DEFAULT 0,
    md5            NVARCHAR(64),
    metadata       NVARCHAR(MAX),
    expirationutc  DATETIME2,
    createdutc     DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    lastupdateutc  DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    lastaccessutc  DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('s3.buckettags', 'U') IS NULL
CREATE TABLE s3.buckettags (
    id         INT            IDENTITY(1,1) PRIMARY KEY,
    guid       NVARCHAR(64)   NOT NULL UNIQUE,
    bucketguid NVARCHAR(64)   NOT NULL,
    tagkey     NVARCHAR(256)  NOT NULL,
    tagvalue   NVARCHAR(1024),
    createdutc DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('s3.objecttags', 'U') IS NULL
CREATE TABLE s3.objecttags (
    id         INT            IDENTITY(1,1) PRIMARY KEY,
    guid       NVARCHAR(64)   NOT NULL UNIQUE,
    bucketguid NVARCHAR(64)   NOT NULL,
    objectguid NVARCHAR(64)   NOT NULL,
    tagkey     NVARCHAR(256)  NOT NULL,
    tagvalue   NVARCHAR(1024),
    createdutc DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('s3.bucketacls', 'U') IS NULL
CREATE TABLE s3.bucketacls (
    id                 INT            IDENTITY(1,1) PRIMARY KEY,
    guid               NVARCHAR(64)   NOT NULL UNIQUE,
    usergroup          NVARCHAR(256),
    bucketguid         NVARCHAR(64)   NOT NULL,
    userguid           NVARCHAR(64),
    issuedbyuserguid   NVARCHAR(64),
    permitread         TINYINT        NOT NULL DEFAULT 0,
    permitwrite        TINYINT        NOT NULL DEFAULT 0,
    permitreadacp      TINYINT        NOT NULL DEFAULT 0,
    permitwriteacp     TINYINT        NOT NULL DEFAULT 0,
    permitfullcontrol  TINYINT        NOT NULL DEFAULT 0,
    createdutc         DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('s3.objectacls', 'U') IS NULL
CREATE TABLE s3.objectacls (
    id                 INT            IDENTITY(1,1) PRIMARY KEY,
    guid               NVARCHAR(64)   NOT NULL UNIQUE,
    usergroup          NVARCHAR(256),
    userguid           NVARCHAR(64),
    issuedbyuserguid   NVARCHAR(64),
    bucketguid         NVARCHAR(64)   NOT NULL,
    objectguid         NVARCHAR(64)   NOT NULL,
    permitread         TINYINT        NOT NULL DEFAULT 0,
    permitwrite        TINYINT        NOT NULL DEFAULT 0,
    permitreadacp      TINYINT        NOT NULL DEFAULT 0,
    permitwriteacp     TINYINT        NOT NULL DEFAULT 0,
    permitfullcontrol  TINYINT        NOT NULL DEFAULT 0,
    createdutc         DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('s3.uploads', 'U') IS NULL
CREATE TABLE s3.uploads (
    id             INT            IDENTITY(1,1) PRIMARY KEY,
    guid           NVARCHAR(64)   NOT NULL UNIQUE,
    bucketguid     NVARCHAR(64)   NOT NULL,
    ownerguid      NVARCHAR(64)   NOT NULL,
    authorguid     NVARCHAR(64)   NOT NULL,
    objectkey      NVARCHAR(1024) NOT NULL,
    createdutc     DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    lastaccessutc  DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    expirationutc  DATETIME2      NOT NULL,
    contenttype    NVARCHAR(256),
    metadata       NVARCHAR(MAX)
);

IF OBJECT_ID('s3.uploadparts', 'U') IS NULL
CREATE TABLE s3.uploadparts (
    id            INT            IDENTITY(1,1) PRIMARY KEY,
    guid          NVARCHAR(64)   NOT NULL UNIQUE,
    bucketguid    NVARCHAR(64)   NOT NULL,
    ownerguid     NVARCHAR(64)   NOT NULL,
    uploadguid    NVARCHAR(64)   NOT NULL,
    partnumber    INT            NOT NULL,
    partlength    INT            NOT NULL DEFAULT 0,
    md5hash       NVARCHAR(64),
    sha1hash      NVARCHAR(128),
    sha256hash    NVARCHAR(128),
    lastaccessutc DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    createdutc    DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

IF NOT EXISTS (SELECT 1 FROM s3.users WHERE guid = 'default')
    INSERT INTO s3.users (guid, name, email)
    VALUES ('default', 'Default User', 'default@default.com');

IF NOT EXISTS (SELECT 1 FROM s3.credentials WHERE accesskey = 'default')
    INSERT INTO s3.credentials (guid, userguid, description, accesskey, secretkey, isbase64)
    VALUES (NEWID(), 'default', 'Default key', 'default', 'default', 0);

IF NOT EXISTS (SELECT 1 FROM s3.buckets WHERE guid = 'default')
    INSERT INTO s3.buckets (guid, ownerguid, name, regionstring, storagetype, diskdirectory,
                            enableversioning, enablepublicwrite, enablepublicread)
    VALUES ('default', 'default', 'default', 'us-west-1', 'Disk', './disk/default/Objects/', 0, 0, 1);

