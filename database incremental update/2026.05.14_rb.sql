-- ============================================================
-- Export Style + Public Form Attachments/ZIP
-- Adds exportStyle configuration to ProgrammeForms/PublicForms
-- Adds attachments count in public form submissions listing
-- Adds SP for retrieving public form submission documents
-- Date: 2026-05-14
-- ============================================================

-- ----------------------------
-- Add exportStyle to ProgrammeForms
-- ----------------------------
IF COL_LENGTH('portal.ProgrammeForms', 'exportStyle') IS NULL
BEGIN
    ALTER TABLE [portal].[ProgrammeForms]
    ADD [exportStyle] NVARCHAR(20) NULL;
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c
        ON c.default_object_id = dc.object_id
    INNER JOIN sys.tables t
        ON t.object_id = c.object_id
    INNER JOIN sys.schemas s
        ON s.schema_id = t.schema_id
    WHERE s.name = 'portal'
      AND t.name = 'ProgrammeForms'
      AND c.name = 'exportStyle'
)
BEGIN
    ALTER TABLE [portal].[ProgrammeForms]
    ADD CONSTRAINT [DF_ProgrammeForms_exportStyle] DEFAULT ('vertical') FOR [exportStyle];
END
GO

UPDATE [portal].[ProgrammeForms]
SET [exportStyle] = 'vertical'
WHERE [exportStyle] IS NULL
   OR LTRIM(RTRIM([exportStyle])) = '';
GO

UPDATE [portal].[ProgrammeForms] SET [exportStyle] = N'horizontal' WHERE [dimFormId] in (11, 26);
Go
-- ----------------------------
-- Add exportStyle to PublicForms
-- ----------------------------
IF COL_LENGTH('portal.PublicForms', 'exportStyle') IS NULL
BEGIN
    ALTER TABLE [portal].[PublicForms]
    ADD [exportStyle] NVARCHAR(20) NULL;
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c
        ON c.default_object_id = dc.object_id
    INNER JOIN sys.tables t
        ON t.object_id = c.object_id
    INNER JOIN sys.schemas s
        ON s.schema_id = t.schema_id
    WHERE s.name = 'portal'
      AND t.name = 'PublicForms'
      AND c.name = 'exportStyle'
)
BEGIN
    ALTER TABLE [portal].[PublicForms]
    ADD CONSTRAINT [DF_PublicForms_exportStyle] DEFAULT ('vertical') FOR [exportStyle];
END
GO

UPDATE [portal].[PublicForms]
SET [exportStyle] = 'vertical'
WHERE [exportStyle] IS NULL
   OR LTRIM(RTRIM([exportStyle])) = '';
GO

UPDATE [portal].[PublicForms] SET [exportStyle] = N'horizontal' WHERE [dimFormId] = 36;
Go
-- ----------------------------
-- procedure structure for spCertification_GetSubmissions
-- ----------------------------
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[portal].[spCertification_GetSubmissions]') AND type IN ('P', 'PC', 'RF', 'X'))
    DROP PROCEDURE [portal].[spCertification_GetSubmissions]
GO

CREATE PROCEDURE [portal].[spCertification_GetSubmissions]
  @certId INT
AS
BEGIN
  SET NOCOUNT ON;

  SELECT
    pf.progFormId,
    pf.dimFormId,
    pf.displayName AS formName,
    pf.displayOrder,
        ISNULL(NULLIF(LTRIM(RTRIM(pf.exportStyle)), ''), 'vertical') AS exportStyle,
    df.dataSourceId,
    cfs.certsubmissionId,
    cfs.submissionId,
    cfs.dateSubmitted,
    cfs.userId,
    u.fullName,
    cfs.locationId,
    l.locationName
  FROM portal.Certification AS cert
  INNER JOIN portal.ProgrammeForms AS pf
    ON pf.progId = cert.progId
  INNER JOIN Dimension.Form AS df
    ON df.id = pf.dimFormId
  INNER JOIN portal.CertFormSubmissions AS cfs
    ON pf.dimFormId = cfs.dimFormId
    AND cert.certId = cfs.certId
  LEFT JOIN portal.Users AS u
    ON u.userId = cfs.userId
    AND ISNULL(u.isDeleted, 0) = 0
  LEFT JOIN portal.Location AS l
    ON l.locationId = cfs.locationId
    AND ISNULL(l.isDeleted, 0) = 0
  WHERE cert.certId = @certId
    AND cfs.isDraft = 0
  ORDER BY cfs.dateSubmitted;
END
GO

-- ----------------------------
-- procedure structure for spPublicForm_Get
-- ----------------------------
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[portal].[spPublicForm_Get]') AND type IN ('P', 'PC', 'RF', 'X'))
    DROP PROCEDURE [portal].[spPublicForm_Get]
GO

CREATE PROCEDURE [portal].[spPublicForm_Get]
    @pformId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        pf.[pformId],
        pf.[dimFormId],
        pf.[displayName],
        pf.[displayOrder],
        pf.[isActive],
        ISNULL(NULLIF(LTRIM(RTRIM(pf.[exportStyle])), ''), 'vertical') AS [exportStyle],
        COUNT(pfs.[psubmissionId]) AS [submissionCnt]
    FROM [portal].[PublicForms] pf
    LEFT JOIN [portal].[PublicFormSubmissions] pfs
        ON pfs.[dimFormId] = pf.[dimFormId]
        AND (pfs.[isDeleted] = 0 OR pfs.[isDeleted] IS NULL)
    WHERE ((@pformId IS NULL AND pf.[isActive] = 1) OR pf.[pformId] = @pformId)
    GROUP BY
        pf.[pformId],
        pf.[dimFormId],
        pf.[displayName],
        pf.[displayOrder],
        pf.[isActive],
        ISNULL(NULLIF(LTRIM(RTRIM(pf.[exportStyle])), ''), 'vertical')
    ORDER BY pf.[displayOrder], pf.[displayName];
END
GO

-- ----------------------------
-- procedure structure for spPublicFormSubmission_Get
-- ----------------------------
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[portal].[spPublicFormSubmission_Get]') AND type IN ('P', 'PC', 'RF', 'X'))
    DROP PROCEDURE [portal].[spPublicFormSubmission_Get]
GO

CREATE PROCEDURE [portal].[spPublicFormSubmission_Get]
    @dimFormId INT,
    @psubmissionId INT = NULL,
    @dateFrom DATETIME2 = NULL,
    @dateTo DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        pfs.[psubmissionId],
        pfs.[dimFormId],
        df.sourceId AS formId,
        pfs.[submissionId],
        pfs.[certId],
        pfs.[dateSubmitted],
        pfs.[notes],
        pfs.[properties],
        pf.[displayName],
        ISNULL(attachmentInfo.attachments, 0) AS attachments,
        STRING_AGG(
            CASE
                WHEN q.questionLabel IS NOT NULL
                THEN CONCAT(q.questionLabel, ':', ISNULL(sr.responseData, ''))
            END,
            ', '
        ) AS details
    FROM [portal].[PublicFormSubmissions] pfs
    INNER JOIN [portal].[PublicForms] pf
        ON pf.[dimFormId] = pfs.[dimFormId]
    INNER JOIN Dimension.Form AS df
        ON df.id = pf.dimFormId
    OUTER APPLY (
        SELECT COUNT(DISTINCT fsd.documentId) AS attachments
        FROM portal.FormSubmissionDocuments AS fsd
        INNER JOIN documents.Document AS d
            ON d.id = fsd.documentId
        WHERE fsd.submissionId = pfs.submissionId
          AND fsd.formId = df.sourceId
    ) attachmentInfo
    OUTER APPLY STRING_SPLIT(pf.displayQuestionIds, ',') qs
    LEFT JOIN portal.FormQuestions AS q
        ON q.formId = df.sourceId
       AND q.questionId = TRY_CAST(qs.value AS INT)
    LEFT JOIN portal.FormSubmissionResponses AS sr
        ON sr.questionId = q.questionId
       AND sr.submissionId = pfs.submissionId
    WHERE (pfs.[isDeleted] = 0 OR pfs.[isDeleted] IS NULL)
      AND pfs.[dimFormId] = @dimFormId
      AND (@psubmissionId IS NULL OR pfs.[psubmissionId] = @psubmissionId)
      AND (@dateFrom IS NULL OR CAST(pfs.[dateSubmitted] AS DATE) >= CAST(@dateFrom AS DATE))
      AND (@dateTo IS NULL OR CAST(pfs.[dateSubmitted] AS DATE) <= CAST(@dateTo AS DATE))
    GROUP BY
      pfs.[psubmissionId],
      pfs.[dimFormId],
      df.sourceId,
      pfs.[submissionId],
      pfs.[certId],
      pfs.[dateSubmitted],
      pfs.[notes],
      pfs.[properties],
      pf.[displayName],
      attachmentInfo.attachments
    ORDER BY pfs.[dateSubmitted] DESC;
END
GO

-- ----------------------------
-- procedure structure for spPublicFormSubmissionDocuments_Get
-- ----------------------------
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[portal].[spPublicFormSubmissionDocuments_Get]') AND type IN ('P', 'PC', 'RF', 'X'))
    DROP PROCEDURE [portal].[spPublicFormSubmissionDocuments_Get]
GO

CREATE PROCEDURE [portal].[spPublicFormSubmissionDocuments_Get]
    @dimFormId INT,
    @psubmissionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        pfs.[psubmissionId],
        pfs.[dimFormId],
        pfs.[submissionId],
        pf.[displayName] AS formName,
        ISNULL(fq.questionLabel, '') AS question,
        COALESCE(fsd.displayName, d.title, '') AS documentName,
        d.id AS documentId,
        d.container,
        d.blobName
    FROM [portal].[PublicFormSubmissions] AS pfs
    INNER JOIN [portal].[PublicForms] AS pf
        ON pf.[dimFormId] = pfs.[dimFormId]
    INNER JOIN Dimension.Form AS df
        ON df.id = pf.dimFormId
    INNER JOIN portal.FormSubmissionDocuments AS fsd
        ON fsd.submissionId = pfs.submissionId
       AND fsd.formId = df.sourceId
    INNER JOIN documents.Document AS d
        ON d.id = fsd.documentId
    LEFT JOIN portal.FormQuestions AS fq
        ON fq.questionId = fsd.questionId
       AND fq.formId = fsd.formId
    WHERE (pfs.[isDeleted] = 0 OR pfs.[isDeleted] IS NULL)
      AND pfs.[dimFormId] = @dimFormId
      AND pfs.[psubmissionId] = @psubmissionId
    ORDER BY question, documentName;
END
GO
