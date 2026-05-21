-- Add canSaveDraft column to PublicForms table
ALTER TABLE [portal].[PublicForms] ADD [canSaveDraft] bit DEFAULT 0 NULL;
GO


-- ----------------------------
-- procedure structure for spToken_Validate
-- Updated to include canSaveDraft from [portal].[PublicForms]
-- ----------------------------
-- ============================================================
-- Fix spToken_Validate: widen @tokenKey from NVARCHAR(20) to
-- NVARCHAR(500) to prevent silent truncation of tokens longer
-- than 20 characters (webinar tokens are NVARCHAR(200)).
-- Truncation caused appended text to still validate correctly
-- because the extra characters were silently discarded.
-- Date: 2026-04-21
-- ============================================================

ALTER   PROCEDURE [portal].[spToken_Validate]
    @tokenType NVARCHAR(100),
    @tokenKey  NVARCHAR(25)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.tokenId,
        t.tokenKey,
        t.tokenType,
        t.certId,
        t.locationId,
        t.dimFormId,
        CASE
            WHEN t.activeTo IS NULL  THEN 0
            WHEN t.activeTo >= GETDATE() THEN 0
            ELSE 1
        END AS isExpired,
        t.isActive,
        t.properties,
        ISNULL(pf.canSaveDraft, 0) AS canSaveDraft
    FROM [portal].[Tokens] t
    LEFT JOIN [portal].[PublicForms] pf ON (pf.dimFormId = t.dimFormId and t.tokenType='publicform')
    WHERE t.tokenKey = @tokenKey
      AND (
            @tokenType IS NULL
            OR t.tokenType IN (
                SELECT TRIM(value)
                FROM STRING_SPLIT(@tokenType, ',')
            )
          );
END
GO

-- ─────────────────────────────────────────────────────────────
-- 5. spWebinarSuppliers_Get — derive isUnsubscribed from Supplier.UnsubscribeId
-- ─────────────────────────────────────────────────────────────
ALTER   PROCEDURE [portal].[spWebinarSuppliers_Get]
    @webinarId  INT,
    @companyId  INT,
    @certId     INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.supplierId,
           s.name,
           s.email,
           s.companyName,
           s.certId,
           CASE
               WHEN b.bookingId     IS NOT NULL THEN 'confirmed'
               WHEN wi.invitationId IS NOT NULL THEN 'invited'
               ELSE NULL
           END AS inviteStatus,
           IsNull(eu.IsUnsubscribed, 0) AS isUnsubscribed
    FROM   [portal].[Supplier]               s
    LEFT JOIN [portal].[WebinarInvitations]  wi
           ON  wi.webinarId  = @webinarId
           AND wi.supplierId = s.supplierId
    LEFT JOIN [portal].[WebinarBookings]     b
           ON  b.webinarId           = @webinarId
           AND LOWER(b.contactEmail) = LOWER(s.email)
           AND b.status              = 'confirmed'
    LEFT JOIN portal.EmailUnsubscriptions as eu on (s.email = eu.Email)
    WHERE  s.companyId = @companyId And isNull(trim(s.email),'') <> ''
      AND  (@certId IS NULL OR s.certId = @certId)
      And (IsNull(eu.UnsubscribeId, 0) = 0 OR wi.invitationId is not null) -- exclude unsubscribed
    ORDER  BY s.name ASC;
END
Go