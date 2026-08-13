
-- вся информация по картам 

SELECT
    t.nn,
    t.title_ru,
    t.title_kk,
    t.title_en,
    c.primary_color,
    c.bg_color,
    c.text_color,
    c.icon_color,
    c.shadow_color,
    (j.key)::INT   AS city_id,
    (j.value->>'tripCost')::INT AS trip_cost,
    (j.value->>'passCost')::INT AS pass_cost
FROM ct_card_titles AS t
LEFT JOIN ct_card_colors AS c
    ON c.nn = t.nn
    AND c.is_virtual = FALSE
JOIN ct_card_tariffs AS tr
    ON tr.nn = t.nn
CROSS JOIN LATERAL jsonb_each(tr.tariffs_json) AS j(key, value)
-- WHERE t.nn = '60.50'
ORDER BY city_id;