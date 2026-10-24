{% macro range_category(column_name, rules, default_value) %}

case

    {% for rule in rules %}

        when {{ column_name }} {{ rule.operator }} {{ rule.value }}
            then '{{ rule.label }}'

    {% endfor %}

    else '{{ default_value }}'

end

{% endmacro %}