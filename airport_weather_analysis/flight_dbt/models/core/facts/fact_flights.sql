{{ config(
    materialized='incremental',
    unique_key='flight_key',
    incremental_strategy='merge',
    on_schema_change='append_new_columns'
) }}

with arrivals_api as (

    select
        flight_number,
        call_sign,
        flight_status,
        is_cargo,
        lower(trim(direction)) as flight_direction,

        upper(trim(airline_iata)) as airline_iata,
        upper(trim(airline_icao)) as airline_icao,

        aircraft_model,
        upper(trim(aircraft_registration)) as aircraft_registration,

        upper(trim(departure_airport_iata)) as airport_departure_iata,
        upper(trim(airport_code))           as airport_arrival_iata,

        scheduled_departure_utc,
        revised_departure_utc as actual_departure_utc,

        scheduled_arrival_utc,
        revised_arrival_utc as actual_arrival_utc

    from {{ ref('stg_aerodatabox_arrivals') }}

),

arrivals_parquet as (

    select
        flight_number,
        call_sign,
        flight_status,
        is_cargo,
        lower(trim(direction)) as flight_direction,

        upper(trim(airline_iata)) as airline_iata,
        upper(trim(airline_icao)) as airline_icao,

        aircraft_model,
        upper(trim(aircraft_registration)) as aircraft_registration,

        upper(trim(departure_airport_iata)) as airport_departure_iata,
        upper(trim(airport_code))           as airport_arrival_iata,

        scheduled_departure_utc,
        revised_departure_utc as actual_departure_utc,

        scheduled_arrival_utc,
        revised_arrival_utc as actual_arrival_utc

    from {{ ref('stg_parquet_arrivals') }}

),

departures_api as (

    select
        flight_number,
        call_sign,
        flight_status,
        is_cargo,
        lower(trim(direction)) as flight_direction,

        upper(trim(airline_iata)) as airline_iata,
        upper(trim(airline_icao)) as airline_icao,

        aircraft_model,
        upper(trim(aircraft_registration)) as aircraft_registration,

        upper(trim(airport_code))           as airport_departure_iata,
        upper(trim(arrival_airport_iata))   as airport_arrival_iata,

        scheduled_departure_utc,
        revised_departure_utc as actual_departure_utc,

        scheduled_arrival_utc,
        revised_arrival_utc as actual_arrival_utc

    from {{ ref('stg_aerodatabox_departures') }}

),

departures_parquet as (

    select
        flight_number,
        call_sign,
        flight_status,
        is_cargo,
        lower(trim(direction)) as flight_direction,

        upper(trim(airline_iata)) as airline_iata,
        upper(trim(airline_icao)) as airline_icao,

        aircraft_model,
        upper(trim(aircraft_registration)) as aircraft_registration,

        upper(trim(airport_code))         as airport_departure_iata,
        upper(trim(arrival_airport_iata)) as airport_arrival_iata,

        scheduled_departure_utc,
        revised_departure_utc as actual_departure_utc,

        scheduled_arrival_utc,
        revised_arrival_utc as actual_arrival_utc

    from {{ ref('stg_parquet_departures') }}

),

arrivals_union as (

    select * from arrivals_api
    union all
    select * from arrivals_parquet

),

departures_union as (

    select * from departures_api
    union all
    select * from departures_parquet

),

flights_union as (

    select * from arrivals_union
    union all
    select * from departures_union

),

deduped as (

    select *
    from (
        select
            *,
            row_number() over (
                partition by
                    airline_iata,
                    flight_number,
                    coalesce(scheduled_departure_utc, scheduled_arrival_utc),
                    airport_departure_iata,
                    airport_arrival_iata,
                    flight_direction
                order by
                    actual_departure_utc desc nulls last,
                    actual_arrival_utc   desc nulls last
            ) as rn
        from flights_union
    ) t
    where rn = 1

),

enriched as (

    select
        {{ generate_surrogate_key([
            'airline_iata',
            'flight_number',
            'coalesce(scheduled_departure_utc, scheduled_arrival_utc)',
            'airport_departure_iata',
            'airport_arrival_iata',
            'flight_direction'
        ]) }} as flight_key,

        flight_number,
        call_sign,
        flight_status,
        is_cargo,
        flight_direction,

        airline_iata,
        airline_icao,

        aircraft_model,
        aircraft_registration,

        airport_departure_iata,
        airport_arrival_iata,

        scheduled_departure_utc,
        actual_departure_utc,

        scheduled_arrival_utc,
        actual_arrival_utc,

        case
            when actual_departure_utc is not null
             and scheduled_departure_utc is not null
            then round(
                cast(
                    extract(epoch from (actual_departure_utc - scheduled_departure_utc))
                    as numeric
                ) / 60.0,
                2
            )
        end as departure_delay_minutes,

        case
            when actual_arrival_utc is not null
             and scheduled_arrival_utc is not null
            then round(
                cast(
                    extract(epoch from (actual_arrival_utc - scheduled_arrival_utc))
                    as numeric
                ) / 60.0,
                2
            )
        end as arrival_delay_minutes,

        case
            when flight_direction = 'departure' then scheduled_departure_utc
            when flight_direction = 'arrival'   then scheduled_arrival_utc
        end as operation_ts,

        case
            when flight_direction = 'departure' then cast(date(scheduled_departure_utc) as date)
            when flight_direction = 'arrival'   then cast(date(scheduled_arrival_utc)   as date)
        end as operation_date,

        cast(
            extract(
                hour from
                case
                    when flight_direction = 'departure' then scheduled_departure_utc
                    when flight_direction = 'arrival'   then scheduled_arrival_utc
                end
            )
            as integer
        ) as operation_hour,

        trim(
            to_char(
                case
                    when flight_direction = 'departure' then scheduled_departure_utc
                    when flight_direction = 'arrival'   then scheduled_arrival_utc
                end,
                'Day'
            )
        ) as operation_day_of_week

    from deduped

),

final as (

    select
        flight_key,

        flight_number,
        call_sign,
        flight_status,
        is_cargo,
        flight_direction,

        airline_iata,
        airline_icao,

        aircraft_model,
        aircraft_registration,

        airport_departure_iata,
        airport_arrival_iata,

        scheduled_departure_utc,
        actual_departure_utc,

        scheduled_arrival_utc,
        actual_arrival_utc,

        departure_delay_minutes,
        arrival_delay_minutes,

        operation_ts,
        operation_date,
        operation_hour,
        operation_day_of_week,

        {{ flight_time_status('departure_delay_minutes') }}
            as departure_time_status,

        {{ flight_time_status('arrival_delay_minutes') }}
            as arrival_time_status

    from enriched

)

select * from final