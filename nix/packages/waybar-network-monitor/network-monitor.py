import subprocess
import sys
from time import sleep

### Configuration

refresh_interval = 500  # in milliseconds
rx_min = 200 * 1024  # 200 KB, the min download speed
initial_rx_max = 1 * 1024**2  # 1 MB, initial max download speed
tx_min = 200 * 1024  # 200 KB, the min upload speed
initial_tx_max = 1 * 1024**2  # 1 MB, initial max upload speed
decay_factor = 0.95  # how fast the max decreases when traffic is lower
growth_factor = 1.2  # how much to increase max when traffic exceeds it
rx_color = "#0080c0"  # blue, the color for download speed
tx_color = "#fa7070"  # red, the color for upload speed
scale_change_delay = 3000  # minimum time in ms before changing scale (to avoid spikes)

### End Configuration


def default_interface():
    process = subprocess.run(
        ["ip", "route"], check=True, text=True, capture_output=True
    )
    for line in process.stdout.splitlines():
        if line.startswith("default via"):
            return line.split()[4]
    raise RuntimeError("No default interface found")


def get_rx_tx_bytes(iface):
    with open("/proc/net/dev") as f:
        for line in f:
            line = line.strip()
            if not line.startswith(f"{iface}:"):
                continue
            rx_bytes = int(line.split()[1])
            tx_bytes = int(line.split()[9])
            return rx_bytes, tx_bytes
    raise RuntimeError("Interface not found")


def format_bytes(bytes_per_sec):
    """Format bytes per second into human readable format"""
    units = ['B/s', 'KB/s', 'MB/s', 'GB/s']
    unit_index = 0
    value = float(bytes_per_sec)

    while value >= 1024 and unit_index < len(units) - 1:
        value /= 1024
        unit_index += 1

    # Format with 2 decimals, removing trailing zeros
    formatted = f"{value:.2f}".rstrip('0').rstrip('.')
    return f"{formatted} {units[unit_index]}"


def round_to_scale(value, round_up=True):
    """Round value to predetermined scales like 1MB, 5MB, 10MB, 50MB, 100MB, etc."""
    if value <= 0:
        return 1 * 1024**2  # 1 MB minimum

    # Predetermined scales in bytes
    scales = [
        100 * 1024,      # 100 KB
        250 * 1024,      # 250 KB
        500 * 1024,      # 500 KB
        1 * 1024**2,     # 1 MB
        2 * 1024**2,     # 2 MB
        5 * 1024**2,     # 5 MB
        10 * 1024**2,    # 10 MB
        20 * 1024**2,    # 20 MB
        30 * 1024**2,    # 30 MB
        40 * 1024**2,    # 40 MB
        50 * 1024**2,    # 50 MB
        100 * 1024**2,   # 100 MB
        200 * 1024**2,   # 200 MB
        500 * 1024**2,   # 500 MB
        1 * 1024**3,     # 1 GB
    ]

    if round_up:
        # Find the smallest scale that is >= value (round up)
        for scale in scales:
            if scale >= value:
                return scale
        # If value exceeds all scales, return the largest one
        return scales[-1]
    else:
        # Find the largest scale that is <= value (round down)
        for i in range(len(scales) - 1, -1, -1):
            if scales[i] <= value:
                return scales[i]
        # If value is below all scales, return the smallest one
        return scales[0]


def main():
    iface = default_interface()

    rx_bytes, tx_bytes = get_rx_tx_bytes(iface)

    # Dynamic maximums that adapt to usage
    rx_max = initial_rx_max
    tx_max = initial_tx_max

    # Track pending scale changes and time elapsed
    rx_pending_scale = None
    tx_pending_scale = None
    rx_pending_time = 0
    tx_pending_time = 0

    while True:
        prev_rx_bytes, prev_tx_bytes = rx_bytes, tx_bytes
        rx_bytes, tx_bytes = get_rx_tx_bytes(iface)
        rx_current = (rx_bytes - prev_rx_bytes) * 1000 // refresh_interval
        tx_current = (tx_bytes - prev_tx_bytes) * 1000 // refresh_interval

        # Update dynamic maximums with delay
        if rx_current > rx_max:
            # Traffic exceeds current max, calculate new scale
            new_scale = round_to_scale(rx_current * growth_factor, round_up=True)

            if rx_pending_scale == new_scale:
                # Still wanting same scale change, increment time
                rx_pending_time += refresh_interval
                if rx_pending_time >= scale_change_delay:
                    # Enough time has passed, apply the change
                    rx_max = new_scale
                    rx_pending_scale = None
                    rx_pending_time = 0
            else:
                # Different scale needed, restart timer
                rx_pending_scale = new_scale
                rx_pending_time = 0
        else:
            # Traffic is below max, calculate new scale
            new_max = max(rx_current, rx_max * decay_factor, rx_min)
            new_scale = round_to_scale(new_max, round_up=False)

            if new_scale != rx_max:
                # Scale would change
                if rx_pending_scale == new_scale:
                    # Still wanting same scale change, increment time
                    rx_pending_time += refresh_interval
                    if rx_pending_time >= scale_change_delay:
                        # Enough time has passed, apply the change
                        rx_max = new_scale
                        rx_pending_scale = None
                        rx_pending_time = 0
                else:
                    # Different scale needed, restart timer
                    rx_pending_scale = new_scale
                    rx_pending_time = 0
            else:
                # No change needed, reset pending
                rx_pending_scale = None
                rx_pending_time = 0

        if tx_current > tx_max:
            # Traffic exceeds current max, calculate new scale
            new_scale = round_to_scale(tx_current * growth_factor, round_up=True)

            if tx_pending_scale == new_scale:
                # Still wanting same scale change, increment time
                tx_pending_time += refresh_interval
                if tx_pending_time >= scale_change_delay:
                    # Enough time has passed, apply the change
                    tx_max = new_scale
                    tx_pending_scale = None
                    tx_pending_time = 0
            else:
                # Different scale needed, restart timer
                tx_pending_scale = new_scale
                tx_pending_time = 0
        else:
            # Traffic is below max, calculate new scale
            new_max = max(tx_current, tx_max * decay_factor, tx_min)
            new_scale = round_to_scale(new_max, round_up=False)

            if new_scale != tx_max:
                # Scale would change
                if tx_pending_scale == new_scale:
                    # Still wanting same scale change, increment time
                    tx_pending_time += refresh_interval
                    if tx_pending_time >= scale_change_delay:
                        # Enough time has passed, apply the change
                        tx_max = new_scale
                        tx_pending_scale = None
                        tx_pending_time = 0
                else:
                    # Different scale needed, restart timer
                    tx_pending_scale = new_scale
                    tx_pending_time = 0
            else:
                # No change needed, reset pending
                tx_pending_scale = None
                tx_pending_time = 0

        p = 0
        if sys.argv[1] == "down":
            p = int(100.0 * rx_current / rx_max)
            tooltip = f"Download: {format_bytes(rx_current)} / Max: {format_bytes(rx_max)}"
        else:
            p = int(100.0 * tx_current / tx_max)
            tooltip = f"Upload: {format_bytes(tx_current)} / Max: {format_bytes(tx_max)}"
        if p > 100:
            p = 100
        line = f'{{"text": "{p}%", "percentage": {p},"tooltip": "{tooltip}"}}'
        print(line, flush=True)
        sleep(refresh_interval / 1000)  # Convert ms to seconds


if __name__ == "__main__":
    main()
