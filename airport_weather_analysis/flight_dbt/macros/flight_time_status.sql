{% macro flight_time_status(column_name) %}

case
    when {{ column_name }} is null
        then 'unknown'

    when {{ column_name }} <= 0
        then 'on_time'

    when {{ column_name }} <= 15
        then 'minor_delay'

    else 'delayed'
end

{% endmacro %}