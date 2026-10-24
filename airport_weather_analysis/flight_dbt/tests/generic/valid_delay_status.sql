{% test valid_delay_status(model, delay_column, status_column) %}

select *
from {{ model }}
where

    -- если задержка NULL, статус должен быть 'unknown'
    (
        {{ delay_column }} is null
        and {{ status_column }} <> 'unknown'
    )

    -- если задержка <= 0, статус должен быть 'on_time'
    or
    (
        {{ delay_column }} <= 0
        and {{ status_column }} <> 'on_time'
    )

    -- если 0 < задержка <= 15, статус должен быть 'minor_delay'
    or
    (
        {{ delay_column }} > 0
        and {{ delay_column }} <= 15
        and {{ status_column }} <> 'minor_delay'
    )

    -- если задержка > 15, статус должен быть 'delayed'
    or
    (
        {{ delay_column }} > 15
        and {{ status_column }} <> 'delayed'
    )

    -- если статус NULL, это тоже ошибка (не должно быть при not_null)
    or
    (
        {{ status_column }} is null
    )

{% endtest %}