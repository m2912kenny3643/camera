"""Create and boot a dedicated, available iPhone 17 simulator for the UI job."""
import json
import os
from pathlib import Path
import subprocess


def query(kind):
    return json.loads(subprocess.check_output(["xcrun", "simctl", "list", kind, "--json"], text=True))


def prepare():
    devices = query("devicetypes")["devicetypes"]
    device_type = next(item["identifier"] for item in devices if item["name"] == "iPhone 17")
    runtimes = [item for item in query("runtimes")["runtimes"]
                if item.get("isAvailable") and "SimRuntime.iOS-" in item["identifier"]
                and item["version"].split(".")[0] == "27"]
    if not runtimes:
        raise RuntimeError("No available iOS 27 simulator runtime")
    runtime = max(runtimes, key=lambda item: tuple(int(part) for part in item["version"].split(".")))
    simulator = subprocess.check_output(
        ["xcrun", "simctl", "create", "R6Camera-CI", device_type, runtime["identifier"]], text=True
    ).strip()
    print(f"Dedicated simulator: {simulator}; runtime {runtime['version']}", flush=True)
    subprocess.run(["xcrun", "simctl", "boot", simulator], check=True, timeout=60)
    subprocess.run(["xcrun", "simctl", "bootstatus", simulator, "-b"], check=True, timeout=300)
    with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as stream:
        stream.write(f"R6_SIMULATOR_UDID={simulator}\n")


if __name__ == "__main__":
    prepare()
