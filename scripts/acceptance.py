#!/usr/bin/env python3
"""Public CLI acceptance with synthetic contacts, real SQLite, and owned storage."""
import argparse
import contextlib
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    return str(path)


@contextlib.contextmanager
def service(tool, backend, root):
    data = root / "remote"
    data.mkdir()
    if backend == "s3":
        (data / "contacts-test").mkdir()
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    command = [str(tool), "serve", backend, str(data), "--addr", f"127.0.0.1:{port}", "--config", os.devnull]
    command += ["--user", "fixture", "--pass", "fixture-secret"] if backend == "webdav" else ["--auth-key", "fixture,fixture-secret"]
    with (root / "server.log").open("w") as log:
        proc = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                env={"PATH": os.environ["PATH"], "LANG": "C.UTF-8"})
        try:
            for _ in range(100):
                if proc.poll() is not None:
                    raise AssertionError((root / "server.log").read_text())
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                        break
                except OSError:
                    time.sleep(0.1)
            else:
                raise AssertionError("service did not become ready")
            yield f"http://127.0.0.1:{port}"
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
            print(f"CLEANUP {backend} owned service reaped", flush=True)


def exercise(binary, root, backend, endpoint=None):
    env = {"PATH": os.environ["PATH"], "CW_TEST_USER": "fixture", "CW_TEST_SECRET": "fixture-secret"}
    if backend == "fs":
        remote = root / "remote"
        remote.mkdir()
        config = {"type": "fs", "root": str(remote)}
    elif backend == "webdav":
        config = {"type": "webdav", "endpoint": endpoint, "username_env": "CW_TEST_USER", "password_env": "CW_TEST_SECRET", "allow_loopback_http": True}
    else:
        config = {"type": "s3", "endpoint": endpoint, "region": "us-east-1", "bucket": "contacts-test", "access_key_env": "CW_TEST_USER", "secret_key_env": "CW_TEST_SECRET", "allow_loopback_http": True}
    config_file = write(root / "backend.json", config)
    count = 0

    def cli(home, *args, exits=(0,), override=None):
        nonlocal count
        p = subprocess.run([str(binary), str(root / home), *map(str, args)], text=True, capture_output=True, env=override or env, timeout=90)
        assert p.returncode in exits, (args, p.returncode, p.stdout, p.stderr)
        assert "fixture-secret" not in p.stdout + p.stderr
        count += 1
        value = json.loads(p.stdout if p.returncode in (0, 5) else p.stderr)
        return value.get("result", value.get("error"))

    def sync(home):
        return cli(home, "sync", config_file, exits=(0, 5))

    def converge(*homes):
        for home in (*homes, *homes):
            sync(home)

    a = cli("a", "init")
    b = cli("b", "init", a["dataset"])
    c = cli("c", "init", a["dataset"])
    assert len({a["device"], b["device"], c["device"]}) == 3
    data = {"version": 2, "display_name": "测试联系人 Élodie", "given_name": "Élodie", "middle_name": "MiddleOnly", "family_name": "测试", "phones": [{"label": "mobile", "value": "+1 555 0100"}, {"label": "work", "value": "010-1234"}], "emails": [{"label": "work", "value": "fixture@example.invalid"}], "organization": "Example", "notes": "仅为合成样本", "dates": [{"kind": "birthday", "label": "生日", "calendar": "chinese_lunar", "year": None, "month": 2, "day": 29, "is_leap_month": True}, {"kind": "birthday", "label": "公历生日", "calendar": "gregorian", "year": 2024, "month": 2, "day": 29, "is_leap_month": False}]}
    expanded = {
        "name_prefix": "PrefixOnly", "name_suffix": "SuffixOnly",
        "phonetic_family_name": "PhoneticFamilyOnly", "phonetic_middle_name": "PhoneticMiddleOnly",
        "phonetic_given_name": "PhoneticGivenOnly", "nickname": "NicknameOnly", "job_title": "JobOnly",
        "website": "https://websiteonly.invalid", "addresses": [{"label": "住宅", "value": "AddressOnly"}],
        "instant_messages": [{"label": "微信", "value": "AccountOnly"}],
        "relations": [{"label": "朋友", "value": "RelationOnly"}],
    }
    data.update(expanded)
    source = write(root / "contact.json", data)
    contact = cli("a", "create", source)
    key = contact["id"]
    assert cli("a", "get", key)["contact"]["data"] == data
    assert cli("a", "info") == a
    assert len(cli("a", "list", "ÉLODIE")["contacts"]) == 1
    assert len(cli("a", "list", "middleonly")["contacts"]) == 1
    assert len(cli("a", "list", "010-1234")["contacts"]) == 1
    assert cli("a", "list", "no-match")["contacts"] == []
    for value in expanded.values():
        needle = value[0]["value"] if isinstance(value, list) else value
        assert len(cli("a", "list", needle.lower())["contacts"]) == 1
    before = cli("a", "status")
    for invalid in [dict(data, middle_name="x" * 1025), dict(data, dates=[data["dates"][0], data["dates"][0]]), dict(data, dates=[dict(data["dates"][1], kind="unknown")]), dict(data, dates=[{k: v for k, v in data["dates"][0].items() if k != "kind"}]), dict(data, dates=[dict(data["dates"][0], kind="custom", label="")]), dict(data, dates=[dict(data["dates"][0], year=2024)]), dict(data, dates=[dict(data["dates"][0], year=2025, month=6, day=30)]), dict(data, dates=[dict(data["dates"][0], year=1900)]), dict(data, unexpected=True), dict(data, version=1), dict(data, display_name=""), dict(data, dates=[dict(data["dates"][1], year=2023)]), dict(data, notes="x" * 65537)]:
        cli("a", "update", key, write(root / "invalid.json", invalid), exits=(2,))
        assert cli("a", "status") == before
    for field, value in expanded.items():
        invalids = (["汉" * (1366 if field == "website" else 342), "bad\0value"] if isinstance(value, str)
                    else [[{"label": "x", "value": "x"}] * 33,
                          [{"label": "", "value": "x"}], [{"label": "汉" * 43, "value": "x"}],
                          [{"label": "x", "value": "汉" * (1366 if field == "addresses" else 342)}]])
        for invalid in invalids:
            cli("a", "update", key, write(root / "invalid.json", dict(data, **{field: invalid})), exits=(2,))
            assert cli("a", "status") == before
    other = cli("b", "create", source)
    assert other["id"] != key
    converge("a", "b", "c")
    for home in ("a", "b", "c"):
        assert cli(home, "get", key)["contact"]["data"] == data
        assert len(cli(home, "list")["contacts"]) == 2
        assert cli(home, "status")["settled"]
    assert sync("a")["uploaded"] == 0
    assert len(cli("a", "list", "", 1, 1)["contacts"]) == 1

    # Two edits and a third offline edit arriving after the observed conflict.
    for home in ("a", "b", "c"):
        cli(home, "update", key, write(root / f"{home}.json", dict(data, notes=home, job_title="Job-"+home, relations=[{"label":"朋友","value":"Relation-"+home}], dates=[dict(data["dates"][0], kind="anniversary" if home == "a" else "custom", label=home), data["dates"][1]])))
    converge("a", "b")
    conflict = cli("a", "conflicts")[0]
    assert len(conflict["candidates"]) == 2
    assert {v["contact"]["data"]["notes"] for v in conflict["candidates"]} == {"a", "b"}
    assert {v["contact"]["data"]["job_title"] for v in conflict["candidates"]} == {"Job-a", "Job-b"}
    assert {v["contact"]["data"]["relations"][0]["value"] for v in conflict["candidates"]} == {"Relation-a", "Relation-b"}
    assert all(v["contact"]["data"]["website"] == expanded["website"] for v in conflict["candidates"])
    assert not cli("a", "status")["settled"]
    cli("a", "update", key, source, exits=(3,))
    cli("a", "delete", key, exits=(3,))
    observed = [v["version"] for v in conflict["candidates"]]
    before = cli("a", "status")
    cli("a", "resolve", key, write(root / "missing-contact.json", {"observed": observed}), exits=(2,))
    assert cli("a", "status") == before
    sync("c")
    sync("a")
    assert len(cli("a", "conflicts")[0]["candidates"]) == 3
    resolution = write(root / "resolve.json", {"observed": observed, "contact": dict(data, notes="merged")})
    cli("a", "resolve", key, resolution)
    assert len(cli("a", "conflicts")[0]["candidates"]) == 2
    conflict = cli("a", "conflicts")[0]
    assert {v["contact"]["data"]["notes"] for v in conflict["candidates"]} == {"c", "merged"}
    resolution = write(root / "resolve.json", {"observed": [v["version"] for v in conflict["candidates"]], "contact": data})
    cli("a", "resolve", key, resolution)
    converge("a", "b", "c")
    assert all(cli(home, "conflicts") == [] for home in ("a", "b", "c"))
    assert all(cli(home, "get", key)["contact"]["data"] == data for home in ("a", "b", "c"))

    # Delete versus update must retain a tombstone candidate.
    cli("a", "delete", key)
    cli("b", "update", key, write(root / "b.json", dict(data, notes="after delete")))
    converge("a", "b")
    conflict = cli("a", "conflicts")[0]
    assert len(conflict["candidates"]) == 2
    assert any(v["contact"] is None for v in conflict["candidates"])
    assert cli("a", "get", key)["conflict"] is not None
    assert cli("a", "list")["conflicts"]
    cli("a", "delete", key, exits=(3,))
    resolution = write(root / "resolve.json", {"observed": [v["version"] for v in conflict["candidates"]], "contact": None})
    cli("a", "resolve", key, resolution)
    converge("a", "b", "c")
    cli("b", "get", key, exits=(2,))
    assert cli("b", "conflicts") == []

    # Local writes survive a real transport/authentication failure.
    cli("a", "create", source)
    pending = cli("a", "status")["pending_outbox"]
    if backend == "fs":
        bad = write(root / "bad.json", {"type": "fs", "root": str(root / "missing")})
        cli("a", "sync", bad, exits=(4,))
    else:
        cli("a", "sync", config_file, override=dict(env, CW_TEST_SECRET="wrong-password"), exits=(4, 5))
    assert cli("a", "status")["pending_outbox"] == pending
    converge("a", "b")
    assert cli("a", "status")["settled"]
    assert cli("a", "list") == cli("b", "list")
    assert sync("b")["uploaded"] == 0

    # Identity mismatch and missing configuration fail without silently creating a new store.
    identity_file = root / "a" / "identity.json"
    write(identity_file, dict(a, dataset="wrong-dataset"))
    assert cli("a", "status", exits=(4,))["code"] == "identity_mismatch"
    write(identity_file, a)
    identity_file.rename(identity_file.with_suffix(".saved"))
    cli("a", "status", exits=(4,))
    cli("a", "init", exits=(4,))
    identity_file.with_suffix(".saved").rename(identity_file)
    assert cli("a", "info") == a
    print(f"PASS {backend}: {count} CLI calls; CRUD/reopen/dates/three-device/conflicts/stale-resolution/delete/retry/identity", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", type=Path, default=Path("target/debug/card-weave"))
    parser.add_argument("--backend", choices=["fs", "webdav", "s3"], default="fs")
    parser.add_argument("--rclone", type=Path)
    args = parser.parse_args()
    binary = args.bin.resolve()
    if args.backend != "fs" and not args.rclone:
        parser.error("HTTP backend requires --rclone")
    with tempfile.TemporaryDirectory(prefix="card-weave-acceptance-") as tmp:
        root = Path(tmp)
        if args.backend == "fs":
            exercise(binary, root, args.backend)
        else:
            subprocess.run([str(args.rclone.resolve()), "version", "--config", os.devnull], check=True)
            with service(args.rclone.resolve(), args.backend, root) as endpoint:
                exercise(binary, root, args.backend, endpoint)
    print("CLEANUP fixture directory removed", flush=True)


if __name__ == "__main__":
    main()
