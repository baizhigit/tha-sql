SELECT
    has_table_privilege('ct_card_tariffs', 'SELECT') AS can_select,
    has_table_privilege('ct_card_tariffs', 'INSERT') AS can_insert,
    has_table_privilege('ct_card_tariffs', 'UPDATE') AS can_update,
    has_table_privilege('ct_card_tariffs', 'DELETE') AS can_delete;