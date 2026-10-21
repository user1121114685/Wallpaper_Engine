import queue
import subprocess
import sys
import threading
import time
from pathlib import Path


def pump(stream, messages):
    while True:
        chunk = stream.read1(4096)
        if not chunk:
            return
        messages.put(chunk)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: native_smoke_test.py <steamcmd_worker.exe> <steamcmd_fixture.exe>")
    launcher, fixture = map(lambda name: str(Path(name).resolve()), sys.argv[1:])
    process = subprocess.Popen(
        [launcher, fixture],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        creationflags=subprocess.CREATE_NO_WINDOW,
    )
    output = queue.Queue()
    errors = queue.Queue()
    readers = [
        threading.Thread(target=pump, args=(process.stdout, output), daemon=True),
        threading.Thread(target=pump, args=(process.stderr, errors), daemon=True),
    ]
    for reader in readers:
        reader.start()

    captured = bytearray()
    error_output = bytearray()
    deadline = time.monotonic() + 20
    submitted = False
    while process.poll() is None and time.monotonic() < deadline:
        try:
            captured.extend(output.get(timeout=0.1))
        except queue.Empty:
            pass
        while not errors.empty():
            error_output.extend(errors.get_nowait())
        if not submitted and b"Steam Guard code: " in captured:
            time.sleep(0.25)
            if process.poll() is None:
                try:
                    process.stdin.write(b"AB12C\n")
                    process.stdin.flush()
                    submitted = True
                except OSError as error:
                    error_output.extend(str(error).encode())
                    break

    if process.poll() is None:
        process.kill()
        process.wait()
        raise AssertionError("fixture timed out waiting for hooked child input")

    captured.extend(process.stdout.read())
    error_output.extend(process.stderr.read())
    for reader in readers:
        reader.join(timeout=1)
    text = captured.decode("utf-8", errors="replace")
    stderr = error_output.decode("utf-8", errors="replace")
    expected = [
        "[fixture] starting the x64 SteamCMD process",
        "[fixture] ANSI log: " + "\u9a8c\u8bc1\u7801\u5904\u7406\u901a\u8fc7",
        "Steam Guard code: ",
        "[fixture] input received after child relaunch: AB12C",
        "[hook] attached to SteamCMD process",
    ]
    attached_processes = text.count("[hook] attached to SteamCMD process")
    missing = [marker for marker in expected if marker not in text]
    if not submitted or attached_processes < 2 or missing or process.returncode != 0:
        raise AssertionError(
            f"code={process.returncode}, submitted={submitted}, missing={missing}\n"
            f"stdout={text!r}\nstderr={stderr!r}"
        )
    print(text, end="")
    print(f"native hook smoke: exit={process.returncode}; guard code sent after live prompt")


if __name__ == "__main__":
    main()
