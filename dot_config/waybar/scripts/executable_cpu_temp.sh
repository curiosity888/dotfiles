# chezmoi: executable=true
#!/bin/bash

critical_temp=100

for hwmon in /sys/class/hwmon/hwmon*; do
    if grep -q "coretemp" "$hwmon/name"; then
        temp=$(cat "$hwmon/temp1_input")
        temp_c=$((temp / 1000))
        icon=""
        color="#ffffff"

        if [ "$temp_c" -ge "$critical_temp" ]; then
            icon=""
            color="#ff5555"
        fi

        echo "{\"text\": \"$icon ${temp_c}°C\", \"class\": \"temperature\", \"tooltip\": \"CPU Temp: ${temp_c}°C\", \"color\": \"$color\"}"
        exit 0
    fi
done

echo '{"text": "N/A", "class": "temperature", "color": "#999999"}'


