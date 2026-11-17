"""Exercise real clients on loopback, with disposable profiles and tiny torrents."""

import contextlib
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import xmlrpc.client


def bencode(value):
    if isinstance(value, int):
        return b"i" + str(value).encode() + b"e"
    if isinstance(value, bytes):
        return str(len(value)).encode() + b":" + value
    if isinstance(value, list):
        return b"l" + b"".join(map(bencode, value)) + b"e"
    return b"d" + b"".join(bencode(k) + bencode(v) for k, v in sorted(value.items())) + b"e"


def port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_for(description, predicate, timeout=90):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = predicate()
            if last:
                return last
        except (OSError, ValueError, xmlrpc.client.Error) as error:
            last = error
        time.sleep(0.2)
    raise AssertionError(f"Timed out: {description}; last result: {last!r}")


class Qbit:
    def __init__(self, root, binary, settings):
        self.root = root
        self.binary = binary
        self.web_port = port()
        self.peer_port = port()
        config = root / "profile/qBittorrent/config/qBittorrent.conf"
        config.parent.mkdir(parents=True)
        config.write_text(
            "[LegalNotice]\nAccepted=true\n[BitTorrent]\n"
            "Session\\DHTEnabled=false\nSession\\LSDEnabled=false\n"
            "Session\\PeXEnabled=false\nSession\\QueueingSystemEnabled=false\n"
            "Session\\IgnoreSlowTorrentsForQueueing=false\n"
            + "".join(
                f"Session\\{key}={str(value).lower() if isinstance(value, bool) else value}\n"
                for key, value in settings.items()
            )
            + "[Preferences]\nWebUI\\LocalHostAuth=false\n"
            "WebUI\\HostHeaderValidation=false\nWebUI\\CSRFProtection=false\n"
        )

    def request(self, endpoint, fields=None, torrent=None):
        headers = {}
        data = None
        if torrent is not None:
            boundary = "torrent-storage-test"
            parts = []
            for key, value in (fields or {}).items():
                parts.append(
                    f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode()
                )
            parts.append(
                f'--{boundary}\r\nContent-Disposition: form-data; name="torrents"; filename="fixture.torrent"\r\n'
                "Content-Type: application/x-bittorrent\r\n\r\n".encode()
                + torrent
                + f"\r\n--{boundary}--\r\n".encode()
            )
            data = b"".join(parts)
            headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
        elif fields is not None:
            data = urllib.parse.urlencode(fields).encode()
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.web_port}/api/v2/{endpoint}", data=data, headers=headers
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.read()

    @contextlib.contextmanager
    def running(self):
        with process(
            self.root,
            [self.binary, f"--profile={self.root / 'profile'}", f"--webui-port={self.web_port}",
             f"--torrenting-port={self.peer_port}"],
        ) as child:
            wait_for("qBittorrent ready", lambda: self.request("app/version"))
            yield self
            # Ask the application to flush resume data before testing a clean
            # restart. Signals are only the failure-cleanup fallback below.
            self.request("app/shutdown", {})
            child.wait(timeout=30)

    def info(self, info_hash):
        torrents = json.loads(self.request(f"torrents/info?hashes={info_hash}"))
        return torrents[0] if torrents else {}


@contextlib.contextmanager
def process(root, command):
    root.mkdir(parents=True, exist_ok=True)
    env = os.environ | {"HOME": str(root), "XDG_CONFIG_HOME": str(root / "config")}
    with (root / "process.log").open("w+") as log:
        child = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            yield child
        except BaseException:
            log.seek(0)
            print(log.read(), file=sys.stderr)
            raise
        finally:
            child.send_signal(signal.SIGINT)
            try:
                child.wait(timeout=20)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


class Rtorrent:
    def __init__(self, root, binary, config_text):
        self.root, self.binary = root, binary
        root.mkdir(parents=True)
        self.completed = root / "finished"
        for directory in ("session", "download", "finished"):
            (root / directory).mkdir()
        self.socket = root / "rpc.sock"
        self.config = root / "rtorrent.rc"
        peer_port = port()
        self.config.write_text(
            f"directory.default.set = {root}/download\nsession.path.set = {root}/session\n"
            f"scgi_local = {self.socket}\nnetwork.port_range.set = {peer_port}-{peer_port}\n"
            "network.bind_address.set = 127.0.0.1\n"
            f"log.execute = {root}/execute.log\nlog.open_file = test,{root}/rtorrent.log\n"
            "log.add_output = info,test\n"
            "dht.mode.set = disable\nprotocol.pex.set = no\ntrackers.use_udp.set = no\n"
            "pieces.hash.on_completion.set = no\n"
            + config_text.replace("/var/lib/torrents", str(root))
        )

    def rpc(self, method, *args):
        body = xmlrpc.client.dumps(args, methodname=method).encode()
        headers = b"CONTENT_LENGTH\0" + str(len(body)).encode() + b"\0SCGI\x001\0"
        with socket.socket(socket.AF_UNIX) as sock:
            sock.settimeout(5)
            sock.connect(str(self.socket))
            sock.sendall(str(len(headers)).encode() + b":" + headers + b"," + body)
            data = b""
            while chunk := sock.recv(65536):
                data += chunk
        return xmlrpc.client.loads(data.split(b"\r\n\r\n", 1)[1])[0][0]

    @contextlib.contextmanager
    def running(self):
        with process(self.root, [self.binary, "-n", "-o", "system.daemon.set=true", "-o", f"import={self.config}"]) as child:
            def ready():
                if child.poll() is not None:
                    raise RuntimeError(f"rTorrent exited with {child.returncode}")
                return self.rpc("system.client_version")
            wait_for("rTorrent ready", ready)
            yield self


def main():
    qbit_binary, rtorrent_binary, settings_file, rtorrent_config = sys.argv[1:]
    settings = json.loads(Path(settings_file).read_text())
    with tempfile.TemporaryDirectory(prefix="torrent-storage-") as temporary:
        root = Path(temporary)

        def fixture(directory, name, multi=False):
            payload = (b"local completion test\n" * 4096)
            info = {
                b"name": name.encode(), b"piece length": 16384, b"private": 1,
                b"pieces": b"".join(hashlib.sha1(payload[i:i + 16384]).digest()
                                    for i in range(0, len(payload), 16384)),
            }
            if multi:
                info[b"files"] = [{b"length": len(payload), b"path": [b"episode.mkv"]}]
                target = directory / name / "episode.mkv"
            else:
                info[b"length"] = len(payload)
                target = directory / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(payload)
            torrent = bencode({b"info": info})
            info_hash = hashlib.sha1(bencode(info)).hexdigest()
            return torrent, info_hash, payload

        # Completion is driven by the real clients' hash checks. No external
        # tracker/peers are needed, and the result is independent of networking.
        qbit_root = root / "qbit"
        mapped = {key: value.replace("/data", str(qbit_root)) if isinstance(value, str) else value
                  for key, value in settings.items() if key != "Port"}
        downloader = Qbit(qbit_root, qbit_binary, mapped)
        torrent, info_hash, payload = fixture(qbit_root / "torrents/incomplete", "qbit movie.mkv")
        with downloader.running():
            downloader.request("torrents/add", {}, torrent)
            wait_for("qBittorrent complete", lambda: downloader.info(info_hash).get("progress") == 1)
            target = qbit_root / "torrents/completed/qbit movie.mkv"
            wait_for("qBittorrent final path", target.exists)
            assert target.read_bytes() == payload
            assert not (qbit_root / "torrents/incomplete/qbit movie.mkv").exists()
            wait_for("qBittorrent seeding", lambda: downloader.info(info_hash)["state"] in ("uploading", "stalledUP"))
        with downloader.running():
            wait_for("qBittorrent seed after restart", lambda: downloader.info(info_hash).get("progress") == 1)
            assert Path(downloader.info(info_hash)["content_path"]) == target
        print("PASS: qBittorrent completes, relocates and resumes seeding")

        rtorrent = Rtorrent(root / "rtorrent", rtorrent_binary, Path(rtorrent_config).read_text())
        with rtorrent.running():
            for name, multi in (("rtorrent movie.mkv", False), ("rtorrent series", True)):
                torrent, info_hash, payload = fixture(rtorrent.root / "download", name, multi)
                metafile = root / f"{name}.torrent"
                metafile.write_bytes(torrent)
                rtorrent.rpc("load.start", "", str(metafile))
                wait_for("rTorrent hash check", lambda: rtorrent.rpc("d.complete", info_hash))
                # Loading already-complete data is treated as an existing seed
                # (and deliberately does not fire finished). Exercise the public
                # completion event explicitly after verifying the fixture data.
                rtorrent.rpc("event.download.finished", info_hash)
                target = rtorrent.completed / name
                data_file = target / "episode.mkv" if multi else target
                try:
                    wait_for("rTorrent completed relocation", data_file.exists, 15)
                except AssertionError:
                    print("rTorrent status:", {key: rtorrent.rpc(key, info_hash) for key in (
                        "d.complete", "d.directory", "d.state", "d.message", "d.completion_source",
                    )}, file=sys.stderr)
                    for logfile in rtorrent.root.glob("*.log"):
                        print(logfile.name, logfile.read_text(), file=sys.stderr)
                    raise
                assert data_file.read_bytes() == payload
                wait_for("rTorrent seeding", lambda: rtorrent.rpc("d.is_active", info_hash))
                assert Path(rtorrent.rpc("d.base_path", info_hash)) == target
                assert not (rtorrent.root / "download" / name).exists()
            name = "labelled game.nsp"
            torrent, labelled_hash, payload = fixture(rtorrent.root / "download", name)
            metafile = root / "labelled.torrent"
            metafile.write_bytes(torrent)
            rtorrent.rpc("load.start", "", str(metafile), "d.custom1.set=switch")
            wait_for("labelled fixture ready", lambda: rtorrent.rpc("d.complete", labelled_hash))
            rtorrent.rpc("event.download.finished", labelled_hash)
            labelled_target = rtorrent.completed / "switch" / name
            assert labelled_target.exists(), "Completed torrent must use its Flood label as the folder"
            assert labelled_target.read_bytes() == payload
            assert rtorrent.rpc("d.custom1", labelled_hash) == "switch"
            assert Path(rtorrent.rpc("d.base_path", labelled_hash)) == labelled_target
            for name, encoded_label, folder in (
                ("encoded label.nsp", "Games%2C%20Switch", "Games, Switch"),
                ("unicode label.nsp", "%D0%98%D0%B3%D1%80%D1%8B", "Игры"),
            ):
                torrent, encoded_hash, payload = fixture(rtorrent.root / "download", name)
                metafile = root / f"{name}.torrent"
                metafile.write_bytes(torrent)
                rtorrent.rpc("load.start", "", str(metafile), f"d.custom1.set={encoded_label}")
                wait_for("encoded label fixture ready", lambda: rtorrent.rpc("d.complete", encoded_hash))
                rtorrent.rpc("event.download.finished", encoded_hash)
                destination = rtorrent.completed / folder / name
                assert destination.read_bytes() == payload
                assert Path(rtorrent.rpc("d.base_path", encoded_hash)) == destination
                assert rtorrent.rpc("d.custom1", encoded_hash) == encoded_label
        with rtorrent.running():
            wait_for("rTorrent seed after restart", lambda: rtorrent.rpc("d.is_active", info_hash))
            assert Path(rtorrent.rpc("d.base_path", info_hash)) == target
            assert Path(rtorrent.rpc("d.base_path", labelled_hash)) == labelled_target
            # Rechecks / repeated completion events must not move seeds again.
            rtorrent.rpc("event.download.finished", info_hash)
            assert data_file.read_bytes() == payload

            # A pre-existing destination is never merged or overwritten. On
            # failure the original tracked path is retained and seeding stops.
            name = "existing destination.mkv"
            torrent, info_hash, payload = fixture(rtorrent.root / "download", name)
            metafile = root / "collision.torrent"
            metafile.write_bytes(torrent)
            target = rtorrent.completed / name
            target.write_bytes(b"keep existing content")
            rtorrent.rpc("load.start", "", str(metafile))
            wait_for("collision fixture ready", lambda: rtorrent.rpc("d.complete", info_hash))
            try:
                rtorrent.rpc("event.download.finished", info_hash)
            except xmlrpc.client.Fault:
                pass
            else:
                raise AssertionError("Completion must report the destination collision")
            assert target.read_bytes() == b"keep existing content"
            assert (rtorrent.root / "download" / name).read_bytes() == payload
            assert rtorrent.rpc("d.directory", info_hash) == str(rtorrent.root / "download")
            assert rtorrent.rpc("d.is_active", info_hash) == 0

            # A torrent explicitly saved elsewhere stays there.
            custom = rtorrent.root / "custom"
            torrent, info_hash, payload = fixture(custom, "custom destination.mkv")
            metafile = root / "custom.torrent"
            metafile.write_bytes(torrent)
            rtorrent.rpc("load.start", "", str(metafile), f"d.directory.set={custom}")
            wait_for("custom fixture ready", lambda: rtorrent.rpc("d.complete", info_hash))
            rtorrent.rpc("event.download.finished", info_hash)
            assert (custom / "custom destination.mkv").read_bytes() == payload
            assert rtorrent.rpc("d.is_active", info_hash) == 1
            outside = rtorrent.root / "outside"
            outside.mkdir()
            (rtorrent.completed / "linked").symlink_to(outside, target_is_directory=True)
            for index, unsafe_label in enumerate((
                "switch,Books", "%2e%2e%2foutside", "%2Ftmp", "bad%0Alabel", "linked",
            )):
                name = f"unsafe label {index}.nsp"
                torrent, unsafe_hash, payload = fixture(rtorrent.root / "download", name)
                metafile = root / f"{name}.torrent"
                metafile.write_bytes(torrent)
                rtorrent.rpc("load.start", "", str(metafile))
                wait_for("unsafe label fixture ready", lambda: rtorrent.rpc("d.complete", unsafe_hash), 15)
                rtorrent.rpc("d.custom1.set", unsafe_hash, unsafe_label)
                try:
                    rtorrent.rpc("event.download.finished", unsafe_hash)
                except xmlrpc.client.Fault:
                    pass
                else:
                    raise AssertionError("Unsafe or ambiguous label must not move data")
                assert (rtorrent.root / "download" / name).read_bytes() == payload
                assert rtorrent.rpc("d.is_active", unsafe_hash) == 1
                assert not (outside / name).exists()
        print("PASS: rTorrent single/multi-file completion and restart preserve seeding")
        print("PASS: rTorrent refuses collisions and preserves custom paths")
        print("PASS: Flood labels route completed data; unsafe or ambiguous labels do not move it")


if __name__ == "__main__":
    main()
