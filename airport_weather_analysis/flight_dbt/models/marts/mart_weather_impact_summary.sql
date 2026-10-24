{{ config(materialized='table') }}

with aggregated_weather_impact as (

    select
        operation_type,

        case
            when
                is_strong_wind
                or is_heavy_precipitation
                or is_heavy_rain
                or has_thunderstorm
                or is_low_visibility
            then 'adverse_weather'
            else 'normal_weather'
        end as weather_condition,

        total_operations,

        delayed_operations,
        minor_delay_operations,
        ontime_operations,
        unknown_operations,

        avg_delay_minutes,
        avg_positive_delay_minutes,

        delay_rate,
        ontime_rate,

        windspeed_10m_ms,
        precipitation_mm,
        temperature_2m_c,
        visibility_m

    from {{ ref('mart_weather_flight_impact') }}

),

final as (

    select
        operation_type,
        weather_condition,

        count(*) as total_weather_hours,

        sum(total_operations) as total_operations,

        sum(delayed_operations)     as delayed_operations,
        sum(minor_delay_operations) as minor_delay_operations,
        sum(ontime_operations)      as ontime_operations,
        sum(unknown_operations)     as unknown_operations,

        -- средневзвешенное по числу операций, а не среднее средних
        round(
            sum(avg_delay_minutes * total_operations)
            / nullif(sum(total_operations), 0),
            2
        ) as avg_delay_minutes,

        round(
            sum(avg_positive_delay_minutes * total_operations)
            / nullif(sum(total_operations), 0),
            2
        ) as avg_positive_delay_minutes,

        -- считаем доли от суммарного числа операций, а не среднее долей
        round(
            cast(sum(delayed_operations) as numeric)
            / nullif(sum(total_operations), 0),
            4
        ) as delay_rate,

        round(
            cast(sum(ontime_operations) as numeric)
            / nullif(sum(total_operations), 0),
            4
        ) as ontime_rate,

        round(avg(windspeed_10m_ms),  2) as avg_wind_speed,
        round(avg(precipitation_mm),  2) as avg_precipitation,
        round(avg(temperature_2m_c),  2) as avg_temperature,
        round(avg(visibility_m),      0) as avg_visibility_m

    from aggregated_weather_impact

    group by
        operation_type,
        weather_condition

)

select * from final
