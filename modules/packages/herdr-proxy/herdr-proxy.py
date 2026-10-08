import json
import os
import re
import socket

REAL_SOCKET = os.environ["REAL_SOCKET"]
TIMEOUT = 2

CLAUDE_HOOKS_SOURCE = "local:claude-hooks"
SESSION_ID = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
)

# Allowlisted keys, so fields added by newer herdr (0.9.2's resume_argv runs
# on the host at restore) are rejected until reviewed.
ALLOWED = {
    "pane.report_agent": {
        "sources": {CLAUDE_HOOKS_SOURCE},
        "keys": {
            "pane_id",
            "source",
            "agent",
            "state",
            "message",
            "seq",
            "agent_session_id",
            "agent_session_path",
        },
    },
    "pane.report_agent_session": {
        # herdr's own SessionStart hook reports as herdr:claude
        "sources": {"herdr:claude", CLAUDE_HOOKS_SOURCE},
        "keys": {
            "pane_id",
            "source",
            "agent",
            "seq",
            "agent_session_id",
            "agent_session_path",
            "session_start_source",
            "status",
        },
    },
    "pane.release_agent": {
        "sources": {CLAUDE_HOOKS_SOURCE},
        "keys": {"pane_id", "source", "agent", "seq"},
    },
}


class Rejected(Exception):
    pass


def get_listen_socket():
    try:
        return socket.fromfd(3, socket.AF_UNIX, socket.SOCK_STREAM)
    except OSError as e:
        raise RuntimeError("No systemd-passed listening socket on fd 3") from e


def check(method, params):
    rules = ALLOWED[method]
    if not isinstance(params, dict):
        raise Rejected("params must be an object")
    unknown = params.keys() - rules["keys"]
    if unknown:
        raise Rejected(f"params not allowed: {', '.join(sorted(unknown))}")
    if params.get("source") not in rules["sources"]:
        allowed = ", ".join(sorted(rules["sources"]))
        raise Rejected(f"source must be one of: {allowed}")
    # herdr turns herdr:claude sessions into `claude --resume <id>` on restore
    if params.get("agent") != "claude":
        raise Rejected("agent must be claude")
    session_id = params.get("agent_session_id")
    if session_id is not None and not (
        isinstance(session_id, str) and SESSION_ID.fullmatch(session_id)
    ):
        raise Rejected("agent_session_id must be a UUID")


def send_error(client, request_id, message):
    response = {
        "id": request_id if isinstance(request_id, str) else "",
        "error": {"code": "forbidden", "message": f"herdr-proxy: {message}"},
    }
    client.sendall(json.dumps(response).encode() + b"\n")


def handle_client(client):
    with client:
        data = b""
        while not data.endswith(b"\n"):
            chunk = client.recv(8192)
            if not chunk:
                return
            data += chunk

        try:
            message = json.loads(data.decode())
        except json.JSONDecodeError:
            return

        if not isinstance(message, dict):
            return

        method = message.get("method")
        if method not in ALLOWED:
            return

        try:
            check(method, message.get("params"))
        except Rejected as e:
            print(f"rejected {method}: {e}", flush=True)
            send_error(client, message.get("id"), str(e))
            return

        # Re-serialize so herdr parses exactly what was checked
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as upstream:
            upstream.settimeout(TIMEOUT)
            upstream.connect(REAL_SOCKET)
            upstream.sendall(json.dumps(message).encode() + b"\n")
            while True:
                response = upstream.recv(8192)
                if not response:
                    break
                client.sendall(response)


def main():
    listen_sock = get_listen_socket()
    with listen_sock:
        while True:
            client, _ = listen_sock.accept()
            # Single-threaded, so a stalled peer would block every other hook
            client.settimeout(TIMEOUT)
            try:
                handle_client(client)
            # herdr's hook hangs up after 0.5s without waiting for the reply
            except (BrokenPipeError, ConnectionResetError):
                print("client disconnected before response", flush=True)
            except TimeoutError:
                print("timed out talking to client or herdr", flush=True)


if __name__ == "__main__":
    main()
