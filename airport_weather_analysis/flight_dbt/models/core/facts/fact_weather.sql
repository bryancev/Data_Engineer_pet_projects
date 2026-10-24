{{ config(
    materialized='incremental',
    unique_key='weather_key',
    incremental_strategy='merge',
    on_schema_change='append_new_columns'
) }}

with weather_union as (

    select
        source,
        airport_iata,
        loaded_at,
        weather_time_utc,
        temperature_2m_c,
        apparent_temperature_c,
        dewpoint_2m_c,
        relative_humidity_2m_pct,
        precipitation_mm,
        rain_mm,
        snowfall_cm,
        cloudcover_pct,
        cloudcover_low_pct,
        cloudcover_mid_pct,
        cloudcover_high_pct,
        surface_pressure_hpa,
        pressure_msl_hpa,
        visibility_m,
        windspeed_10m_ms,
        windgusts_10m_ms,
        winddirection_10m_deg,
        weathercode,
        weather_description
    from {{ ref('stg_weather_api') }}

    union all

    select
        source,
        airport_iata,
        loaded_at,
        weather_time_utc,
        temperature_2m_c,
        apparent_temperature_c,
        dewpoint_2m_c,
        relative_humidity_2m_pct,
        precipitation_mm,
        rain_mm,
        snowfall_cm,
        cloudcover_pct,
        cloudcover_low_pct,
        cloudcover_mid_pct,
        cloudcover_high_pct,
        surface_pressure_hpa,
        pressure_msl_hpa,
        visibility_m,
        windspeed_10m_ms,
        windgusts_10m_ms,
        winddirection_10m_deg,
        weathercode,
        weather_description
    from {{ ref('stg_weather_history') }}

),

deduped as (

    select *
    from (
        select
            *,
            row_number() over (
                partition by airport_iata, weather_time_utc
                order by loaded_at desc
            ) as rn
        from weather_union
        where airport_iata    is not null
          and weather_time_utc is not null
    ) t
    where rn = 1

),

enriched as (

    select
        {{ generate_surrogate_key([
            'airport_iata',
            'weather_time_utc'
        ]) }} as weather_key,

        airport_iata,
        weather_time_utc,

        cast(temperature_2m_c         as numeric) as temperature_2m_c,
        cast(apparent_temperature_c   as numeric) as apparent_temperature_c,
        cast(dewpoint_2m_c            as numeric) as dewpoint_2m_c,
        cast(relative_humidity_2m_pct as numeric) as relative_humidity_2m_pct,
        cast(precipitation_mm         as numeric) as precipitation_mm,
        cast(rain_mm                  as numeric) as rain_mm,
        cast(snowfall_cm              as numeric) as snowfall_cm,
        cast(cloudcover_pct           as numeric) as cloudcover_pct,
        cast(visibility_m             as numeric) as visibility_m,
        cast(windspeed_10m_ms         as numeric) as windspeed_10m_ms,
        cast(winddirection_10m_deg    as numeric) as winddirection_10m_deg,
        cast(weathercode              as integer) as weathercode,
        weather_description,

        cast(date(weather_time_utc)                        as date)    as weather_date,
        cast(extract(hour from weather_time_utc)           as integer) as weather_hour,
        trim(to_char(weather_time_utc, 'Day'))                         as weather_day_of_week,

        {{ range_category(
            'cast(windspeed_10m_ms as numeric)',
            [
                {'operator': '>=', 'value': 13.9, 'label': 'strong'},
                {'operator': '>=', 'value': 10.8, 'label': 'moderate'},
                {'operator': '>=', 'value': 5.5,  'label': 'light'}
            ],
            'calm'
        ) }} as wind_category,

        {{ range_category(
            'cast(precipitation_mm as numeric)',
            [
                {'operator': '>=', 'value': 10,  'label': 'heavy'},
                {'operator': '>=', 'value': 2.5, 'label': 'moderate'},
                {'operator': '>',  'value': 0,   'label': 'light'}
            ],
            'none'
        ) }} as precipitation_category,

        {{ range_category(
            'cast(rain_mm as numeric)',
            [
                {'operator': '>=', 'value': 10,  'label': 'heavy_rain'},
                {'operator': '>=', 'value': 2.5, 'label': 'moderate_rain'},
                {'operator': '>',  'value': 0,   'label': 'light_rain'}
            ],
            'no_rain'
        ) }} as rain_category,

        {{ range_category(
            'cast(temperature_2m_c as numeric)',
            [
                {'operator': '>=', 'value': 35, 'label': 'extreme_heat'},
                {'operator': '>=', 'value': 30, 'label': 'very_hot'},
                {'operator': '>=', 'value': 25, 'label': 'hot'},
                {'operator': '>=', 'value': 20, 'label': 'warm'}
            ],
            'mild'
        ) }} as temperature_category,

        {{ range_category(
            'cast(cloudcover_pct as numeric)',
            [
                {'operator': '>=', 'value': 90, 'label': 'overcast'},
                {'operator': '>=', 'value': 70, 'label': 'mostly_cloudy'},
                {'operator': '>=', 'value': 40, 'label': 'partly_cloudy'},
                {'operator': '>=', 'value': 10, 'label': 'mostly_clear'}
            ],
            'clear'
        ) }} as cloudcover_category,

        {{ range_category(
            'cast(visibility_m as numeric)',
            [
                {'operator': '<', 'value': 1000,  'label': 'very_poor'},
                {'operator': '<', 'value': 3000,  'label': 'poor'},
                {'operator': '<', 'value': 5000,  'label': 'moderate'},
                {'operator': '<', 'value': 10000, 'label': 'good'}
            ],
            'excellent'
        ) }} as visibility_category,

        coalesce(cast(windspeed_10m_ms  as numeric) >= 13.9, false) as is_strong_wind,
        coalesce(cast(precipitation_mm  as numeric) >= 10,   false) as is_heavy_precipitation,
        coalesce(cast(rain_mm           as numeric) >= 10,   false) as is_heavy_rain,
        coalesce(cast(weathercode       as integer) in (95, 96, 99), false) as has_thunderstorm,
        coalesce(cast(cloudcover_pct    as numeric) >= 90,   false) as is_overcast,
        coalesce(cast(visibility_m      as numeric) < 3000,  false) as is_low_visibility

    from deduped

)

select * from enriched