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
    -- 2) Obtener los registros permitidos para el usuario en la entidad padre
    -------------------------------------------------------------------------
    ;WITH AccessibleRecords AS (
        SELECT er.child_record_id
        FROM UserCompany uc
        INNER JOIN EntityRelationship er
            ON uc.company_id = er.parent_record_id
        WHERE uc.user_id = @UserId
          AND uc.useco_active = 1
          AND er.child_entity_id = @EntityId
    ),

    -------------------------------------------------------------------------
    -- 3) Permisos directos a nivel de ENTIDAD (PermiUser)
    -------------------------------------------------------------------------
    EntityPerms AS (
        SELECT 
            p.can_create,
            p.can_read,
            p.can_update,
            p.can_delete,
            p.can_import,
            p.can_export
        FROM UserCompany uc
        INNER JOIN PermiUser pu
            ON uc.id_useco = pu.usercompany_id
        INNER JOIN Permission p
            ON pu.permission_id = p.id_permi
        WHERE uc.user_id       = @UserId
          AND uc.useco_active  = 1
          AND pu.peusr_include = 1
          AND pu.entitycatalog_id = @EntityId
    ),

    -------------------------------------------------------------------------
    -- 4) Permisos heredados por ROLES a nivel de ENTIDAD (PermiRole)
    -------------------------------------------------------------------------
    RoleEntityPerms AS (
        SELECT 
            p.can_create,
            p.can_read,
            p.can_update,
            p.can_delete,
            p.can_import,
            p.can_export
        FROM UserRole ur
        INNER JOIN PermiRole pr
            ON ur.role_id = pr.role_id
        INNER JOIN Permission p
            ON pr.permission_id = p.id_permi
        WHERE ur.user_id       = @UserId
          AND pr.perol_include = 1
          AND pr.entitycatalog_id = @EntityId
    ),

    -------------------------------------------------------------------------
    -- 5) Combinar permisos de usuario directo y heredado por roles
    -------------------------------------------------------------------------
    AllPerms AS (
        SELECT * FROM EntityPerms
        UNION ALL
        SELECT * FROM RoleEntityPerms
    )

    -------------------------------------------------------------------------
    -- 6) SELECT final, unimos con EntityCatalog y filtramos por registros accesibles
    -------------------------------------------------------------------------
    SELECT 
        ec.entit_name,
        ec.entit_descrip,

        ISNULL(MAX(CASE WHEN can_create = 1 THEN 1 ELSE 0 END), 0) AS can_create,
        ISNULL(MAX(CASE WHEN can_read   = 1 THEN 1 ELSE 0 END), 0) AS can_read,
        ISNULL(MAX(CASE WHEN can_update = 1 THEN 1 ELSE 0 END), 0) AS can_update,
        ISNULL(MAX(CASE WHEN can_delete = 1 THEN 1 ELSE 0 END), 0) AS can_delete,
        ISNULL(MAX(CASE WHEN can_import = 1 THEN 1 ELSE 0 END), 0) AS can_import,
        ISNULL(MAX(CASE WHEN can_export = 1 THEN 1 ELSE 0 END), 0) AS can_export

    FROM AllPerms
    CROSS JOIN EntityCatalog ec
    WHERE ec.id_entit = @EntityId
      AND EXISTS (
          SELECT 1
          FROM AccessibleRecords ar
          WHERE ar.child_record_id = ec.id_entit
      )
    GROUP BY ec.entit_name, ec.entit_descrip;
END;
GO