# Combine every per-host signal into ONE Healthchecks verdict per period.
# add() records each metric's pass/fail (last-known, keyed per instance) plus the
# last time its category was seen; push() prunes anything older than the TTL,
# then emits a single `health` metric whose `result` tag routes ok->URL /
# fail->URL/fail and whose `message` field is the full FAIL-first snapshot.
# reset() is intentionally a no-op: state persists across periods so a slow input
# (e.g. SMART) or a brief gap doesn't blink the verdict, and a category that
# stops arriving trips `stale:<cat>` instead of masquerading as healthy.
#
# Constants injected from Nix: disk_full, ssh_cert_min_seconds, ttl_seconds,
# required (comma-separated category list for THIS host).

REQUIRED = [c for c in required.split(",") if c != ""]

def _category(name):
    if name == "disk":
        return "disk"
    if name == "smart_device":
        return "smart"
    if name == "systemd_health":
        return "failed_units"
    if name == "zpool_health":
        return "zpool"
    if name == "ping":
        return "internet"
    if name == "ssh_cert":
        return "ssh_cert"
    return None

def _tag(metric, key):
    if key in metric.tags:
        return metric.tags[key]
    return "?"

def _smart_bad(f):
    if "exit_status" in f and f["exit_status"] > 0:
        return True
    if "pending_sector_count" in f and f["pending_sector_count"] > 0:
        return True
    if "reallocated_sectors_count" in f and f["reallocated_sectors_count"] > 0:
        return True
    if "uncorrectable_sector_count" in f and f["uncorrectable_sector_count"] > 0:
        return True
    if "udma_crc_errors" in f and f["udma_crc_errors"] > 0:
        return True
    if "media_errors" in f and f["media_errors"] > 0:
        return True
    if "critical_warning" in f and f["critical_warning"] > 0:
        return True
    if "available_spare" in f and f["available_spare"] <= 10:
        return True
    if "percentage_used" in f and f["percentage_used"] > 90:
        return True
    if "percent_lifetime_remain" in f and f["percent_lifetime_remain"] < 10:
        return True
    return False

def _evaluate(metric, cat):
    f = metric.fields
    if cat == "disk":
        used = f["used_percent"] if "used_percent" in f else 0.0
        return ("disk:" + _tag(metric, "path"), used >= disk_full)
    if cat == "smart":
        return ("smart:" + _tag(metric, "device"), _smart_bad(f))
    if cat == "failed_units":
        n = f["failed_units"] if "failed_units" in f else 0
        return ("failed_units", n > 0)
    if cat == "zpool":
        deg = f["degraded"] if "degraded" in f else 0
        cap = f["capacity"] if "capacity" in f else 0
        return ("zpool:" + _tag(metric, "pool"), deg > 0 or cap >= disk_full)
    if cat == "internet":
        loss = f["percent_packet_loss"] if "percent_packet_loss" in f else 0.0
        return ("internet", loss >= 100.0)
    if cat == "ssh_cert":
        secs = f["expiry_seconds"] if "expiry_seconds" in f else ssh_cert_min_seconds
        return ("ssh_cert", secs < ssh_cert_min_seconds)
    return (None, False)

def add(metric):
    if metric.time > state.get("now", 0):
        state["now"] = metric.time

    cat = _category(metric.name)
    if cat == None:
        return

    # A real signal has landed; see push() for why this primes the verdict.
    state["primed"] = True

    seen = state.get("seen", {})
    seen[cat] = metric.time
    state["seen"] = seen

    key, failed = _evaluate(metric, cat)
    if key == None:
        return
    inst = state.get("inst", {})
    inst[key] = [failed, metric.time]
    state["inst"] = inst

def push():
    # Cold start: until the first gather lands, stay silent instead of emitting an
    # all-stale /fail. State is in-memory, so every process start (boot, restart)
    # begins unprimed — this prevents a spurious failure on each reboot.
    if not state.get("primed", False):
        return []

    now = state.get("now", 0)
    ttl_ns = ttl_seconds * 1000000000

    inst = state.get("inst", {})
    fresh = {}
    for k in inst:
        if now - inst[k][1] <= ttl_ns:
            fresh[k] = inst[k]
    state["inst"] = fresh

    seen = state.get("seen", {})
    fresh_seen = {}
    for c in seen:
        if now - seen[c] <= ttl_ns:
            fresh_seen[c] = seen[c]
    state["seen"] = fresh_seen

    fails = []
    oks = []
    for k in fresh:
        if fresh[k][0]:
            fails.append(k)
        else:
            oks.append(k)
    for c in REQUIRED:
        if c not in fresh_seen:
            fails.append("stale:" + c)

    lines = []
    for k in sorted(fails):
        lines.append("FAIL " + k)
    for k in sorted(oks):
        lines.append("OK   " + k)

    m = Metric("health")
    m.tags["result"] = "fail" if len(fails) > 0 else "ok"
    m.fields["message"] = "\n".join(lines)
    m.fields["failed"] = len(fails)
    return [m]

def reset():
    pass
