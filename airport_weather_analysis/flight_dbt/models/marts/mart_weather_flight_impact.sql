{{ config(materialized='table') }}

with weather_observations as (

    select
        weather_key,
        weather_time_utc,

        weather_date,
        weather_hour,
        weather_day_of_week,

        temperature_2m_c,
        apparent_temperature_c,
        dewpoint_2m_c,
        relative_humidity_2m_pct,

        precipitation_mm,
        rain_mm,
        snowfall_cm,

        cloudcover_pct,
        visibility_m,

        windspeed_10m_ms,
        winddirection_10m_deg,

        weathercode,
        weather_description,

        wind_category,
        precipitation_category,
        rain_category,
        temperature_category,
        cloudcover_category,
        visibility_category,

        is_strong_wind,
        is_heavy_precipitation,
        is_heavy_rain,
        has_thunderstorm,
        is_overcast,
        is_low_visibility

    from {{ ref('fact_weather') }}

),

airport_operations as (

    select
        flight_key,
        flight_number,
        airline_iata,

        flight_direction as operation_type,

        operation_ts,

        case flight_direction
            when 'departure' then departure_delay_minutes
            when 'arrival'   then arrival_delay_minutes
        end as delay_minutes,

        case flight_direction
            when 'departure' then departure_time_status
            when 'arrival'   then arrival_time_status
        end as time_status

    from {{ ref('fact_flights') }}

    where
        (airport_departure_iata = 'HKT' and flight_direction = 'departure')
     or (airport_arrival_iata   = 'HKT' and flight_direction = 'arrival')

),

weather_operations as (

    select
        w.weather_key,
        w.weather_time_utc,

        w.weather_date,
        w.weather_hour,
        w.weather_day_of_week,

        w.temperature_2m_c,
        w.apparent_temperature_c,
        w.dewpoint_2m_c,
        w.relative_humidity_2m_pct,

        w.precipitation_mm,
        w.rain_mm,
        w.snowfall_cm,

        w.cloudcover_pct,
        w.visibility_m,

        w.windspeed_10m_ms,
        w.winddirection_10m_deg,

        w.weathercode,
        w.weather_description,

        w.wind_category,
        w.precipitation_category,
        w.rain_category,
        w.temperature_category,
        w.cloudcover_category,
        w.visibility_category,

        w.is_strong_wind,
        w.is_heavy_precipitation,
        w.is_heavy_rain,
        w.has_thunderstorm,
        w.is_overcast,
        w.is_low_visibility,

        o.flight_key,
        o.flight_number,
        o.airline_iata,

        o.operation_type,
        o.operation_ts,

        o.delay_minutes,
        o.time_status

    from weather_observations w

    left join airport_operations o
        on o.operation_ts >= w.weather_time_utc - interval '30 minutes'
       and o.operation_ts <  w.weather_time_utc + interval '30 minutes'

),

aggregated as (

    select
        weather_key,
        weather_time_utc,

        weather_date,
        weather_hour,
        weather_day_of_week,

        operation_type,

        temperature_2m_c,
        apparent_temperature_c,
        dewpoint_2m_c,
        relative_humidity_2m_pct,

        precipitation_mm,
        rain_mm,
        snowfall_cm,

        cloudcover_pct,
        visibility_m,

        windspeed_10m_ms,
        winddirection_10m_deg,

        weathercode,
        weather_description,

        wind_category,
        precipitation_category,
        rain_category,
        temperature_category,
        cloudcover_category,
        visibility_category,

        is_strong_wind,
        is_heavy_precipitation,
        is_heavy_rain,
        has_thunderstorm,
        is_overcast,
        is_low_visibility,

        count(flight_key) as total_operations,

        round(avg(delay_minutes), 2) as avg_delay_minutes,

        round(
            avg(delay_minutes) filter (where delay_minutes > 0),
            2
        ) as avg_positive_delay_minutes,

        count(flight_key) filter (where time_status = 'delayed')     as delayed_operations,
        count(flight_key) filter (where time_status = 'minor_delay') as minor_delay_operations,
        count(flight_key) filter (where time_status = 'on_time')     as ontime_operations,
        count(flight_key) filter (where time_status = 'unknown')     as unknown_operations,

        round(
            cast(count(flight_key) filter (where time_status = 'delayed') as numeric)
            / nullif(count(flight_key), 0),
            4
        ) as delay_rate,

        round(
            cast(count(flight_key) filter (where time_status = 'on_time') as numeric)
            / nullif(count(flight_key), 0),
            4
        ) as ontime_rate

    from weather_operations

    group by
        weather_key,
        weather_time_utc,
        weather_date,
        weather_hour,
        weather_day_of_week,
        operation_type,

        temperature_2m_c,
        apparent_temperature_c,
        dewpoint_2m_c,
        relative_humidity_2m_pct,

        precipitation_mm,
        rain_mm,
        snowfall_cm,

        cloudcover_pct,
        visibility_m,

        windspeed_10m_ms,
        winddirection_10m_deg,

        weathercode,
        weather_description,

        wind_category,
        precipitation_category,
        rain_category,
        temperature_category,
        cloudcover_category,
        visibility_category,

        is_strong_wind,
        is_heavy_precipitation,
        is_heavy_rain,
        has_thunderstorm,
        is_overcast,
        is_low_visibility

)

select *
from aggregated
where operation_type is not null