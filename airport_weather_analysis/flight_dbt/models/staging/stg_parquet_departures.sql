{{ config(
    materialized='table',
    indexes=[
      {'columns': ['airport_code', 'scheduled_departure_utc']},
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

    from {{ source('raw', 'flights_2025') }}

),

departures as (

    select
        source,
        airport_code,
        code_type,
        window_from_local,
        window_to_local,
        loaded_at,

        jsonb_array_elements(payload -> 'departures') as departure

    from source_data

    where jsonb_typeof(payload) = 'object'
      and jsonb_typeof(payload -> 'departures') = 'array'

),

typed as (

    select
        source,
        airport_code,
        code_type,
        window_from_local,
        window_to_local,
        loaded_at,

        cast('departure' as text) as direction,

        nullif(departure ->> 'number',          '') as flight_number,
        nullif(departure ->> 'status',          '') as flight_status,
        nullif(departure ->> 'callSign',        '') as call_sign,
        nullif(departure ->> 'codeshareStatus', '') as codeshare_status,

        nullif(departure -> 'airline' ->> 'iata', '') as airline_iata,
        nullif(departure -> 'airline' ->> 'icao', '') as airline_icao,
        nullif(departure -> 'airline' ->> 'name', '') as airline_name,

        nullif(departure -> 'aircraft' ->> 'reg',   '') as aircraft_registration,
        nullif(departure -> 'aircraft' ->> 'modeS', '') as aircraft_modes,
        nullif(departure -> 'aircraft' ->> 'model', '') as aircraft_model,

        nullif(departure -> 'departure' ->> 'terminal', '') as departure_terminal,

        cast(departure -> 'departure' -> 'scheduledTime' ->> 'utc'   as timestamptz) as scheduled_departure_utc,
        cast(departure -> 'departure' -> 'scheduledTime' ->> 'local' as timestamptz) as scheduled_departure_local,
        cast(departure -> 'departure' -> 'revisedTime'   ->> 'utc'   as timestamptz) as revised_departure_utc,
        cast(departure -> 'departure' -> 'revisedTime'   ->> 'local' as timestamptz) as revised_departure_local,

        nullif(departure -> 'arrival' -> 'airport' ->> 'iata',     '') as arrival_airport_iata,
        nullif(departure -> 'arrival' -> 'airport' ->> 'icao',     '') as arrival_airport_icao,
        nullif(departure -> 'arrival' -> 'airport' ->> 'name',     '') as arrival_airport_city,
        nullif(departure -> 'arrival' -> 'airport' ->> 'timeZone', '') as arrival_airport_timezone,

        nullif(departure -> 'arrival' ->> 'terminal', '') as arrival_terminal,

        cast(departure -> 'arrival' -> 'scheduledTime' ->> 'utc'   as timestamptz) as scheduled_arrival_utc,
        cast(departure -> 'arrival' -> 'scheduledTime' ->> 'local' as timestamptz) as scheduled_arrival_local,
        cast(departure -> 'arrival' -> 'revisedTime'   ->> 'utc'   as timestamptz) as revised_arrival_utc,
        cast(departure -> 'arrival' -> 'revisedTime'   ->> 'local' as timestamptz) as revised_arrival_local,

        case
            when (departure ->> 'isCargo') in ('true', 'false')
                then cast(departure ->> 'isCargo' as boolean)
            else null
        end as is_cargo,

        departure as departure_payload

    from departures

),

deduplicated as (

    select
        *,
        row_number() over (
            partition by airport_code, flight_number, scheduled_departure_utc
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

        departure_terminal,
        scheduled_departure_utc,
        scheduled_departure_local,
        revised_departure_utc,
        revised_departure_local,

        arrival_airport_iata,
        arrival_airport_icao,
        arrival_airport_city,
        arrival_airport_timezone,
        arrival_terminal,

        scheduled_arrival_utc,
        scheduled_arrival_local,
        revised_arrival_utc,
        revised_arrival_local,

        is_cargo,

        departure_payload

    from deduplicated
    where rn = 1

)

select * from final