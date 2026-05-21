IF COL_LENGTH('portal.Supplier', 'isMissing') IS NULL
BEGIN
    IF COL_LENGTH('portal.Supplier', 'UnsubscribeId') IS NOT NULL
    BEGIN
        EXEC sp_rename 'portal.Supplier.UnsubscribeId', 'isMissing', 'COLUMN'
    END
    ELSE
    BEGIN
        ALTER TABLE [portal].[Supplier]
        ADD [isMissing] bit NULL
    END
END;
GO

UPDATE [portal].[Supplier]
SET [isMissing] = CASE WHEN ISNULL(TRY_CONVERT(INT, [isMissing]), 0) = 0 THEN 0 ELSE 1 END
WHERE [isMissing] IS NULL OR ISNULL(TRY_CONVERT(INT, [isMissing]), 0) NOT IN (0, 1);
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c
        ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'[portal].[Supplier]')
      AND c.name = 'isMissing'
)
BEGIN
    ALTER TABLE [portal].[Supplier]
    ADD CONSTRAINT [DF_Supplier_isMissing] DEFAULT ((0)) FOR [isMissing];
END;
GO

ALTER TABLE [portal].[Supplier]
ALTER COLUMN [isMissing] bit NOT NULL;
GO

CREATE OR ALTER PROCEDURE [portal].[spSupplier_Save]
    @supplierId  INT            = NULL,
    @companyId   INT            = NULL,
    @companyName NVARCHAR(50)   = NULL,
    @name        NVARCHAR(100),
    @email       NVARCHAR(50),
    @phone       NVARCHAR(20),
    @industry    NVARCHAR(50)   = NULL,
    @spend       NVARCHAR(20)   = NULL,
    @certId      INT            = NULL,
    @isMissing     BIT            = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @existingSupplierId INT;
    SET @email = ISNULL(@email, '');
    SET @phone = ISNULL(@phone, '');

    IF @supplierId IS NOT NULL
    BEGIN
        SELECT @existingSupplierId = supplierId
        FROM   [portal].[Supplier]
        WHERE  supplierId = @supplierId;
    END
    ELSE IF NULLIF(LTRIM(RTRIM(@email)), '') IS NOT NULL
    BEGIN
        SELECT @existingSupplierId = supplierId
        FROM   [portal].[Supplier]
        WHERE  companyId = @companyId
          AND  email     = @email
          AND  isDeleted = 0;
    END
    ELSE
    BEGIN
        SELECT @existingSupplierId = supplierId
        FROM   [portal].[Supplier]
        WHERE  companyId = @companyId
          AND  ISNULL(companyName, '') = ISNULL(@companyName, '')
          AND  name = @name
          AND  ISNULL(certId, 0) = ISNULL(@certId, 0)
          AND  isDeleted = 0;
    END

    IF @existingSupplierId IS NULL
    BEGIN
        INSERT INTO [portal].[Supplier] (
            companyId, name, email, phone, companyName, industry, spend, certId, isDeleted, isMissing
        )
        VALUES (
            @companyId, @name, @email, @phone, @companyName, @industry, @spend, @certId, 0, @isMissing
        );

        SELECT SCOPE_IDENTITY() AS supplierId, 'Inserted' AS Action;
    END
    ELSE
    BEGIN
        UPDATE [portal].[Supplier]
        SET
            name        = @name,
            email       = @email,
            phone       = @phone,
            companyName = @companyName,
            industry    = @industry,
            spend       = @spend,
            certId      = COALESCE(@certId, certId),
            isMissing     = @isMissing,
            isDeleted   = 0
        WHERE supplierId = @existingSupplierId;

        SELECT @existingSupplierId AS supplierId, 'Updated' AS Action;
    END
END;
GO

CREATE OR ALTER PROCEDURE [portal].[spSupplier_Get]
    @companyId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.supplierId,
        s.companyId,
        s.name,
        s.email,
        s.phone,
        s.companyName,
        s.industry,
        s.spend,
        s.certId,
        s.isMissing,
        c.companyName   AS ownerCompanyName,
        cert.refNumber  AS certRefNumber,
        cert.certYear   AS certYear,
        prg.progName    AS certProgName
    FROM   [portal].[Supplier]      s
    LEFT JOIN [portal].[Company]      c    ON c.companyId = s.companyId
    LEFT JOIN [portal].[Certification] cert ON cert.certId = s.certId
    LEFT JOIN [portal].[Programme]    prg  ON prg.progId  = cert.progId
    WHERE  (@companyId IS NULL OR s.companyId = @companyId)
      AND  ISNULL(s.isDeleted, 0) = 0
    ORDER  BY s.name ASC;
END;
GO



CREATE OR ALTER PROCEDURE [portal].[spEmailUnsubscription_Save]
    @Email   NVARCHAR(255),
    @Reason  NVARCHAR(100),
    @Details NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Email = LOWER(LTRIM(RTRIM(@Email)));

    IF EXISTS (SELECT 1 FROM [portal].[EmailUnsubscriptions] WHERE [Email] = @Email)
    BEGIN
        UPDATE [portal].[EmailUnsubscriptions]
        SET    [Reason]          = @Reason,
               [Details]         = @Details,
               [IsUnsubscribed]  = 1,
               [UnsubscribeDate] = GETUTCDATE(),
               [ResubscribeDate] = NULL,
               [UpdatedAt]       = GETUTCDATE()
        WHERE  [Email] = @Email;
    END
    ELSE
    BEGIN
        INSERT INTO [portal].[EmailUnsubscriptions] ([Email], [Reason], [Details])
        VALUES (@Email, @Reason, @Details);
    END

    SELECT [UnsubscribeId]   AS unsubscribeId,
           [Email]           AS email,
           [Reason]          AS reason,
           [Details]         AS details,
           [UnsubscribeDate] AS unsubscribeDate,
           [ResubscribeDate] AS resubscribeDate,
           [IsUnsubscribed]  AS isUnsubscribed,
           [CreatedAt]       AS createdAt,
           [UpdatedAt]       AS updatedAt
    FROM   [portal].[EmailUnsubscriptions]
    WHERE  [Email] = @Email;
END;
GO

CREATE OR ALTER PROCEDURE [portal].[spEmailUnsubscription_Get]
    @Email NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Email IS NOT NULL
        SET @Email = LOWER(LTRIM(RTRIM(@Email)));

    SELECT [UnsubscribeId]   AS unsubscribeId,
           [Email]           AS email,
           [Reason]          AS reason,
           [Details]         AS details,
           [UnsubscribeDate] AS unsubscribeDate,
           [ResubscribeDate] AS resubscribeDate,
           [IsUnsubscribed]  AS isUnsubscribed,
           [CreatedAt]       AS createdAt,
           [UpdatedAt]       AS updatedAt
    FROM   [portal].[EmailUnsubscriptions]
    WHERE  (@Email IS NULL OR [Email] = @Email)
    ORDER  BY [UnsubscribeDate] DESC;
END;
GO

CREATE OR ALTER PROCEDURE [portal].[spEmailUnsubscription_Resubscribe]
    @Email NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    SET @Email = LOWER(LTRIM(RTRIM(@Email)));

    UPDATE [portal].[EmailUnsubscriptions]
    SET    [IsUnsubscribed]  = 0,
           [ResubscribeDate] = GETUTCDATE(),
           [UpdatedAt]       = GETUTCDATE()
    WHERE  [Email] = @Email;

    SELECT [UnsubscribeId]   AS unsubscribeId,
           [Email]           AS email,
           [Reason]          AS reason,
           [Details]         AS details,
           [UnsubscribeDate] AS unsubscribeDate,
           [ResubscribeDate] AS resubscribeDate,
           [IsUnsubscribed]  AS isUnsubscribed,
           [CreatedAt]       AS createdAt,
           [UpdatedAt]       AS updatedAt
    FROM   [portal].[EmailUnsubscriptions]
    WHERE  [Email] = @Email;
END;
GO
