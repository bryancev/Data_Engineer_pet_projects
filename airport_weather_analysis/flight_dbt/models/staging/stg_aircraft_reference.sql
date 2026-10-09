select
    nullif(nullif(trim("aircraft_type"), ''), '\N') :: text as aircraft_type,
    nullif(nullif(trim("manufacturer"), ''), '\N')  :: text as manufacturer,

    "seats"    :: integer as seats,
    "range_km" :: integer as range_km,

    nullif(nullif(trim("category"), ''), '\N') :: text as category,

    _load_dt as source_loaded_at

from {{ source('raw', 'aircraft_reference') }}