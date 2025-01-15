ALTER PROCEDURE [dbo].[sp_GetUserCompanyData]
      @UserId   BIGINT,
    @EntityId BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -------------------------------------------------------------------------
    -- 1) Validar que el usuario existe y está activo
    -------------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM [User] AS u
        WHERE u.id_user = @UserId
          AND u.user_is_active = 1
    )
    BEGIN
        RAISERROR('El usuario no existe o está inactivo.', 16, 1);
        RETURN;
    END;

    -------------------------------------------------------------------------
    -- 2) Obtener las sucursales a las que el usuario tiene acceso
    -------------------------------------------------------------------------
    ;WITH AccessibleBranches AS (
        SELECT bo.id_broff, bo.broff_name, bo.broff_code, bo.broff_city, bo.broff_state, bo.broff_country
        FROM UserCompany uc
        INNER JOIN BranchOffice bo
            ON uc.company_id = bo.company_id
        WHERE uc.user_id = @UserId
          AND uc.useco_active = 1
          AND bo.broff_active = 1
    ),

    -------------------------------------------------------------------------
    -- 3) Obtener los centros de costos asociados a esas sucursales
    -------------------------------------------------------------------------
    AccessibleCostCenters AS (
        SELECT cc.id_cosce, cc.cosce_code, cc.cosce_name, cc.cosce_description, cc.cosce_budget, ab.id_broff
        FROM AccessibleBranches ab
        INNER JOIN EntityRelationship er
            ON ab.id_broff = er.parent_record_id
        INNER JOIN CostCenter cc
            ON er.child_record_id = cc.id_cosce
        WHERE er.parent_entity_id = 2
          AND er.child_entity_id = @EntityId
          AND cc.cosce_active = 1
    ),

    -------------------------------------------------------------------------
    -- 4) Permisos directos a nivel de ENTIDAD (PermiUser)
    -------------------------------------------------------------------------
    EntityPerms AS (
        SELECT 
            p.can_create,
            p.can_read,
            p.can_update,
            p.can_delete,
            p.can_import,
            p.can_export,
            cc.id_cosce
        FROM UserCompany uc
        INNER JOIN PermiUser pu
            ON uc.id_useco = pu.usercompany_id
        INNER JOIN Permission p
            ON pu.permission_id = p.id_permi
        INNER JOIN AccessibleCostCenters cc
            ON cc.id_cosce = pu.entitycatalog_id
        WHERE uc.user_id       = @UserId
          AND uc.useco_active  = 1
          AND pu.peusr_include = 1
    ),

    -------------------------------------------------------------------------
    -- 5) Permisos heredados por ROLES a nivel de ENTIDAD (PermiRole)
    -------------------------------------------------------------------------
    RoleEntityPerms AS (
        SELECT 
            p.can_create,
            p.can_read,
            p.can_update,
            p.can_delete,
            p.can_import,
            p.can_export,
            cc.id_cosce
        FROM UserRole ur
        INNER JOIN PermiRole pr
            ON ur.role_id = pr.role_id
        INNER JOIN Permission p
            ON pr.permission_id = p.id_permi
        INNER JOIN AccessibleCostCenters cc
            ON cc.id_cosce = pr.entitycatalog_id
        WHERE ur.user_id       = @UserId
          AND pr.perol_include = 1
    ),

    -------------------------------------------------------------------------
    -- 6) Combinar permisos de usuario directo y heredado por roles
    -------------------------------------------------------------------------
    AllPerms AS (
        SELECT * FROM EntityPerms
        UNION ALL
        SELECT * FROM RoleEntityPerms
    )

    -------------------------------------------------------------------------
    -- 7) SELECT final: Devolver la información de sucursales, centros de costos y permisos
    -------------------------------------------------------------------------
    SELECT 
        ab.broff_name AS branch_name,
        ab.broff_code AS branch_code,
        ab.broff_city AS branch_city,
        ab.broff_state AS branch_state,
        ab.broff_country AS branch_country,

        cc.cosce_code AS cost_center_code,
        cc.cosce_name AS cost_center_name,
        cc.cosce_description AS cost_center_description,
        cc.cosce_budget AS cost_center_budget,

        ISNULL(MAX(CASE WHEN ap.can_create = 1 THEN 1 ELSE 0 END), 0) AS can_create,
        ISNULL(MAX(CASE WHEN ap.can_read   = 1 THEN 1 ELSE 0 END), 0) AS can_read,
        ISNULL(MAX(CASE WHEN ap.can_update = 1 THEN 1 ELSE 0 END), 0) AS can_update,
        ISNULL(MAX(CASE WHEN ap.can_delete = 1 THEN 1 ELSE 0 END), 0) AS can_delete,
        ISNULL(MAX(CASE WHEN ap.can_import = 1 THEN 1 ELSE 0 END), 0) AS can_import,
        ISNULL(MAX(CASE WHEN ap.can_export = 1 THEN 1 ELSE 0 END), 0) AS can_export

    FROM AllPerms ap
    INNER JOIN AccessibleCostCenters cc
        ON ap.id_cosce = cc.id_cosce
    INNER JOIN AccessibleBranches ab
        ON cc.id_broff = ab.id_broff
    GROUP BY 
        ab.broff_name, ab.broff_code, ab.broff_city, ab.broff_state, ab.broff_country,
        cc.cosce_code, cc.cosce_name, cc.cosce_description, cc.cosce_budget;
END;
GO