CREATE OR ALTER PROCEDURE [dbo].[sp_GetRoleEntityPermissions]
    @RoleId   BIGINT,
    @EntityId BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -------------------------------------------------------------------------
    -- 1) Verificar que el rol exista y esté activo
    -------------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM Role r
        WHERE r.id_role    = @RoleId
          AND r.role_active = 1
    )
    BEGIN
        RAISERROR('El rol no existe o está inactivo.', 16, 1);
        RETURN;
    END;

    -------------------------------------------------------------------------
    -- 2) CTE para tomar datos del rol (por si requieres más información)
    -------------------------------------------------------------------------
    ;WITH RoleBase AS (
        SELECT
            r.id_role
        FROM Role r
        WHERE r.id_role = @RoleId
    ),
    -------------------------------------------------------------------------
    -- 3) CTE para recoger los permisos directos de ese rol en PermiRole
    --    (solo registros con perol_include=1) filtrando la entidad solicitada.
    -------------------------------------------------------------------------
    DirectRolePerms AS (
        SELECT 
            p.can_create,
            p.can_read,
            p.can_update,
            p.can_delete,
            p.can_import,
            p.can_export
        FROM RoleBase rb
        INNER JOIN PermiRole pr
            ON rb.id_role = pr.role_id
        INNER JOIN Permission p
            ON pr.permission_id = p.id_permi
        WHERE pr.perol_include   = 1
          AND pr.entitycatalog_id = @EntityId
          -- Si quisieras solo a nivel de ENTIDAD, incluirías 
          -- AND pr.perol_record IS NULL
          -- Si también contemplas perol_record, ajusta la lógica.
    )
    -------------------------------------------------------------------------
    -- 4) SELECT final:
    --    - Muestra nombre y descripción de la entidad (opcional).
    --    - Suma (MAX) los bits de permiso del rol.
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

    FROM DirectRolePerms
    CROSS JOIN EntityCatalog ec
    WHERE ec.id_entit = @EntityId
    GROUP BY ec.entit_name, ec.entit_descrip;
END;
GO