ALTER PROCEDURE [dbo].[sp_GetUserCompanyData]
   @UserId   BIGINT,
    @EntityId BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -------------------------------------------------------------------------
    -- 1) Verificar que el usuario exista y esté activo
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
    -- 2) CTE para tomar datos básicos del usuario (principalmente user_is_admin)
    -------------------------------------------------------------------------
    ;WITH UserBase AS (
        SELECT
            u.id_user,
            u.user_is_admin
        FROM [User] u
        WHERE u.id_user = @UserId
    ),
    -------------------------------------------------------------------------
    -- 3) CTE para recoger TODOS los permisos directos de ese usuario, 
    --    en TODAS sus compañías activas, para la entidad solicitada.
    --    Se incluyen sólo los que estén "peusr_include=1".
    -------------------------------------------------------------------------
    DirectPerms AS (
        SELECT 
            p.can_create,
            p.can_read,
            p.can_update,
            p.can_delete,
            p.can_import,
            p.can_export
        FROM UserBase ub
        INNER JOIN UserCompany uc
            ON ub.id_user = uc.user_id
        INNER JOIN PermiUser pu
            ON uc.id_useco = pu.usercompany_id
        INNER JOIN Permission p
            ON pu.permission_id = p.id_permi
        WHERE uc.useco_active   = 1
          AND pu.peusr_include  = 1
          AND pu.entitycatalog_id = @EntityId
    )
    -------------------------------------------------------------------------
    -- 4) SELECT final: 
    --    - Muestra el nombre y descripción de la entidad (si lo deseas).
    --    - Combina (MAX) los bits de permiso.
    --    - Si user_is_admin=1 => todos los permisos = 1.
    -------------------------------------------------------------------------
    SELECT 
        EC.entit_name,
        EC.entit_descrip,

        CASE WHEN (SELECT user_is_admin FROM UserBase) = 1 THEN 1
             ELSE ISNULL(MAX(CASE WHEN can_create = 1 THEN 1 ELSE 0 END), 0)
        END AS can_create,

        CASE WHEN (SELECT user_is_admin FROM UserBase) = 1 THEN 1
             ELSE ISNULL(MAX(CASE WHEN can_read = 1 THEN 1 ELSE 0 END), 0)
        END AS can_read,

        CASE WHEN (SELECT user_is_admin FROM UserBase) = 1 THEN 1
             ELSE ISNULL(MAX(CASE WHEN can_update = 1 THEN 1 ELSE 0 END), 0)
        END AS can_update,

        CASE WHEN (SELECT user_is_admin FROM UserBase) = 1 THEN 1
             ELSE ISNULL(MAX(CASE WHEN can_delete = 1 THEN 1 ELSE 0 END), 0)
        END AS can_delete,

        CASE WHEN (SELECT user_is_admin FROM UserBase) = 1 THEN 1
             ELSE ISNULL(MAX(CASE WHEN can_import = 1 THEN 1 ELSE 0 END), 0)
        END AS can_import,

        CASE WHEN (SELECT user_is_admin FROM UserBase) = 1 THEN 1
             ELSE ISNULL(MAX(CASE WHEN can_export = 1 THEN 1 ELSE 0 END), 0)
        END AS can_export

    FROM DirectPerms
    -- Unimos con EntityCatalog para mostrar info de la entidad
    CROSS JOIN EntityCatalog EC
    WHERE EC.id_entit = @EntityId
    GROUP BY EC.entit_name, EC.entit_descrip;
END;
GO