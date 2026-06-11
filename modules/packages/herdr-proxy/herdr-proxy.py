import json
import os
import socket

REAL_SOCKET = os.environ["REAL_SOCKET"]


def get_listen_socket():
    try:
        return socket.fromfd(3, socket.AF_UNIX, socket.SOCK_STREAM)
    except OSError as e:
        raise RuntimeError("No systemd-passed listening socket on fd 3") from e


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

        if message.get("method") != "pane.report_agent_session":
            return

        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as upstream:
            upstream.connect(REAL_SOCKET)
            upstream.sendall(data)
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
            handle_client(client)


if __name__ == "__main__":
    main()
