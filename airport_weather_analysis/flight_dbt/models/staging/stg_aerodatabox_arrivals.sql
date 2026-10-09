{{ config(
    materialized='table',
    indexes=[
      {'columns': ['airport_code', 'scheduled_arrival_utc']},
      {'columns': ['flight_number']}
    ]
) }}

with source_data as (

    select
        cast(source       as text)        as source,
        cast(airport_code as text)        as airport_code,
        cast(code_type    as text)        as code_type,
        cast(from_local   as timestamptz) as window_from_local,
        cast(to_local     as timestamptz) as window_to_local,
        cast(extracted_at as timestamptz) as loaded_at,
        cast(payload      as jsonb)       as payload

    from {{ source('raw', 'aerodatabox_fids_range') }}

),

arrivals as (

    select
        source,
        airport_code,
        code_type,
        window_from_local,
        window_to_local,
        loaded_at,

        jsonb_array_elements(payload -> 'arrivals') as arrival

    from source_data

    where jsonb_typeof(payload) = 'object'
      and jsonb_typeof(payload -> 'arrivals') = 'array'

),

typed as (

    select
        source,
        airport_code,
        code_type,
        window_from_local,
        window_to_local,
        loaded_at,

        cast('arrival' as text) as direction,

        nullif(arrival ->> 'number',          '') as flight_number,
        nullif(arrival ->> 'status',          '') as flight_status,
        nullif(arrival ->> 'callSign',        '') as call_sign,
        nullif(arrival ->> 'codeshareStatus', '') as codeshare_status,

        nullif(arrival -> 'airline' ->> 'iata', '') as airline_iata,
        nullif(arrival -> 'airline' ->> 'icao', '') as airline_icao,
        nullif(arrival -> 'airline' ->> 'name', '') as airline_name,

        nullif(arrival -> 'aircraft' ->> 'reg',   '') as aircraft_registration,
        nullif(arrival -> 'aircraft' ->> 'modeS', '') as aircraft_modes,
        nullif(arrival -> 'aircraft' ->> 'model', '') as aircraft_model,

        nullif(arrival -> 'arrival' ->> 'terminal', '') as arrival_terminal,

        cast(arrival -> 'arrival' -> 'scheduledTime' ->> 'utc'   as timestamptz) as scheduled_arrival_utc,
        cast(arrival -> 'arrival' -> 'scheduledTime' ->> 'local' as timestamptz) as scheduled_arrival_local,
        cast(arrival -> 'arrival' -> 'revisedTime'   ->> 'utc'   as timestamptz) as revised_arrival_utc,
        cast(arrival -> 'arrival' -> 'revisedTime'   ->> 'local' as timestamptz) as revised_arrival_local,

        nullif(arrival -> 'departure' -> 'airport' ->> 'iata',     '') as departure_airport_iata,
        nullif(arrival -> 'departure' -> 'airport' ->> 'icao',     '') as departure_airport_icao,
        nullif(arrival -> 'departure' -> 'airport' ->> 'name',     '') as departure_airport_city,
        nullif(arrival -> 'departure' -> 'airport' ->> 'timeZone', '') as departure_airport_timezone,
        nullif(arrival -> 'departure' ->> 'terminal', '') as departure_terminal,

        cast(arrival -> 'departure' -> 'scheduledTime' ->> 'utc'   as timestamptz) as scheduled_departure_utc,
        cast(arrival -> 'departure' -> 'scheduledTime' ->> 'local' as timestamptz) as scheduled_departure_local,
        cast(arrival -> 'departure' -> 'revisedTime'   ->> 'utc'   as timestamptz) as revised_departure_utc,
        cast(arrival -> 'departure' -> 'revisedTime'   ->> 'local' as timestamptz) as revised_departure_local,

        case
            when (arrival ->> 'isCargo') in ('true', 'false')
                then cast(arrival ->> 'isCargo' as boolean)
            else null
        end as is_cargo,

        arrival as arrival_payload

    from arrivals

),

deduplicated as (

    select
        *,
        row_number() over (
            partition by airport_code, flight_number, scheduled_arrival_utc
            order by loaded_at desc
        ) as rn
    from typed

),

final as (

    select
        source,
        airport_code,
        code_type,
        window_from_local,
        window_to_local,
        loaded_at,
        direction,

        flight_number,
        flight_status,
        call_sign,
        codeshare_status,

        airline_iata,
        airline_icao,
        airline_name,

        aircraft_registration,
        aircraft_modes,
        aircraft_model,

        arrival_terminal,
        scheduled_arrival_utc,
        scheduled_arrival_local,
        revised_arrival_utc,
        revised_arrival_local,

        departure_airport_iata,
        departure_airport_icao,
        departure_airport_city,
        departure_airport_timezone,
        departure_terminal,

        scheduled_departure_utc,
        scheduled_departure_local,
        revised_departure_utc,
        revised_departure_local,

        is_cargo,

        arrival_payload

    from deduplicated
    where rn = 1

)

select * from final