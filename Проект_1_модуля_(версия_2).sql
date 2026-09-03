/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Деньгина Анна
 * Дата: 24.07.2026
*/


-- Задача 1: Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Категоризация по длительности активности и местоположению
categorization AS(
	SELECT *,
	CASE
		WHEN city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
		ELSE 'ЛенОбл'
	END AS location_group,
	CASE 
		WHEN days_exposition BETWEEN 1 AND 30 THEN ' до 1 месяца'
		WHEN days_exposition BETWEEN 31 AND 90 THEN ' до 3-х месяцев'
		WHEN days_exposition BETWEEN 91 AND 180 THEN ' до полугода'
		WHEN days_exposition > 180 THEN 'более полугода'
		ELSE ' без категории'
	END AS duration_group,
	a.last_price/f.total_area AS cost_per_sqm
	FROM real_estate.flats AS f
	JOIN real_estate.city AS c USING (city_id)
	JOIN real_estate.advertisement AS a USING(id)
	JOIN real_estate.TYPE AS t USING (type_id)
	WHERE EXTRACT(YEAR FROM first_day_exposition::timestamp) BETWEEN 2015 AND 2018 AND t.TYPE = 'город'
	)
-- Основной запрос для сравнения объявлений:
SELECT location_group,
	duration_group,
	COUNT(*) AS count_flats,
	ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY location_group), 2) AS percentage_region,
	ROUND(AVG(cost_per_sqm)::numeric, 2) AS avg_cost_per_sqm,
	ROUND(AVG(total_area)::numeric, 2) AS avg_total_area,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rooms) AS med_rooms,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY balcony) AS med_balcony
FROM categorization AS cat
JOIN filtered_id AS filt USING (id)
GROUP BY location_group, duration_group	
ORDER BY location_group DESC, duration_group;

-- Задача 2: Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Найдем месяц выставления объявления на продажу и месяц его снятия, ограничим временной интервал 2015-2018 гг.:
ex_month AS (
	SELECT *,
		EXTRACT(MONTH FROM first_day_exposition) AS month_from,
		EXTRACT(MONTH FROM first_day_exposition::timestamp + INTERVAL '1days'*days_exposition) AS month_to
	FROM real_estate.advertisement
	WHERE EXTRACT(YEAR FROM first_day_exposition::timestamp) BETWEEN 2015 AND 2018
	),
-- Статистика по месяцу публикации (исключены аномальные значения, применена фильтрация по типу населенного пункта):
month_from_stat AS (
	SELECT month_from AS month,
		COUNT(*) AS count_pub,
		ROUND(AVG(last_price/total_area)::numeric, 2) AS avg_cost_pub,
		ROUND(AVG(total_area)::numeric, 2) AS avg_area_pub
	FROM ex_month AS em
	JOIN filtered_id AS filt USING(id)
	JOIN real_estate.flats AS f USING(id)
	JOIN real_estate.TYPE AS t USING (type_id)
	WHERE t.TYPE = 'город'
	GROUP BY month_from
	ORDER BY month_from),
-- Статистика по месяцу снятия (исключены аномальные значения, применена фильтрация по типу населенного пункта):
month_to_stat AS (
	SELECT month_to AS month,
		COUNT(*) AS count_end,
		ROUND(AVG(last_price/total_area)::numeric, 2) AS avg_cost_end,
		ROUND(AVG(total_area)::numeric, 2) AS avg_area_end
	FROM ex_month AS em
	JOIN filtered_id AS filt USING(id)
	JOIN real_estate.flats AS f USING(id)
	JOIN real_estate.TYPE AS t USING (type_id)
	WHERE t.TYPE = 'город'
	GROUP BY month_to
	ORDER BY month_to)
--Объединение полученных значений в основном запросе:
SELECT 
    fs.month,
    ts.count_end,
    fs.count_pub,
    fs.avg_cost_pub,
    ts.avg_cost_end,
    fs.avg_area_pub,
    ts.avg_area_end
FROM month_from_stat AS fs 
JOIN month_to_stat AS ts ON fs.month = ts.month
ORDER BY fs.month
