select
    nullif(nullif(trim("Name"), ''), '-')        :: text as airline_name,
    nullif(nullif(trim("IATA"), ''), '-')        :: text as iata_code,
    nullif(nullif(trim("ICAO"), ''), '-')        :: text as icao_code,
    nullif(nullif(trim("Callsign"), ''), '-')    :: text as callsign,
    nullif(nullif(trim("Country"), ''), '-')     :: text as airline_country,

    case
        when lower(trim("Active")) in ('y', 'yes', 'true', '1') then true
        when lower(trim("Active")) in ('n', 'no', 'false', '0') then false
        else null
    end as airline_active,
    _load_dt as source_loaded_at

from {{ source('raw', 'airlines') }}