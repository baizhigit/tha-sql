
-- льготы по городам

SELECT
    *
FROM concession_validations AS con_val
WHERE con_val."concessionGroupId" IN (
    SELECT
        DISTINCT(con_gr.id)
    FROM public.cities AS city
    INNER JOIN concession_categories AS con_cat
        ON con_cat."cityId" = city.id
    INNER JOIN concession_subcategories AS con_sub
        ON con_sub."concessionCategoryId" = con_cat.id
    INNER JOIN concessions AS con
        ON con."subcategoryId" = con_sub.id
    INNER JOIN concession_groups AS con_gr
        ON con."groupId" = con_gr.id
    WHERE city.name = 'Сарань'
        AND con_cat.id IN (12, 14)
        AND con_sub.id != 51
)



DELETE FROM concession_validations AS con_val
WHERE con_val."concessionGroupId" IN (
    SELECT
        DISTINCT(con_gr.id)
    FROM public.cities AS city
    INNER JOIN concession_categories AS con_cat
        ON con_cat."cityId" = city.id
    INNER JOIN concession_subcategories AS con_sub
        ON con_sub."concessionCategoryId" = con_cat.id
    INNER JOIN concessions AS con
        ON con."subcategoryId" = con_sub.id
    INNER JOIN concession_groups AS con_gr
        ON con."groupId" = con_gr.id
    WHERE city.name = 'Сарань'
        AND con_cat.id IN (12, 14)
        AND con_sub.id != 51
)
